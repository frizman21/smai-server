require "test_helper"

class CustomerReplyHandlerTest < ActiveSupport::TestCase
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
      final_subject: "Hi",
      final_body: "Body"
    )
    @reply_payload = { "id" => "msg-1", "snippet" => "Yes please" }
  end

  test "stamps the reply payload on the step instance and flags customer_replied" do
    CustomerReplyHandler.flag!(@step_instance, @reply_payload)
    @step_instance.reload
    assert @step_instance.customer_replied
    assert_equal @reply_payload, @step_instance.gmail_reply_payload
  end

  test "stops an active campaign instance with :stopped_on_reply and stamps ended_at" do
    freeze_time = Time.current
    travel_to(freeze_time) { CustomerReplyHandler.flag!(@step_instance, @reply_payload) }

    @instance.reload
    assert_equal "stopped_on_reply", @instance.status
    assert_in_delta freeze_time, @instance.ended_at, 1.second
  end

  test "also stops a just-completed instance — the reply still matters operationally" do
    @instance.update!(status: :completed, ended_at: 5.minutes.ago)
    CustomerReplyHandler.flag!(@step_instance, @reply_payload)
    assert_equal "stopped_on_reply", @instance.reload.status
  end

  test "does not change a paused instance — the operator already steered it" do
    @instance.update!(status: :paused, ended_at: 1.hour.ago)
    CustomerReplyHandler.flag!(@step_instance, @reply_payload)
    assert_equal "paused", @instance.reload.status
  end

  test "flips the host JobProposal status_overlay to customer_waiting" do
    CustomerReplyHandler.flag!(@step_instance, @reply_payload)
    assert_equal "customer_waiting", @proposal.reload.status_overlay
  end

  test "the flipped overlay surfaces the proposal in JobProposal.needs_attention" do
    # End-to-end with the scope that drives the sidebar badge and the
    # Needs Attention filter — this is the operator-visible outcome of a
    # reply landing, and the whole point of issue #240's plumbing.
    CustomerReplyHandler.flag!(@step_instance, @reply_payload)
    assert_includes JobProposal.needs_attention, @proposal.reload
  end
end
