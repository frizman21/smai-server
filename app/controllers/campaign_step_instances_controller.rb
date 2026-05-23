# Detail page for a single CampaignStepInstance under a job proposal.
# Shows the rendered email exactly as it would (or did) ship: From, To,
# Subject, Body, plus planned-delivery / actual-send timing and status.
#
# Scoping: every action loads the parent JobProposal through
# accessible_by(current_ability) and then asserts the step instance
# belongs to that proposal — protects against guessing IDs across
# tenants.
class CampaignStepInstancesController < ApplicationController
  before_action :load_proposal_and_step_instance

  def show
    prepare_show_view_data
  end

  # On-demand diagnostic: probe the Gmail thread this step opened and surface
  # the API request + response. Authenticates as the proposal originator's
  # connected Gmail — the same credential GmailReplyPollJob uses and the
  # account where the conversation actually lives — so the result
  # reproduces what the production poller sees. URL and response body are
  # logged at info level so Heroku logs always carry the diagnostic trail.
  def check_thread
    delegation = @job_proposal.owner.gmail_delegation
    if delegation.nil?
      flash.now[:alert] = "#{@job_proposal.owner.display_name} hasn't connected their Gmail — no originator credential to probe with. Have them reconnect in Settings → Integrations."
    else
      sender = GmailSender.new(delegation)
      Rails.logger.info "[ThreadCheck] step #{@step_instance.id} probing thread #{@step_instance.gmail_thread_id.inspect} as #{delegation.email} (originator)"
      @thread_probe    = sender.probe_thread(@step_instance.gmail_thread_id)
      @thread_probe_at = Time.current
    end

    prepare_show_view_data
    render :show
  end

  # Development-only diagnostic: enqueue a Sidekiq job that synthesizes a
  # customer reply for this step and runs it through the same handler the
  # real Gmail poller uses. Walks the post-reply state machine end to end —
  # campaign instance flips to :stopped_on_reply, proposal status_overlay
  # to "customer_waiting", proposal lands in Needs Attention — without
  # needing a real inbox. Gated to admin + development at the controller
  # layer, and the job itself refuses in non-dev as a second line.
  def simulate_reply
    unless Rails.env.development? && current_user.is_admin
      redirect_to job_proposal_step_instance_path(@job_proposal, @step_instance),
        alert: "Simulate response is a development-only diagnostic." and return
    end
    unless @step_instance.email_delivery_status_sent?
      redirect_to job_proposal_step_instance_path(@job_proposal, @step_instance),
        alert: "Only sent steps can have a reply simulated against them." and return
    end

    SimulateCustomerReplyJob.perform_later(@step_instance.id)
    redirect_to job_proposal_path(@job_proposal),
      notice: "Simulated customer reply enqueued — refresh in a moment to see the campaign stop and the proposal flip to Customer waiting."
  end

  private

  def prepare_show_view_data
    @campaign_step  = @step_instance.campaign_step
    @sent           = @step_instance.email_delivery_status_sent?

    # For a step that already shipped, final_subject/final_body capture
    # exactly what the customer received — show that. Otherwise (pending,
    # sending, failed before ever queueing copy) render the live template
    # through the same MailGenerator.render the live send uses, so what
    # the preview shows is byte-for-byte what would ship if the step
    # fired right now.
    #
    # render raises UnresolvedMergeFieldError when the template references
    # a merge field this proposal can't provide — a real campaign-config
    # bug (e.g. typo'd token, KNOWN_KEYS missing a binding). We surface
    # the message in a banner and fall back to render_safely so the rest
    # of the page still renders.
    if @sent && @step_instance.final_subject.present?
      @rendered = MailGenerator::Output.new(
        subject: @step_instance.final_subject,
        body:    @step_instance.final_body.to_s
      )
      @rendering_error = nil
    else
      begin
        @rendered = MailGenerator.render(
          campaign_step: @campaign_step,
          job_proposal:  @job_proposal
        )
        @rendering_error = nil
      rescue MailGenerator::UnresolvedMergeFieldError => e
        @rendered = MailGenerator.render_safely(
          campaign_step: @campaign_step,
          job_proposal:  @job_proposal
        )
        @rendering_error = e.message
      end
    end

    # Per PRD-09 §1, the From on a customer send is the proposal originator's
    # own connected Gmail — not the shared ApplicationMailbox. Surface the
    # same address (and owner name for the caption) so this preview matches
    # what actually lands in the customer's inbox. A missing delegation is
    # the same condition PreSendChecklist#check_originator_mailbox flags as
    # a delivery issue; the view shows an explanatory warning in that case.
    owner               = @job_proposal.owner
    @from_address       = owner.gmail_delegation&.email
    @from_display_name  = owner.display_name
    @to_address         = @job_proposal.customer_email.presence
  end

  def load_proposal_and_step_instance
    @job_proposal  = JobProposal.accessible_by(current_ability).find(params[:job_proposal_id])
    @step_instance = CampaignStepInstance.find(params[:id])
    instance = @step_instance.campaign_instance
    unless instance && instance.host_type == "JobProposal" && instance.host_id == @job_proposal.id
      raise ActiveRecord::RecordNotFound, "step instance does not belong to this proposal"
    end
  end
end
