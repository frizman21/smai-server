class ProposalReplyNotificationJob < ApplicationJob
  queue_as :default

  # Texts the JobProposal owner that the customer replied to one of the
  # campaign emails. Composed from the proposal's customer fields and a
  # short link that redirects the owner into the Gmail thread on their
  # phone. No-ops (with a log line) when:
  #
  #   - the step instance vanished between flag! and the job firing
  #   - the host isn't a JobProposal (other host types don't carry the
  #     customer fields the SMS body needs)
  #   - the owner has no phone_number on file
  #   - SmsSender has no provider wired (TEST_TO_PHONE etc. unset)
  #
  # The SMS provider abstraction (SmsSender) handles dev-mode redirection
  # via TEST_TO_PHONE and test-mode capture via SmsSender.deliveries.
  def perform(step_instance_id)
    step_instance = CampaignStepInstance.find_by(id: step_instance_id)
    return log_skip("step instance #{step_instance_id} no longer exists") if step_instance.nil?

    instance = step_instance.campaign_instance
    proposal = instance&.host
    return log_skip("host is not a JobProposal (instance #{instance&.id})") unless proposal.is_a?(JobProposal)

    owner = proposal.owner
    return log_skip("proposal #{proposal.id} owner has no phone_number") if owner&.phone_number.blank?

    body = compose_body(proposal)
    SmsSender.deliver(to: owner.phone_number, body: body)
  end

  private

  def compose_body(proposal)
    lines = []
    lines << "Customer reply: #{customer_name(proposal)}"
    lines << proposal.short_address if proposal.short_address.present?
    lines << "Phone: #{proposal.customer_phone}" if proposal.customer_phone.present?
    lines << "DASH: #{proposal.dash_job_number}" if proposal.dash_job_number.present?
    if (open_url = open_in_gmail_url(proposal))
      lines << "Open: #{open_url}"
    end
    lines.join("\n")
  end

  def customer_name(proposal)
    [proposal.customer_first_name, proposal.customer_last_name].compact_blank.join(" ").presence ||
      proposal.customer_email.presence ||
      "(no name)"
  end

  # Wraps the Gmail thread URL in a ShortLink and returns the public
  # short URL the SMS recipient will tap. Returns nil when there's no
  # thread yet (proposal never sent an email) — caller drops the line.
  def open_in_gmail_url(proposal)
    thread_id = proposal.gmail_thread_id
    return nil if thread_id.blank?

    gmail_url = "https://mail.google.com/mail/u/0/#all/#{thread_id}"
    link = ShortLink.for(gmail_url)
    Rails.application.routes.url_helpers.short_link_url(link.code, host: app_host, protocol: app_protocol)
  end

  def app_host
    ActionMailer::Base.default_url_options[:host] || "localhost"
  end

  def app_protocol
    ActionMailer::Base.default_url_options[:protocol] || (Rails.env.production? ? "https" : "http")
  end

  def log_skip(reason)
    Rails.logger.info "[ProposalReplyNotificationJob] skip: #{reason}"
    nil
  end
end
