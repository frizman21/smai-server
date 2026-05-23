# Applies the side effects of a customer reply landing in the proposal's
# Gmail thread:
#
#   - Stamps the reply payload on the step instance (customer_replied=true,
#     gmail_reply_payload=<message>).
#   - Stops any in-flight or just-completed campaign run on this proposal
#     with :stopped_on_reply (ended_at stamped).
#   - Flips the host JobProposal's status_overlay to "customer_waiting",
#     which is what makes the proposal surface in the operator's "Needs
#     Attention" list and badge.
#
# Pulled out of GmailReplyPollJob so the production reply poller and the
# development-only "Simulate response" path drive identical state. If you
# change reply-side effects, this is the only place to edit.
class CustomerReplyHandler
  def self.flag!(step_instance, reply_message)
    new(step_instance, reply_message).flag!
  end

  def initialize(step_instance, reply_message)
    @step_instance = step_instance
    @reply_message = reply_message
  end

  def flag!
    instance = @step_instance.campaign_instance
    host = instance.host

    JobProposal.transaction do
      @step_instance.update!(customer_replied: true, gmail_reply_payload: @reply_message)
      instance.reload
      if instance.status_active? || instance.status_completed?
        instance.update!(status: :stopped_on_reply, ended_at: Time.current)
      end
      host.update!(status_overlay: "customer_waiting") if host.is_a?(JobProposal)
    end
  end
end
