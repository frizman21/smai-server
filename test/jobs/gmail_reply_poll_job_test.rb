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
end
