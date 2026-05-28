require "test_helper"

class SmsSenderTest < ActiveSupport::TestCase
  ENV_KEYS = %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER TEST_TO_PHONE].freeze

  setup do
    @prior_env = ENV_KEYS.to_h { |k| [k, ENV[k]] }
    ENV_KEYS.each { |k| ENV.delete(k) }
  end

  teardown do
    ENV_KEYS.each { |k| @prior_env[k].nil? ? ENV.delete(k) : ENV[k] = @prior_env[k] }
  end

  test "configured? is false when no provider env vars are set" do
    refute_predicate SmsSender, :configured?
    assert_nil SmsSender.provider_name
    assert_nil SmsSender.active_provider
  end

  test "twilio becomes the active provider once all three env vars are set" do
    ENV["TWILIO_ACCOUNT_SID"] = "AC1"
    ENV["TWILIO_AUTH_TOKEN"]  = "tok"
    ENV["TWILIO_FROM_NUMBER"] = "+15555550123"
    assert_predicate SmsSender, :configured?
    assert_equal "Twilio", SmsSender.provider_name
    assert_equal SmsSenders::Twilio, SmsSender.active_provider
  end

  test "deliver returns nil and records nothing when no provider is configured" do
    assert_nil SmsSender.deliver(to: "+15555550100", body: "hi")
    assert_empty SmsSender.deliveries
  end

  test "deliver in test env captures the send on deliveries without HTTP" do
    configure_twilio_env
    result = SmsSender.deliver(to: "+15555550100", body: "hi from test")

    assert_equal "Twilio", result.provider
    assert_equal "+15555550100", result.to
    assert_equal "hi from test", result.body
    assert_match(/^test-/, result.sid)
    assert_equal 1, SmsSender.deliveries.size
    assert_equal result, SmsSender.deliveries.last
  end

  test "TEST_TO_PHONE redirects all outbound SMS to the override number" do
    configure_twilio_env
    ENV["TEST_TO_PHONE"] = "+15555559999"
    result = SmsSender.deliver(to: "+15555550100", body: "hi")
    assert_equal "+15555559999", result.to
  end

  test "deliver drops when destination is blank after override resolution" do
    configure_twilio_env
    assert_nil SmsSender.deliver(to: " ", body: "hi")
    assert_empty SmsSender.deliveries
  end

  test "provider_status_rows returns one Status per known provider" do
    rows = SmsSender.provider_status_rows
    assert_equal 1, rows.size
    assert_equal "Text messaging (Twilio)", rows.first.name
  end

  private

  def configure_twilio_env
    ENV["TWILIO_ACCOUNT_SID"] = "AC1234567890"
    ENV["TWILIO_AUTH_TOKEN"]  = "tok"
    ENV["TWILIO_FROM_NUMBER"] = "+15555550123"
  end
end
