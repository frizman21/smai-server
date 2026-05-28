require "test_helper"

class ProposalReplyNotificationJobTest < ActiveJob::TestCase
  setup do
    @prior_env = %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER]
                 .to_h { |k| [k, ENV[k]] }
    ENV["TWILIO_ACCOUNT_SID"] = "AC1234567890"
    ENV["TWILIO_AUTH_TOKEN"]  = "tok"
    ENV["TWILIO_FROM_NUMBER"] = "+15555550123"

    @owner    = users(:one)
    @owner.update!(phone_number: "+15555550100")
    @proposal = job_proposals(:in_users_org)
    @proposal.update!(
      owner: @owner,
      status: :approved,
      pipeline_stage: :in_campaign,
      customer_email: "alice@example.com",
      customer_first_name: "Alice",
      customer_last_name: "Smith",
      customer_phone: "+15551234567",
      customer_house_number: "123",
      customer_street: "Main St",
      dash_job_number: "12345"
    )
    @campaign      = campaigns(:approved_campaign)
    @step          = campaign_steps(:approved_step_one)
    @instance      = CampaignInstance.create!(host: @proposal, campaign: @campaign, status: :active)
    @step_instance = CampaignStepInstance.create!(
      campaign_instance: @instance,
      campaign_step: @step,
      planned_delivery_at: 1.hour.ago,
      email_delivery_status: :sent,
      gmail_thread_id: "thread-abc",
      final_subject: "Hi",
      final_body: "Body"
    )
  end

  teardown do
    @prior_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "sends an SMS to the owner's phone with the customer's name, address, phone, and DASH" do
    perform_now
    delivery = SmsSender.deliveries.last
    assert_equal "+15555550100", delivery.to
    assert_match "Alice Smith", delivery.body
    assert_match "123 Main St", delivery.body
    assert_match "+15551234567", delivery.body
    assert_match "DASH: 12345", delivery.body
  end

  test "the SMS body includes a short link that resolves to the gmail thread url" do
    perform_now
    delivery = SmsSender.deliveries.last
    url_match = delivery.body.match(%r{(https?://\S+/r/[A-Za-z0-9]+)})
    assert url_match, "expected a /r/<code> short link in the body, got: #{delivery.body}"

    code = url_match[1].split("/r/").last
    link = ShortLink.find_by(code: code)
    assert link, "no ShortLink row written for code #{code.inspect}"
    assert_equal "https://mail.google.com/mail/u/0/#all/thread-abc", link.target_url
  end

  test "skips silently when the owner has no phone number on file" do
    @owner.update!(phone_number: nil)
    perform_now
    assert_empty SmsSender.deliveries
  end

  test "skips silently when no SMS provider is configured" do
    %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER].each { |k| ENV.delete(k) }
    perform_now
    assert_empty SmsSender.deliveries
  end

  test "skips silently when the step instance no longer exists" do
    id = @step_instance.id
    @step_instance.destroy!
    ProposalReplyNotificationJob.new.perform(id)
    assert_empty SmsSender.deliveries
  end

  private

  def perform_now
    ProposalReplyNotificationJob.new.perform(@step_instance.id)
  end
end
