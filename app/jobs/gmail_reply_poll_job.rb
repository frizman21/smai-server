require "net/http"

# Polls Gmail for replies on threads we've sent campaign emails on. Runs
# on its own cadence (see config/sidekiq_cron.yml), independent of the
# CampaignSweepJob so reply latency isn't bounded by the send cadence.
#
# Per PRD-09 §1, customer email leaves from the proposal originator's
# own Gmail — so the conversation lives in *their* mailbox, not the
# shared ApplicationMailbox. The poller authenticates per-step as that
# originator's EmailDelegation; a step whose originator has since
# disconnected Gmail is logged and skipped, and the next tick retries.
#
# Eligibility (per-campaign-instance, latest sent step only):
#   - Step has a stored gmail_thread_id.
#   - Parent CampaignInstance.status IN (:active, :completed).
#   - For :completed, ended_at must be within POLLING_CUTOFF (6 months).
#     Active campaigns are never aged out.
#   - Host JobProposal.pipeline_stage is :in_campaign (not :won, :lost).
#
# Detection cross-references two snapshots of the same thread:
#   - gmail_thread_snapshot, captured at send time by CampaignSweepJob,
#     is the baseline of "what was on the thread when we sent."
#   - The current thread is fetched on each poll. If the current message
#     count exceeds the baseline AND any of the new messages have a From
#     header whose address isn't the originator's Gmail, that message is
#     either a customer reply or an asynchronous bounce DSN.
#
# A new message from the originator's own organization (a CC'd
# teammate, an owner forwarding the thread internally) or from
# ServiceMark AI staff is not a customer reply — see
# Tenant#reply_ignored_domains — and is skipped so the scan can find a
# genuine customer reply further down the thread.
#
# Bounces are distinguished by the local-part of the inbound From
# address (mailer-daemon, postmaster). The handling diverges:
#   - Customer reply  -> CampaignInstance :stopped_on_reply,
#                        JobProposal status_overlay "customer_waiting",
#                        step.customer_replied true.
#   - Async bounce    -> CampaignInstance :stopped_on_delivery_issue,
#                        JobProposal status_overlay "delivery_issue",
#                        step.email_delivery_status :bounced.
# In both cases the inbound message JSON is persisted on the step in
# gmail_reply_payload (kept generically named — it captures whichever
# inbound message tripped the stop).
#
# Failure handling: a Gmail fetch failure (transient network/auth blip,
# missing scope after a re-consent gap) is logged and skipped. The next
# tick retries — no backoff state needed because the eligibility query
# stays small.
class GmailReplyPollJob < ApplicationJob
  queue_as :default

  POLLING_CUTOFF = 6.months

  def perform
    pollable_step_instance_ids(Time.current).each do |id|
      process(id)
    end
  end

  private

  # Returns IDs of every sent step instance on an eligible campaign
  # instance. Each campaign step opens its own Gmail thread (no
  # In-Reply-To threading on outbound), so a customer can reply to any
  # of them independently — we have to check every thread, not just
  # the latest one per campaign instance.
  def pollable_step_instance_ids(now)
    cutoff = now - POLLING_CUTOFF
    active_status = CampaignInstance.statuses[:active]
    completed_status = CampaignInstance.statuses[:completed]

    CampaignStepInstance
      .joins(:campaign_instance)
      .joins("INNER JOIN job_proposals ON job_proposals.id = campaign_instances.host_id AND campaign_instances.host_type = 'JobProposal'")
      .where.not(gmail_thread_id: nil)
      .where(email_delivery_status: CampaignStepInstance.email_delivery_statuses[:sent])
      .where(campaign_instances: { status: [active_status, completed_status] })
      .where(
        "campaign_instances.status = ? OR campaign_instances.ended_at >= ?",
        active_status, cutoff
      )
      .where(job_proposals: { pipeline_stage: JobProposal.pipeline_stages[:in_campaign] })
      .pluck("campaign_step_instances.id")
  end

  def process(step_instance_id)
    step_instance = CampaignStepInstance.find_by(id: step_instance_id)
    return unless step_instance

    # Per PRD-09 §1, the originator's own Gmail is what shipped the mail,
    # so the thread lives there. Authenticate as them — the shared
    # ApplicationMailbox can't see it. A vanished delegation (originator
    # disconnected Gmail) surfaces as a delivery_issue on subsequent
    # sweeps via PreSendChecklist; for polling we just log + skip and let
    # the next tick re-evaluate once they reconnect.
    delegation = step_instance.campaign_instance.host&.owner&.gmail_delegation
    if delegation.nil?
      Rails.logger.warn "[GmailReplyPollJob] no originator Gmail delegation for step #{step_instance.id} (thread #{step_instance.gmail_thread_id}); skipping until reconnect"
      return
    end

    sender = GmailSender.new(delegation)
    thread = sender.fetch_thread(step_instance.gmail_thread_id)
    if thread.nil?
      Rails.logger.warn "[GmailReplyPollJob] thread fetch returned nil for step #{step_instance.id} thread #{step_instance.gmail_thread_id} — will retry next tick"
      return
    end

    # First-pass baseline: send-time snapshot was missing (snapshot fetch
    # failed at send, or this row pre-dates the column). Establish the
    # baseline now and bail; next tick does the actual diff.
    if step_instance.gmail_thread_snapshot.blank?
      step_instance.update!(gmail_thread_snapshot: thread)
      return
    end

    # The customer-replied stop is meant to fire on a *customer* reply
    # only. Mail that comes back from the originator's own organization
    # (a CC'd teammate, an owner forwarding internally) or from
    # ServiceMark AI staff is not a customer reply — see
    # Tenant#reply_ignored_domains. Bounces are unaffected: a DSN is
    # caught earlier by its mailer-daemon/postmaster local-part.
    tenant = step_instance.campaign_instance.host&.owner&.tenant
    inbound = first_inbound_message(thread, step_instance.gmail_thread_snapshot, delegation.email, tenant)
    return unless inbound

    case inbound[:kind]
    when :bounce then flag_bounce(step_instance, inbound[:message])
    when :reply  then flag_reply(step_instance, inbound[:message])
    end
  rescue StandardError => e
    Rails.logger.error "[GmailReplyPollJob] unexpected error polling step #{step_instance_id}: #{e.class}: #{e.message}"
  end

  # Returns the first message in the current thread (after the snapshot
  # baseline) that came from someone other than the originator (the
  # account that sent the campaign mail), tagged as either :reply or
  # :bounce. Returns nil when no such message exists. Returning the
  # message itself — rather than just a flag — lets the caller persist
  # the specific Gmail payload that triggered the stop, useful for
  # diagnostics.
  def first_inbound_message(current_thread, baseline_thread, originator_email, tenant)
    baseline_count = Array(baseline_thread["messages"]).length
    current_messages = Array(current_thread["messages"])
    return nil if current_messages.length <= baseline_count

    new_messages = current_messages.last(current_messages.length - baseline_count)
    new_messages.each do |msg|
      next unless from_other_party?(msg, originator_email)
      return { kind: :bounce, message: msg } if bounce_message?(msg)
      # An internal reply (tenant's own domain / ServiceMark AI) isn't a
      # customer reply — skip it and keep scanning later messages for a
      # genuine customer reply further down the thread.
      next if internal_reply?(msg, tenant)
      return { kind: :reply, message: msg }
    end
    nil
  end

  # True when the message's From address belongs to a domain whose
  # replies should not trip the customer-replied stop. With no tenant we
  # can't resolve the tenant's own domains, so nothing is treated as
  # internal.
  def internal_reply?(message, tenant)
    return false if tenant.nil?
    tenant.reply_ignored_sender?(extract_email(extract_from_header(message)))
  end

  def from_other_party?(message, originator_email)
    sender_email = extract_email(extract_from_header(message))
    sender_email.present? && sender_email.casecmp(originator_email.to_s) != 0
  end

  # Recognizes a Gmail-side delivery status notification (DSN) from the
  # local-part of the inbound From address. Gmail uses
  # Mailer-Daemon@googlemail.com; some receiving servers use
  # postmaster@<domain>. Both forms are well-known DSN senders and we
  # treat them as async bounces, not customer replies.
  def bounce_message?(message)
    sender_email = extract_email(extract_from_header(message))
    return false if sender_email.blank?
    local_part = sender_email.split("@", 2).first.to_s.downcase
    %w[mailer-daemon postmaster].include?(local_part)
  end

  def extract_from_header(message)
    headers = message.dig("payload", "headers") || []
    headers.find { |h| h["name"].to_s.casecmp("From").zero? }&.dig("value").to_s
  end

  # Extracts the bare email from a From header value like
  # "Display Name <addr@host>" or just "addr@host".
  def extract_email(from_value)
    bracketed = from_value.match(/<([^>]+)>/)
    return bracketed[1].strip if bracketed
    bare = from_value.match(/\S+@\S+/)
    bare ? bare[0].strip : ""
  end

  def flag_reply(step_instance, reply_message)
    instance = step_instance.campaign_instance
    host = instance.host

    JobProposal.transaction do
      step_instance.update!(customer_replied: true, gmail_reply_payload: reply_message)
      instance.reload
      if instance.status_active? || instance.status_completed?
        instance.update!(status: :stopped_on_reply, ended_at: Time.current)
      end
      if host.is_a?(JobProposal)
        host.update!(status_overlay: "customer_waiting")
      end
    end
  end

  def flag_bounce(step_instance, bounce_message)
    instance = step_instance.campaign_instance
    host = instance.host

    JobProposal.transaction do
      step_instance.update!(email_delivery_status: :bounced, gmail_reply_payload: bounce_message)
      instance.reload
      if instance.status_active? || instance.status_completed?
        instance.update!(status: :stopped_on_delivery_issue, ended_at: Time.current)
      end
      if host.is_a?(JobProposal)
        host.update!(status_overlay: "delivery_issue")
      end
    end
  end
end
