require "test_helper"

class SimulateCustomerReplyJobTest < ActiveSupport::TestCase
  setup do
    @proposal = job_proposals(:in_users_org)
    @proposal.update!(
      status: :approved,
      pipeline_stage: :in_campaign,
      status_overlay: nil,
      customer_email: "alice@example.com"
    )
    @campaign      = campaigns(:approved_campaign)
    @step          = campaign_steps(:approved_step_one)
    @instance      = CampaignInstance.create!(host: @proposal, campaign: @campaign, status: :active)
    @step_instance = CampaignStepInstance.create!(
      campaign_instance: @instance,
      campaign_step: @step,
      planned_delivery_at: 1.hour.ago,
      email_delivery_status: :sent,
      final_subject: "Subject",
      final_body: "Body",
      gmail_thread_id: "THREAD-XYZ"
    )
  end

  test "running the job drives the full reply state machine" do
    with_rails_env("development") { SimulateCustomerReplyJob.perform_now(@step_instance.id) }

    assert @step_instance.reload.customer_replied
    assert_equal "stopped_on_reply", @instance.reload.status
    assert_equal "customer_waiting", @proposal.reload.status_overlay
    assert_includes JobProposal.needs_attention, @proposal
  end

  test "the persisted payload is shaped like a Gmail message and carries _simulated" do
    with_rails_env("development") { SimulateCustomerReplyJob.perform_now(@step_instance.id) }

    payload = @step_instance.reload.gmail_reply_payload
    assert_equal true, payload["_simulated"]
    assert_equal "THREAD-XYZ", payload["threadId"]
    headers = payload.dig("payload", "headers")
    from = headers.find { |h| h["name"] == "From" }
    assert_equal "alice@example.com", from["value"], "From should be the customer email so reply-handling code reading it sees a realistic shape"
    subject = headers.find { |h| h["name"] == "Subject" }
    assert_match(/^Re: /, subject["value"])
  end

  test "refuses to perform in production as a second-line guard" do
    with_rails_env("production") { SimulateCustomerReplyJob.perform_now(@step_instance.id) }

    assert_not @step_instance.reload.customer_replied
    assert_equal "active", @instance.reload.status
    assert_nil @proposal.reload.status_overlay
  end

  test "noops gracefully when the step instance is gone" do
    @step_instance.destroy!
    assert_nothing_raised do
      with_rails_env("development") { SimulateCustomerReplyJob.perform_now(@step_instance.id) }
    end
  end

  private

  def with_rails_env(env)
    original = Rails.env
    Rails.env = ActiveSupport::StringInquirer.new(env)
    yield
  ensure
    Rails.env = original
  end
end
