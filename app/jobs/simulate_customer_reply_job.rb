# Development-only convenience: pretend a customer reply just landed in
# the Gmail thread for a sent step, and run the synthesized payload through
# the same CustomerReplyHandler the production poller uses. Useful for
# walking the post-reply state machine (campaign stops, proposal overlay
# flips to customer_waiting, proposal lands in Needs Attention) without
# needing a real Gmail inbox.
#
# Refuses to perform outside development as a second-line guard — the
# controller already gates on Rails.env.development? and is_admin, but a
# stray :perform_now in some other context shouldn't be able to fake a
# customer reply on a real production campaign.
class SimulateCustomerReplyJob < ApplicationJob
  queue_as :default

  def perform(step_instance_id)
    return unless Rails.env.development?

    step_instance = CampaignStepInstance.find_by(id: step_instance_id)
    return if step_instance.nil?

    CustomerReplyHandler.flag!(step_instance, self.class.canned_reply_for(step_instance))
  end

  # Gmail-message-shaped hash with the originator's customer email in the
  # From header and a short canned body. The shape matches what the real
  # GmailReplyPollJob hands CustomerReplyHandler, so any view code that
  # later reads gmail_reply_payload sees the same fields it would for a
  # genuine reply. The "_simulated" marker is non-Gmail and gives us a
  # cheap tell when reading payloads later.
  def self.canned_reply_for(step_instance)
    host = step_instance.campaign_instance.host
    customer_email = host.respond_to?(:customer_email) ? host.customer_email.to_s : ""
    snippet = "Yes, thanks — that sounds good. Could you give me a call this week? (Simulated reply)"
    {
      "id"           => "simulated-#{SecureRandom.hex(8)}",
      "threadId"     => step_instance.gmail_thread_id,
      "internalDate" => (Time.current.to_i * 1000).to_s,
      "snippet"      => snippet,
      "payload"      => {
        "headers" => [
          { "name" => "From",    "value" => customer_email },
          { "name" => "Subject", "value" => "Re: #{step_instance.final_subject}" }
        ],
        "body" => { "data" => Base64.urlsafe_encode64(snippet) }
      },
      "_simulated"   => true
    }
  end
end
