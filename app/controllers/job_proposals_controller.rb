class JobProposalsController < ApplicationController
  ALLOWED_SORTS = %w[created_at proposal_value].freeze
  ALLOWED_DIRS  = %w[asc desc].freeze

  EDITABLE_PARAMS = %i[
    customer_title customer_first_name customer_last_name customer_email
    customer_house_number customer_street customer_city customer_state customer_zip
    internal_reference dash_job_number loss_notes loss_reason_id
    owner_id job_type_id scenario_id proposal_value
  ].freeze

  before_action :load_proposal, only: [:edit, :update, :resume, :pause, :launch_campaign, :mark_won, :mark_lost, :revert_pipeline_stage, :revert_to_edit, :approve, :destroy]
  before_action :load_discarded_proposal, only: [:restore]
  before_action :require_admin, only: [:restore]

  def index
    scope = JobProposal
      .accessible_by(current_ability)
      .includes(:location, :job_type, :owner, :created_by_user)

    @status_options = scope.distinct.pluck(:status).compact.sort
    user_ids = (scope.distinct.pluck(:owner_id) + scope.distinct.pluck(:created_by_user_id)).uniq
    @user_options = User.where(id: user_ids).order(:email)

    @show_location_controls = !current_user.scoped_to_location?
    @location_options = current_user.tenant&.locations&.order(:display_name) || Location.none

    @selected_status = params[:status].presence
    @selected_owner_id = params[:owner_id].presence
    @selected_creator_id = params[:creator_id].presence
    @search = params[:q].to_s.strip
    @needs_attention_only = params[:filter] == "needs_attention"

    if current_user.scoped_to_location?
      scope = scope.where(location_id: current_user.location_id)
    else
      @selected_location_id = params[:location_id].presence
      scope = scope.where(location_id: @selected_location_id) if @selected_location_id
    end

    scope = scope.needs_attention if @needs_attention_only
    scope = scope.where(status: @selected_status) if @selected_status
    scope = scope.where(owner_id: @selected_owner_id) if @selected_owner_id
    scope = scope.where(created_by_user_id: @selected_creator_id) if @selected_creator_id
    scope = apply_search(scope, @search) if @search.present?

    sort_column = ALLOWED_SORTS.include?(params[:sort]) ? params[:sort] : "created_at"
    sort_dir    = ALLOWED_DIRS.include?(params[:dir])  ? params[:dir]  : "desc"

    @job_proposals = scope.order(sort_column => sort_dir, id: :desc)
  end

  def show
    @job_proposal = JobProposal.accessible_by(current_ability).find(params[:id])
    @loss_reason_options = LossReason.ordered
  end

  def new
  end

  def create
    file = params[:file]
    if file.blank?
      flash.now[:alert] = "Please choose a file to upload."
      render :new, status: :unprocessable_content and return
    end

    if current_user.tenant.blank?
      flash.now[:alert] = "Your account isn't yet assigned to a tenant."
      render :new, status: :unprocessable_content and return
    end

    # location_id is NOT NULL and scenario_id is required for campaign
    # readiness. Pre-populate sane defaults so the create succeeds; the
    # operator can correct both on the edit form before approving.
    default_location = current_user.location || current_user.tenant.locations.active.order(:id).first
    default_scenario = current_user.tenant.activated_scenarios.includes(:job_type).order(:id).first ||
                       Scenario.includes(:job_type).order(:id).first
    if default_scenario.nil? || default_location.nil?
      flash.now[:alert] = "Your tenant needs at least one active location and one activated scenario before a proposal can be created."
      render :new, status: :unprocessable_content and return
    end

    proposal = JobProposal.new(
      tenant: current_user.tenant,
      location: default_location,
      owner: current_user,
      created_by_user: current_user,
      job_type: default_scenario.job_type,
      scenario: default_scenario
    )
    attachment = proposal.attachments.build(uploaded_by_user: current_user)
    attachment.file.attach(file)

    if proposal.save
      result = JobProposalProcessor.new(proposal).process
      if result.ai_failed?
        redirect_to edit_job_proposal_path(proposal),
                    alert: "Uploaded, but AI extraction failed (#{result.error}). Fill in the details manually below."
      else
        notice = result.stub? \
          ? "Proposal uploaded. AI extraction is not configured, so fields are filled with sample data — confirm the details below before launching the campaign." \
          : "Proposal uploaded. Confirm the details below to launch the campaign."
        redirect_to edit_job_proposal_path(proposal), notice: notice
      end
    else
      flash.now[:alert] = proposal.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def edit
    set_form_options
  end

  # Operator-driven resume. A campaign reaches a stopped state two ways an
  # operator can walk back: a manual pause, or an automatic stop when the
  # customer replied. "Customer waiting" is not terminal — once the
  # operator has handled the reply in Gmail they can put the proposal back
  # into the automated campaign. The inverse flow is `pause`.
  def resume
    instance = @job_proposal.campaign_instances.order(created_at: :desc).first

    if instance&.status_paused? || instance&.status_stopped_on_reply?
      JobProposal.transaction do
        # A campaign that stopped on a customer reply still has that reply
        # sitting in its Gmail thread. Fold it into the step snapshot so
        # the reply poller treats it as baseline — otherwise the next tick
        # would re-detect the same reply and stop the campaign again.
        absorb_recorded_replies(instance) if instance.status_stopped_on_reply?
        # ended_at cleared so the reply poller's age cutoff treats this as
        # a live campaign again (was set when the campaign stopped).
        instance.update!(status: :active, ended_at: nil)
        @job_proposal.update!(status_overlay: nil)
      end
      redirect_to job_proposal_path(@job_proposal), notice: "Campaign resumed."
    else
      redirect_to job_proposal_path(@job_proposal),
        alert: "This campaign isn't paused or waiting on a customer reply."
    end
  end

  # Operator-driven pause from the proposal show page. Sets the overlay
  # to paused and, if a campaign instance is currently active, flips
  # that instance to paused too so the sweep job stops sending. The
  # inverse flow is `resume`.
  def pause
    instance = @job_proposal.campaign_instances.order(created_at: :desc).first

    JobProposal.transaction do
      instance.update!(status: :paused, ended_at: Time.current) if instance&.status_active?
      @job_proposal.update!(status_overlay: "paused")
    end
    redirect_to job_proposal_path(@job_proposal), notice: "Campaign paused."
  end

  # Manual relaunch from the proposal show page's Campaign card. Used when
  # the automatic launch on update was skipped — usually because the
  # scenario wasn't picked yet at save time, or a downstream automation
  # hiccupped. Idempotent via CampaignLauncher: a second click while
  # an instance already exists reports "already running" instead of
  # creating a duplicate.
  def launch_campaign
    result = CampaignLauncher.launch(@job_proposal)
    case result.reason
    when :launched
      @job_proposal.update!(status: :approving)
      redirect_to job_proposal_campaign_instance_path(@job_proposal, result.instance),
        notice: "Campaign created — review the emails below and click Approve to start sending."
    when :already_running
      instance = @job_proposal.campaign_instances.order(created_at: :desc).first
      redirect_to job_proposal_campaign_instance_path(@job_proposal, instance),
        notice: "Campaign is already running."
    when :not_ready
      missing = result.blockers.map { |b| b[:field] }.join(", ")
      redirect_to edit_job_proposal_path(@job_proposal),
        alert: "Can't launch yet — fill in the missing fields first: #{missing}."
    when :no_campaign
      redirect_to job_proposal_path(@job_proposal),
        alert: "The selected scenario has no campaign attached yet — ask an admin to pick one on the scenario page."
    else
      redirect_to job_proposal_path(@job_proposal),
        alert: "Couldn't launch campaign (#{result.reason})."
    end
  end

  def mark_won
    @job_proposal.update!(pipeline_stage: :won)
    redirect_to job_proposal_path(@job_proposal), notice: "Marked as won."
  end

  def mark_lost
    reason_id = params[:loss_reason_id].presence
    notes     = params[:loss_notes].to_s.strip
    reason    = LossReason.find_by(id: reason_id)
    if reason.nil? || notes.blank?
      redirect_to job_proposal_path(@job_proposal),
        alert: "Loss reason and loss notes are both required to mark a job lost."
      return
    end
    @job_proposal.update!(pipeline_stage: :lost, loss_reason: reason, loss_notes: notes)
    redirect_to job_proposal_path(@job_proposal), notice: "Marked as lost."
  end

  # Back-out from the "Review Campaign" page when the operator spots a
  # mistake in the proposal data. Flips status :approving → :drafting
  # and discards the in-flight drafting CampaignInstance — the next save
  # re-launches a fresh instance against the corrected data, so any
  # previously-rendered step_instance previews don't leak the old values
  # forward. Refuses any other status because there's nothing to revert.
  def revert_to_edit
    unless @job_proposal.status_approving?
      redirect_to edit_job_proposal_path(@job_proposal),
        alert: "This proposal isn't waiting on review — nothing to revert."
      return
    end

    JobProposal.transaction do
      @job_proposal.campaign_instances.where(status: :drafting).destroy_all
      @job_proposal.update!(status: :drafting)
    end
    redirect_to edit_job_proposal_path(@job_proposal),
      notice: "Reverted to editing. Save again to re-launch the campaign with your changes."
  end

  # Undo path for an accidental Mark Won / Mark Lost click. Sets the
  # pipeline back to in_campaign so the operator can re-decide.
  def revert_pipeline_stage
    @job_proposal.update!(pipeline_stage: :in_campaign)
    redirect_to job_proposal_path(@job_proposal), notice: "Reverted to in campaign."
  end

  # Approve from the campaign instance show page. Flips JobProposal.status
  # to approved, which is the gate the CampaignSweepJob checks before
  # sending step instances.
  #
  # Three things happen at approve time:
  #   1. JobProposal.status flips to approved.
  #   2. CampaignInstance.started_at is stamped, and each step instance's
  #      planned_delivery_at is computed by accumulating offset_min across
  #      the sequence (offset_min = delay from the *previous* step,
  #      PRD-03 §6.4).
  #   3. Each step instance's final_subject and final_body are rendered
  #      through MailGenerator and persisted. The sweep job then sends
  #      that frozen copy verbatim — no late re-render. Lock-in time means
  #      later edits to the proposal don't silently change a queued email.
  #
  # If any step's template has unresolved merge fields, the whole approve
  # transaction rolls back and the operator sees the offending step in
  # the alert.
  #
  # Redirects back to the instance the operator was reviewing.
  def approve
    instance = @job_proposal.campaign_instances.order(created_at: :desc).first

    begin
      JobProposal.transaction do
        @job_proposal.update!(status: :approved)
        lock_in_instance!(instance) if instance
      end
    rescue MailGenerator::UnresolvedMergeFieldError => e
      if instance
        redirect_to job_proposal_campaign_instance_path(@job_proposal, instance),
          alert: "Can't approve — a step's template has unresolved merge fields: #{e.message}. Fix the template (admin → campaigns) or the proposal data, then try again."
      else
        redirect_to job_proposal_path(@job_proposal),
          alert: "Can't approve — template render failed: #{e.message}."
      end
      return
    end

    if instance
      redirect_to job_proposal_campaign_instance_path(@job_proposal, instance),
        notice: "Approved — the next sweep will start sending."
    else
      redirect_to job_proposal_path(@job_proposal),
        notice: "Approved."
    end
  end

  # Soft-delete via discard. Available to SMAI staff (via Ability's
  # `:manage, :all`) and tenant admins for proposals in their own tenant
  # (see Ability#initialize). Refuses only while an :active
  # CampaignInstance is on the proposal — see JobProposal#ensure_no_live_campaign!.
  def destroy
    authorize! :destroy, @job_proposal
    if @job_proposal.discard
      redirect_to job_proposals_path, notice: "Job proposal moved to trash."
    else
      redirect_to job_proposal_path(@job_proposal),
        alert: @job_proposal.errors.full_messages.to_sentence.presence || "Couldn't delete this proposal."
    end
  end

  def restore
    @job_proposal.undiscard
    redirect_to job_proposal_path(@job_proposal), notice: "Job proposal restored."
  end

  def update
    if @campaign_in_flight
      set_form_options
      flash.now[:alert] = "This proposal's campaign is already in flight and can't be edited."
      render :edit, status: :unprocessable_content and return
    end

    if @job_proposal.update(proposal_params)
      result = CampaignLauncher.launch(@job_proposal)
      if result.reason == :launched
        @job_proposal.update!(status: :approving)
        redirect_to job_proposal_campaign_instance_path(@job_proposal, result.instance),
          notice: "Proposal saved. Campaign created — review the emails below and click Approve to start sending."
      else
        redirect_to job_proposal_path(@job_proposal), notice: launch_notice(result)
      end
    else
      set_form_options
      flash.now[:alert] = @job_proposal.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  private

  # Resuming a campaign that stopped on a customer reply must not let the
  # reply poller re-trip on that same reply. Each step the poller flagged
  # carries the exact Gmail message in gmail_reply_payload; appending it to
  # the step's send-time thread snapshot makes that message part of the new
  # baseline, so only a *further* reply restarts the stop. Steps with no
  # usable snapshot are simply unflagged — a blank snapshot makes the poller
  # re-baseline from the live thread on its next pass anyway.
  def absorb_recorded_replies(instance)
    instance.step_instances.where(customer_replied: true).find_each do |step|
      snapshot = step.gmail_thread_snapshot
      payload = step.gmail_reply_payload
      if payload.present? && snapshot.is_a?(Hash) && snapshot["messages"].is_a?(Array)
        merged = snapshot.deep_dup
        merged["messages"] << payload
        step.update!(gmail_thread_snapshot: merged, customer_replied: false)
      else
        step.update!(customer_replied: false)
      end
    end
  end

  def lock_in_instance!(instance)
    started_at = Time.current
    # Move the instance out of :drafting on approve so the sweep job picks
    # up the now-stamped step instances. Idempotent if a re-approval lands
    # on an already-active instance.
    new_status = instance.status_drafting? ? :active : instance.status
    instance.update!(started_at: started_at, status: new_status)
    cumulative_minutes = 0
    instance.step_instances
      .joins(:campaign_step)
      .order("campaign_steps.sequence_number")
      .includes(:campaign_step).each do |si|
        cumulative_minutes += si.campaign_step.offset_min.to_i
        rendered = MailGenerator.render(campaign_step: si.campaign_step, job_proposal: @job_proposal)
        si.update!(
          planned_delivery_at: started_at + cumulative_minutes.minutes,
          final_subject:       rendered.subject,
          final_body:          rendered.body
        )
      end
  end

  def load_proposal
    @job_proposal = JobProposal.accessible_by(current_ability).find(params[:id])
    authorize! :update, @job_proposal
    @campaign_in_flight = @job_proposal.campaign_instances.exists?
  end

  # Restore acts on a discarded row that default_scope { kept } hides from
  # a plain `find`. Pull from the unscoped relation so admins can restore
  # proposals the rest of the app treats as gone. Admin-only by the
  # before_action below.
  def load_discarded_proposal
    @job_proposal = JobProposal.with_discarded.find(params[:id])
  end

  def require_admin
    return if current_user&.is_admin
    redirect_to root_path, alert: "You are not authorized to do that."
  end

  def set_form_options
    tenant = @job_proposal.tenant
    @owner_options = tenant.users.order(:email)
    @job_type_options = tenant.activated_job_types.order(:name)
    @scenario_options = tenant.activated_scenarios.includes(:job_type).order("job_types.name", :short_name)
    @location_editable = !current_user.scoped_to_location?
    @location_options = @location_editable ? tenant.locations.order(:display_name) : Location.none
    @loss_reason_options = LossReason.ordered
  end

  def proposal_params
    permitted = EDITABLE_PARAMS.dup
    permitted << :location_id unless current_user.scoped_to_location?
    attrs = params.require(:job_proposal).permit(*permitted)
    # Defense in depth: even when location_id is permitted, drop it unless
    # the picked location belongs to this proposal's tenant.
    if attrs[:location_id].present? &&
       !@job_proposal.tenant.locations.exists?(id: attrs[:location_id])
      attrs = attrs.except(:location_id)
    end
    attrs
  end

  def launch_notice(result)
    case result.reason
    when :launched        then "Proposal saved. Campaign launched."
    when :already_running then "Proposal saved."
    when :not_ready
      missing = result.blockers.map { |b| b[:field] }.join(", ")
      "Proposal saved, but the campaign hasn't started yet — still missing: #{missing}."
    when :no_campaign     then "Proposal saved. The selected scenario has no campaign attached yet — ask an admin."
    else "Proposal saved."
    end
  end

  # Case-insensitive substring match across customer name, address fields,
  # and the internal reference. Single ILIKE pattern reused per column.
  def apply_search(scope, query)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    scope.where(<<~SQL.squish, p: pattern)
      customer_first_name   ILIKE :p OR
      customer_last_name    ILIKE :p OR
      customer_house_number ILIKE :p OR
      customer_street       ILIKE :p OR
      customer_city         ILIKE :p OR
      customer_zip          ILIKE :p OR
      internal_reference    ILIKE :p
    SQL
  end
end
