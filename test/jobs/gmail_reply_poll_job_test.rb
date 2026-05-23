require "test_helper"

class GmailReplyPollJobTest < ActiveSupport::TestCase
  setup do
    @campaign = campaigns(:approved_campaign)
    @step_one = campaign_steps(:approved_step_one)
    @proposal = job_proposals(:in_users_org)
    @proposal.update!(
      status: :approved,
      pipeline_stage: :in_campaign,
      customer_email: "alice@example.com",
      customer_house_number: "100",
      customer_street: "Oak Ridge"
    )
    @instance = CampaignInstance.create!(campaign: @campaign, host: @proposal, status: :active)

    # Per PRD-09 §1, customer email leaves from the originator's own Gmail,
    # so the conversation lives in their mailbox — the poller authenticates
    # there, not against the shared ApplicationMailbox. Each test starts
    # with a working delegation; tests covering the "originator vanished"
    # path destroy it explicitly.
    @owner_delegation = EmailDelegation.create!(
      user: @proposal.owner,
      provider: "google_oauth2",
      email: "originator@example.com",
      access_token: "atk",
      refresh_token: "rtk",
      expires_at: 1.hour.from_now
    )
  end

  test "no-op when the originator has no connected Gmail delegation" do
    @owner_delegation.destroy!
    step = build_sent_step(thread_id: "t1", snapshot_messages: outgoing_only("t1"))

    assert_nothing_raised { GmailReplyPollJob.new.perform }
    assert_equal "active", @instance.reload.status
    assert_nil step.reload.gmail_send_response # untouched
  end

  test "no-op when current thread matches the snapshot (no reply)" do
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)

    stub_fetch_thread(returns: { "id" => "t1", "messages" => snapshot }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "active", @instance.reload.status
    assert_nil @proposal.reload.status_overlay
  end

  test "flips instance to stopped_on_reply when a new message from the customer appears" do
    snapshot = outgoing_only("t1")
    step = build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    reply = message_from("customer@elsewhere.com", "t1")
    current = snapshot + [reply]

    freeze_time = Time.current
    travel_to(freeze_time) do
      stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
        GmailReplyPollJob.new.perform
      end
    end

    @instance.reload
    assert_equal "stopped_on_reply", @instance.status
    assert_in_delta freeze_time, @instance.ended_at, 1.second
    assert_equal "customer_waiting", @proposal.reload.status_overlay

    step.reload
    assert step.customer_replied, "step should be flagged as having a customer reply"
    assert_equal reply, step.gmail_reply_payload, "step should retain the specific Gmail message that triggered the stop"
  end

  test "ignores new messages that come from the originator's own mailbox" do
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    # A second outgoing message (e.g., a follow-up step) — same From as us.
    current = snapshot + [message_from(@owner_delegation.email, "t1")]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "active", @instance.reload.status
  end

  test "stops on a reply from any third party on a non-excluded domain" do
    # The customer's wife forwards the thread to her husband's work email;
    # he replies to the thread with our originator still on it. His domain
    # is neither the tenant's nor servicemark.ai, so this is a real reply
    # and must stop the campaign.
    snapshot = outgoing_only("t1")
    step = build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    reply = message_from("husband@some-employer.com", "t1")
    current = snapshot + [reply]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "stopped_on_reply", @instance.reload.status
    assert_equal "customer_waiting", @proposal.reload.status_overlay
    assert_equal reply, step.reload.gmail_reply_payload
  end

  test "ignores a reply that comes from the originator's own tenant domain" do
    # The proposal owner belongs to tenant :one, whose account owner is
    # one@example.com — so example.com is the tenant's own domain.
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    internal = message_from("colleague@example.com", "t1")
    current = snapshot + [internal]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "active", @instance.reload.status, "an internal teammate reply must not stop the campaign"
    assert_nil @proposal.reload.status_overlay
  end

  test "ignores a reply that comes from the servicemark.ai domain" do
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    current = snapshot + [message_from("staff@servicemark.ai", "t1")]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "active", @instance.reload.status, "a ServiceMark AI reply must not stop the campaign"
  end

  test "stops on a genuine customer reply even when an internal reply precedes it" do
    snapshot = outgoing_only("t1")
    step = build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    internal = message_from("colleague@example.com", "t1")
    reply = message_from("customer@elsewhere.com", "t1")
    current = snapshot + [internal, reply]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "stopped_on_reply", @instance.reload.status
    assert_equal "customer_waiting", @proposal.reload.status_overlay
    assert_equal reply, step.reload.gmail_reply_payload, "the customer reply, not the internal one, should trip the stop"
  end

  test "establishes a baseline snapshot on first pass when send-time snapshot was missing" do
    step = build_sent_step(thread_id: "t1", snapshot_messages: nil)
    snapshot_now = outgoing_only("t1")

    stub_fetch_thread(returns: { "id" => "t1", "messages" => snapshot_now }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "active", @instance.reload.status, "should not flip on the very first pass"
    assert_equal snapshot_now, step.reload.gmail_thread_snapshot["messages"]
  end

  test "skips proposals already marked won" do
    @proposal.update!(pipeline_stage: :won)
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    current = snapshot + [message_from("customer@elsewhere.com", "t1")]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "active", @instance.reload.status
    assert_nil @proposal.reload.status_overlay
  end

  test "skips proposals already marked lost" do
    @proposal.update!(pipeline_stage: :lost)
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    current = snapshot + [message_from("customer@elsewhere.com", "t1")]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "active", @instance.reload.status
  end

  test "skips campaign instances that ended more than 6 months ago" do
    @instance.update!(status: :completed, ended_at: 7.months.ago)
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    current = snapshot + [message_from("customer@elsewhere.com", "t1")]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "completed", @instance.reload.status
    assert_nil @proposal.reload.status_overlay
  end

  test "still polls completed campaigns within the 6-month cutoff" do
    @instance.update!(status: :completed, ended_at: 1.month.ago)
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    current = snapshot + [message_from("customer@elsewhere.com", "t1")]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "stopped_on_reply", @instance.reload.status
    assert_equal "customer_waiting", @proposal.reload.status_overlay
  end

  test "skips paused campaign instances" do
    @instance.update!(status: :paused, ended_at: 1.day.ago)
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    current = snapshot + [message_from("customer@elsewhere.com", "t1")]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "paused", @instance.reload.status
  end

  test "transient fetch failure is logged and does not change state" do
    snapshot = outgoing_only("t1")
    step = build_sent_step(thread_id: "t1", snapshot_messages: snapshot)

    stub_fetch_thread(returns: nil) do
      assert_nothing_raised { GmailReplyPollJob.new.perform }
    end

    assert_equal "active", @instance.reload.status
    assert_equal snapshot, step.reload.gmail_thread_snapshot["messages"]
  end

  test "flips instance to stopped_on_delivery_issue when a Mailer-Daemon bounce arrives" do
    snapshot = outgoing_only("t1")
    step = build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    bounce = message_from("Mailer-Daemon@googlemail.com", "t1")
    current = snapshot + [bounce]

    freeze_time = Time.current
    travel_to(freeze_time) do
      stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
        GmailReplyPollJob.new.perform
      end
    end

    @instance.reload
    assert_equal "stopped_on_delivery_issue", @instance.status
    assert_in_delta freeze_time, @instance.ended_at, 1.second
    assert_equal "delivery_issue", @proposal.reload.status_overlay

    step.reload
    assert_equal "bounced", step.email_delivery_status
    assert_not step.customer_replied, "bounce path should not set customer_replied"
    assert_equal bounce, step.gmail_reply_payload
  end

  test "recognizes a postmaster bounce" do
    snapshot = outgoing_only("t1")
    step = build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    bounce = message_from("postmaster@elsewhere.com", "t1")
    current = snapshot + [bounce]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_equal "bounced", step.reload.email_delivery_status
  end

  test "Mailer-Daemon From with display-name-and-bracket form is recognized as a bounce" do
    snapshot = outgoing_only("t1")
    step = build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    bounce = {
      "id" => "dsn-1",
      "threadId" => "t1",
      "labelIds" => ["INBOX"],
      "payload" => {
        "headers" => [{ "name" => "From", "value" => 'Mail Delivery Subsystem <mailer-daemon@googlemail.com>' }]
      }
    }
    current = snapshot + [bounce]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_equal "bounced", step.reload.email_delivery_status
  end

  test "From header parsing handles 'Display Name <email>' format" do
    snapshot = outgoing_only("t1")
    build_sent_step(thread_id: "t1", snapshot_messages: snapshot)
    new_msg = {
      "id" => "incoming-1",
      "threadId" => "t1",
      "labelIds" => ["INBOX"],
      "payload" => {
        "headers" => [{ "name" => "From", "value" => '"Customer Name" <customer@elsewhere.com>' }]
      }
    }
    current = snapshot + [new_msg]

    stub_fetch_thread(returns: { "id" => "t1", "messages" => current }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "stopped_on_reply", @instance.reload.status
  end

  test "polls every sent step's thread on the same campaign instance" do
    build_sent_step_at(thread_id: "earlier", snapshot_messages: outgoing_only("earlier"), created_at: 2.days.ago)
    build_sent_step_at(thread_id: "latest",  snapshot_messages: outgoing_only("latest"),  created_at: 1.minute.ago)

    seen = []
    stub_fetch_thread_with(->(thread_id) {
      seen << thread_id
      { "id" => thread_id, "messages" => outgoing_only(thread_id) }
    }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal ["earlier", "latest"].sort, seen.sort, "every sent step's thread should be polled"
  end

  test "detects a reply on an earlier step's thread, not just the latest" do
    earlier_snapshot = outgoing_only("earlier")
    latest_snapshot  = outgoing_only("latest")
    earlier_step = build_sent_step_at(thread_id: "earlier", snapshot_messages: earlier_snapshot, created_at: 2.days.ago)
    build_sent_step_at(thread_id: "latest",  snapshot_messages: latest_snapshot,  created_at: 1.minute.ago)

    reply_on_earlier = message_from("customer@elsewhere.com", "earlier")
    stub_fetch_thread_with(->(thread_id) {
      case thread_id
      when "earlier" then { "id" => "earlier", "messages" => earlier_snapshot + [reply_on_earlier] }
      when "latest"  then { "id" => "latest",  "messages" => latest_snapshot }
      end
    }) do
      GmailReplyPollJob.new.perform
    end

    assert_equal "stopped_on_reply", @instance.reload.status
    earlier_step.reload
    assert earlier_step.customer_replied
    assert_equal reply_on_earlier, earlier_step.gmail_reply_payload
  end

  private

  def build_sent_step(thread_id:, snapshot_messages:)
    build_sent_step_at(thread_id: thread_id, snapshot_messages: snapshot_messages, created_at: Time.current)
  end

  def build_sent_step_at(thread_id:, snapshot_messages:, created_at:)
    snapshot_payload = snapshot_messages.nil? ? nil : { "id" => thread_id, "messages" => snapshot_messages }
    step = CampaignStepInstance.create!(
      campaign_instance: @instance,
      campaign_step: @step_one,
      planned_delivery_at: 1.hour.ago,
      email_delivery_status: :sent,
      final_subject: "subject",
      final_body: "body",
      gmail_thread_id: thread_id,
      gmail_thread_snapshot: snapshot_payload
    )
    step.update_column(:created_at, created_at) # rubocop:disable Rails/SkipsModelValidations
    step
  end

  def outgoing_only(thread_id)
    [message_from(@owner_delegation.email, thread_id, label: "SENT")]
  end

  def message_from(address, thread_id, label: "INBOX")
    {
      "id" => "msg-#{SecureRandom.hex(4)}",
      "threadId" => thread_id,
      "labelIds" => [label],
      "payload" => {
        "headers" => [{ "name" => "From", "value" => address }]
      }
    }
  end

  def stub_fetch_thread(returns:)
    stub_fetch_thread_with(->(_id) { returns }) { yield }
  end

  def stub_fetch_thread_with(callable)
    original = GmailSender.instance_method(:fetch_thread)
    GmailSender.define_method(:fetch_thread) { |thread_id| callable.call(thread_id) }
    yield
  ensure
    GmailSender.define_method(:fetch_thread, original)
  end
end
