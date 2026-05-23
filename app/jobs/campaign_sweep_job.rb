require "net/http"

# Runs every 5 minutes (see config/sidekiq_cron.yml) to find campaign step
# instances whose planned_delivery_at has passed and either ship them via the
# proposal originator's connected Gmail or block them — whichever the
# PreSendChecklist says.
#
# Send identity (PRD-09 v1.3 §1, SPEC-07): customer email goes out from the
# proposal originator's own Gmail account, authenticated via that user's
# EmailDelegation. The shared ApplicationMailbox is used only for
# transactional system mail (Devise resets, invitations) — never for
# customer campaign sends.
#
# The checklist (app/services/pre_send_checklist.rb, modeled on PRD-09 v1.3
# §9.2) is the single source of truth for what must hold before a real
# customer email leaves the system. Both this job and the operator UI on
# the proposal page run through the same checklist function.
#
# Failure handling, per the checklist's failure class:
# - :block_silent          — step stays pending, the next sweep re-evaluates.
# - :block_delivery_issue  — step is marked failed and the campaign run is
#                            stopped with stopped_on_delivery_issue.
#
# The dev and FAKE-SEND modes never hit Gmail and therefore bypass the
# checklist — they are local-development conveniences that route to
# letter_opener_web or do nothing.
class CampaignSweepJob < ApplicationJob
  queue_as :default

  # Send-mode resolution for a given run. ApplicationMailbox is used here only
  # as a "real-send environment is configured" sentinel — the actual credential
  # for a customer send is the originator's per-user EmailDelegation, looked up
  # in #deliver. The mailbox stays in the picture because it gates Devise/
  # invitation transactional mail and signals that the host has real Gmail
  # traffic configured at all.
  #
  #   1. development                                  -> :dev_letter_opener (route through
  #                                                      CampaignStepMailer + letter_opener_web).
  #                                                      Checklist bypassed.
  #   2. mailbox + (production OR TEST_TO_EMAIL)      -> :real_send. Checklist runs; the
  #                                                      originator-mailbox check enforces
  #                                                      per-proposal Gmail delegation.
  #   3. no mailbox + non-prod                        -> :fake_send. Render the email,
  #                                                      log it, mark the step :sent.
  #                                                      Checklist bypassed — lets tests
  #                                                      exercise the campaign lifecycle
  #                                                      without real Gmail.
  #   4. no mailbox + prod                            -> :real_send. The checklist's
  #                                                      originator-mailbox check
  #                                                      surfaces the outage as a
  #                                                      delivery issue on each step.
  #   5. mailbox + non-prod + no TEST_TO_EMAIL        -> :skip. Staging guardrail; we
  #                                                      will not relay through real
  #                                                      Gmail by accident.
  #
  # Devise mailers (password reset, registration, invitations) are unaffected —
  # they go through Action Mailer using the shared ApplicationMailbox.

  def self.production_environment?
    Rails.env.production?
  end

  def self.development_environment?
    Rails.env.development?
  end

  def self.test_to_email_override
    ENV["TEST_TO_EMAIL"].presence
  end

  def perform
    mode = resolve_mode(ApplicationMailbox.current)
    return if mode == :skip

    due_step_instance_ids(Time.current).each { |id| process(id, mode) }
  end

  private

  def resolve_mode(mailbox)
    if self.class.development_environment?
      Rails.logger.info "[CampaignSweepJob] dev mode: routing campaign step sends through Action Mailer (letter_opener_web at /letter_opener)"
      :dev_letter_opener
    elsif mailbox && (self.class.production_environment? || self.class.test_to_email_override)
      :real_send
    elsif mailbox.nil? && !self.class.production_environment?
      Rails.logger.info "[CampaignSweepJob] no application mailbox configured; running in FAKE-SEND mode (no real email leaves the host)"
      :fake_send
    elsif mailbox.nil? && self.class.production_environment?
      Rails.logger.warn "[CampaignSweepJob] no application mailbox configured in production; the pre-send checklist will surface the outage on each queued step"
      :real_send
    else
      Rails.logger.warn "[CampaignSweepJob] sending disabled in #{Rails.env}; set TEST_TO_EMAIL to redirect mail, or run in production"
      :skip
    end
  end

  def recipient_for(host)
    self.class.test_to_email_override || host.customer_email
  end

  # BCC the proposal originator (at the same Gmail address that appears in
  # the From header) on every customer send, so they have an inbox-visible
  # copy of every campaign email going out under their identity. Suppressed
  # when TEST_TO_EMAIL is set — that flag means "redirect all mail to a QA
  # inbox," and a leak to the originator's real Gmail would defeat the
  # point of the redirect.
  def bcc_for(host)
    return nil if self.class.test_to_email_override.present?
    host.owner&.gmail_delegation&.email
  end

  # Minimal candidate filter: pending steps whose planned_delivery_at has
  # passed. Everything else (campaign run status, proposal stage, suppression,
  # idempotency, …) lives in PreSendChecklist so the UI and the sweep agree
  # on what would block.
  def due_step_instance_ids(now)
    CampaignStepInstance
      .where(email_delivery_status: :pending)
      .where("planned_delivery_at <= ?", now)
      .pluck(:id)
  end

  def process(step_instance_id, mode)
    step_instance = CampaignStepInstance.find(step_instance_id)

    if mode == :dev_letter_opener || mode == :fake_send
      return unless claim(step_instance_id)
      step_instance.reload
      simulated_send(step_instance, mode)
      return
    end

    blocker = PreSendChecklist.run(step_instance).find(&:fail?)
    if blocker
      handle_blocked(step_instance, blocker)
      return
    end

    return unless claim(step_instance_id)
    step_instance.reload
    deliver(step_instance)
  end

  def handle_blocked(step_instance, blocker)
    case blocker.status
    when PreSendChecklist::BLOCK_SILENT
      Rails.logger.info(
        "[CampaignSweepJob] step #{step_instance.id} blocked silently by checklist " \
        "(#{blocker.key}): #{blocker.detail}"
      )
    when PreSendChecklist::BLOCK_DELIVERY_ISSUE
      Rails.logger.warn(
        "[CampaignSweepJob] step #{step_instance.id} blocked with delivery issue " \
        "(#{blocker.key}): #{blocker.detail}"
      )
      claim_to_failed(step_instance)
    end
  end

  # Atomically transitions pending -> sending. Returns true if this worker
  # won the claim, false if the row was already taken or no longer pending.
  def claim(step_instance_id)
    rows = CampaignStepInstance
      .where(id: step_instance_id, email_delivery_status: :pending)
      .update_all(
        email_delivery_status: CampaignStepInstance.email_delivery_statuses[:sending],
        updated_at: Time.current
      )
    rows.positive?
  end

  # Atomically transitions pending -> failed and stops the campaign run.
  # The conditional update_all guarantees we only act once per step even if
  # two sweeps overlap.
  def claim_to_failed(step_instance)
    rows = CampaignStepInstance
      .where(id: step_instance.id, email_delivery_status: :pending)
      .update_all(
        email_delivery_status: CampaignStepInstance.email_delivery_statuses[:failed],
        updated_at: Time.current
      )
    return unless rows.positive?

    instance = step_instance.campaign_instance
    instance.reload
    stop_instance_with_delivery_issue(instance)
  end

  def deliver(step_instance)
    instance = step_instance.campaign_instance
    host = instance.host
    recipient = recipient_for(host)

    # Per PRD-09 §1, the originator's own Gmail delegation is the credential.
    # The checklist's originator_mailbox check would have blocked us already
    # if this were missing, but a delegation can vanish between the checklist
    # run and the claim — fall back to delivery-issue handling rather than
    # crashing.
    delegation = host.owner&.gmail_delegation
    if delegation.nil?
      Rails.logger.warn "[CampaignSweepJob] originator delegation disappeared between checklist and send for step #{step_instance.id}"
      mark_failed(step_instance, instance)
      return
    end

    # Content is locked in at approve time (see JobProposalsController#approve).
    # The sweep just ships the persisted final_subject / final_body — no late
    # re-render means a post-approve edit to the proposal can't silently change
    # a queued email.
    subject = step_instance.final_subject
    body    = step_instance.final_body

    # Display name on the From header is the proposal owner's full name, so
    # the recipient sees:
    #   "Mike Frizzell" <mike@servicemark.ai>
    # The bare email address comes from the originator's own Gmail
    # delegation, not from a shared location/admin mailbox.
    from_name = host.owner&.full_name

    # The first email of the sequence carries the proposal's PDF
    # attachments; subsequent steps go out as plain text. "First" is
    # the lowest sequence_number among this campaign's steps — robust
    # to admins deleting and re-adding step 1.
    attachments = first_step?(step_instance) ? pdf_attachments_for(host) : []

    sender = GmailSender.new(delegation)
    send_response = sender.send_email(to: recipient, subject: subject, body: body.to_s, from_name: from_name, attachments: attachments, bcc: bcc_for(host))
    if send_response.nil?
      mark_failed(step_instance, instance)
      return
    end

    persist_send_metadata(step_instance, sender, send_response)
    step_instance.update!(email_delivery_status: :sent)
    complete_instance_if_done(instance)
  rescue StandardError => e
    Rails.logger.error "[CampaignSweepJob] unexpected error sending step instance #{step_instance.id}: #{e.class}: #{e.message}"
    mark_failed(step_instance, instance)
  end

  # Dev/letter_opener and FAKE-SEND paths. No real Gmail call, no thread
  # metadata to capture — reply polling and delivery-issue detection are
  # production-only concerns. The checklist is intentionally bypassed for
  # both modes (they don't reach a real customer).
  def simulated_send(step_instance, mode)
    instance = step_instance.campaign_instance
    host = instance.host
    recipient = recipient_for(host)
    if recipient.blank?
      Rails.logger.warn "[CampaignSweepJob] no recipient resolvable for step instance #{step_instance.id} in #{mode} mode"
      mark_failed(step_instance, instance)
      return
    end

    subject = step_instance.final_subject
    body    = step_instance.final_body
    if subject.blank?
      Rails.logger.warn "[CampaignSweepJob] step instance #{step_instance.id} has no final_subject in #{mode} mode — was it approved?"
      mark_failed(step_instance, instance)
      return
    end

    from_name = host.owner&.full_name
    attachments = first_step?(step_instance) ? pdf_attachments_for(host) : []
    bcc = bcc_for(host)

    if mode == :dev_letter_opener
      CampaignStepMailer.with(
        to:          recipient,
        bcc:         bcc,
        subject:     subject,
        body:        body.to_s,
        from_name:   from_name,
        attachments: attachments
      ).step.deliver_now
    else
      Rails.logger.info "[CampaignSweepJob][FAKE-SEND] step #{step_instance.id} -> #{recipient} (from #{from_name.inspect}, bcc #{bcc.inspect}, #{attachments.size} attachment(s)): #{subject.inspect}"
    end

    step_instance.update!(email_delivery_status: :sent)
    complete_instance_if_done(instance)
  rescue StandardError => e
    Rails.logger.error "[CampaignSweepJob] unexpected error in #{mode} send for step instance #{step_instance.id}: #{e.class}: #{e.message}"
    mark_failed(step_instance, instance)
  end

  # Stores the Gmail send response and (best-effort) the thread snapshot
  # captured immediately after send. The snapshot is the baseline the
  # GmailReplyPollJob compares against to detect customer replies. A
  # snapshot fetch failure (auth blip, missing scope) is non-fatal: we
  # log and leave gmail_thread_snapshot nil so the poller can fill it in
  # on its first pass.
  def persist_send_metadata(step_instance, sender, send_response)
    return if send_response.nil?

    thread_id = send_response["threadId"]
    thread_snapshot = nil
    if sender && thread_id.present?
      begin
        thread_snapshot = sender.fetch_thread(thread_id)
        if thread_snapshot.nil?
          Rails.logger.warn "[CampaignSweepJob] thread snapshot fetch returned nil for step #{step_instance.id} thread #{thread_id} — poller will populate later"
        end
      rescue StandardError => e
        Rails.logger.warn "[CampaignSweepJob] thread snapshot fetch raised for step #{step_instance.id} thread #{thread_id}: #{e.class}: #{e.message}"
      end
    end

    step_instance.update!(
      gmail_send_response: send_response,
      gmail_thread_id: thread_id,
      gmail_thread_snapshot: thread_snapshot
    )
  end

  # True iff this step is the first one in its revision by
  # sequence_number. Scoped to the step's campaign_revision so a later
  # revision with a renumbered step 1 doesn't change what counts as
  # "first" for an in-flight instance still on an older revision.
  def first_step?(step_instance)
    revision_id = step_instance.campaign_step.campaign_revision_id
    first_seq = CampaignStep.where(campaign_revision_id: revision_id).minimum(:sequence_number)
    step_instance.campaign_step.sequence_number == first_seq
  end

  # Returns an array of { filename:, content:, mime_type: } hashes for
  # every PDF attachment on the proposal. Skips non-PDF attachments
  # (we only want the original proposal document on the first email,
  # not photos or other supporting files).
  def pdf_attachments_for(proposal)
    proposal.attachments.includes(file_attachment: :blob).filter_map do |att|
      next unless att.file.attached?
      next unless att.file.content_type == "application/pdf" || att.file.filename.to_s.downcase.end_with?(".pdf")
      {
        filename:  att.file.filename.to_s,
        content:   att.file.download,
        mime_type: att.file.content_type || "application/pdf"
      }
    end
  end

  def mark_failed(step_instance, instance)
    step_instance.update!(email_delivery_status: :failed)
    instance.reload
    stop_instance_with_delivery_issue(instance)
  end

  # Stops the campaign run with a delivery issue and surfaces it on the
  # host JobProposal's status_overlay so the proposal shows up in the
  # "Needs Attention" filter. Mirrors GmailReplyPollJob#flag_bounce — both
  # synchronous send failures and async bounce detection should drive the
  # same operator-visible state.
  def stop_instance_with_delivery_issue(instance)
    JobProposal.transaction do
      instance.update!(status: :stopped_on_delivery_issue, ended_at: Time.current) if instance.status_active?
      host = instance.host
      host.update!(status_overlay: "delivery_issue") if host.is_a?(JobProposal)
    end
  end

  def complete_instance_if_done(instance)
    has_open = instance.step_instances
      .where(email_delivery_status: [
        CampaignStepInstance.email_delivery_statuses[:pending],
        CampaignStepInstance.email_delivery_statuses[:sending]
      ])
      .exists?
    return if has_open
    instance.reload
    instance.update!(status: :completed, ended_at: Time.current) if instance.status_active?
  end
end
