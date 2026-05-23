require "test_helper"

class GmailReplyPollJobTest < ActiveSupport::TestCase
  setup do
    # Set up common objects used by all tests
    @tenant = tenants(:one)
    @step_instance = campaign_step_instances(:one)
    @job = GmailReplyPollJob.new
  end

  test "internal_reply? identifies internal senders correctly" do
    message_from_ignored_domain = {
      "payload" => { "headers" => [{"name" => "From", "value" => "Internal User <user@mycompany.com>"}] }
    }

    message_from_valid_domain = {
      "payload" => { "headers" => [{"name" => "From", "value" => "External User <user@external.com>"}] }
    }

    invalid_format_message = {
      "payload" => { "headers" => [{"name" => "From", "value" => "Malformed <user@."}] }
    }

    # Assume tenant has mycompany.com as ignored
    @tenant.stubs(:reply_ignored_sender?).returns(false, true, true)

    assert_not @job.send(:internal_reply?, message_from_valid_domain, @tenant)
    assert @job.send(:internal_reply?, message_from_ignored_domain, @tenant)
    assert_not @job.send(:internal_reply?, invalid_format_message, @tenant)
  end

  test "no-op when originator has no Gmail" do
    @step_instance.campaign_instance.host.owner.gmail_delegation = nil
    @job.perform
    assert_nil @step_instance.reload.customer_replied
    assert_nil @step_instance.reload.email_delivery_status
  end

  test "no-op when current thread matches snapshot" do
    gmail_delegation = stub(fetch_thread: {"messages" => [1, 2, 3]})
    @step_instance.campaign_instance.host.owner.stubs(:gmail_delegation).returns(gmail_delegation)
    @step_instance.update!(gmail_thread_snapshot: {"messages" => [1, 2, 3]})
    @job.perform
    assert_nil @step_instance.reload.customer_replied
    assert_nil @step_instance.reload.email_delivery_status
  end

  test "flips to stopped_on_reply on customer reply" do
    gmail_delegation = stub(fetch_thread: {"messages" => [1, 2, 3, 4]})
    @step_instance.campaign_instance.host.owner.stubs(:gmail_delegation).returns(gmail_delegation)
    @step_instance.update!(gmail_thread_snapshot: {"messages" => [1, 2, 3]})
    @job.stubs(:first_inbound_message).returns(kind: :reply, message: {"payload" => {"headers" => []}})
    @job.perform
    assert @step_instance.reload.customer_replied
    assert_equal "stopped_on_reply", @step_instance.campaign_instance.reload.status
    assert_equal "customer_waiting", @step_instance.campaign_instance.host.reload.status_overlay
  end

  test "flips to stopped_on_delivery_issue on async bounce" do
    gmail_delegation = stub(fetch_thread: {"messages" => [1, 2, 3, 4]})
    @step_instance.campaign_instance.host.owner.stubs(:gmail_delegation).returns(gmail_delegation)
    @step_instance.update!(gmail_thread_snapshot: {"messages" => [1, 2, 3]})
    @job.stubs(:first_inbound_message).returns(kind: :bounce, message: {"payload" => {"headers" => []}})
    @job.perform
    assert_equal "bounced", @step_instance.reload.email_delivery_status
    assert_equal "stopped_on_delivery_issue", @step_instance.campaign_instance.reload.status
    assert_equal "delivery_issue", @step_instance.campaign_instance.host.reload.status_overlay
  end

  test "extract_email extracts email from bracketed format" do
    email = @job.send(:extract_email, "Display Name <addr@host.com>")
    assert_equal "addr@host.com", email
  end

  test "extract_email extracts email from bare format" do
    email = @job.send(:extract_email, "addr@host.com")
    assert_equal "addr@host.com", email
  end

  test "extract_email returns empty for invalid format" do
    email = @job.send(:extract_email, "Invalid Email")
    assert_equal "", email
  end

  test "valid_email_format? validates correct email formats" do
    assert @job.send(:valid_email_format?, "test@example.com")
    assert @job.send(:valid_email_format?, "test.name@sub.example.co.uk")
  end

  test "valid_email_format? invalidates incorrect email formats" do
    assert_not @job.send(:valid_email_format?, "invalid-email")
    assert_not @job.send(:valid_email_format?, "@example.com")
    assert_not @job.send(:valid_email_format?, "test@.com")
  end
end
