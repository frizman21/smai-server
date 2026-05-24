require "test_helper"

class SmsSenders::TwilioTest < ActiveSupport::TestCase
  ENV_KEYS = %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER].freeze

  setup do
    @prior_env = ENV_KEYS.to_h { |k| [k, ENV[k]] }
    ENV_KEYS.each { |k| ENV.delete(k) }
  end

  teardown do
    ENV_KEYS.each { |k| @prior_env[k].nil? ? ENV.delete(k) : ENV[k] = @prior_env[k] }
  end

  test "configured? requires all three env vars" do
    refute_predicate SmsSenders::Twilio, :configured?
    ENV["TWILIO_ACCOUNT_SID"] = "AC1"
    ENV["TWILIO_AUTH_TOKEN"]  = "tok"
    refute_predicate SmsSenders::Twilio, :configured?
    ENV["TWILIO_FROM_NUMBER"] = "+15555550123"
    assert_predicate SmsSenders::Twilio, :configured?
  end

  test "partially_configured? flips on once any env var is set, off once all are" do
    refute_predicate SmsSenders::Twilio, :partially_configured?
    ENV["TWILIO_ACCOUNT_SID"] = "AC1"
    assert_predicate SmsSenders::Twilio, :partially_configured?
    ENV["TWILIO_AUTH_TOKEN"]  = "tok"
    ENV["TWILIO_FROM_NUMBER"] = "+15555550123"
    refute_predicate SmsSenders::Twilio, :partially_configured?
  end

  test "missing_env_vars lists only the absent keys" do
    ENV["TWILIO_ACCOUNT_SID"] = "AC1"
    assert_equal %w[TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER], SmsSenders::Twilio.missing_env_vars
  end

  test "status_row reports :missing with a recommendation when nothing is set" do
    row = SmsSenders::Twilio.status_row
    assert_equal :missing, row.state
    assert_match "TWILIO_ACCOUNT_SID", row.recommendation
  end

  test "status_row reports :warn with the missing keys when partially set" do
    ENV["TWILIO_ACCOUNT_SID"] = "AC1"
    row = SmsSenders::Twilio.status_row
    assert_equal :warn, row.state
    assert_match "TWILIO_AUTH_TOKEN", row.details
  end

  test "status_row reports :ok with redacted SID and visible from-number when fully set" do
    ENV["TWILIO_ACCOUNT_SID"] = "AC1234567890abcd"
    ENV["TWILIO_AUTH_TOKEN"]  = "supersecret"
    ENV["TWILIO_FROM_NUMBER"] = "+15555550123"
    row = SmsSenders::Twilio.status_row
    assert_equal :ok, row.state
    assert_match "+15555550123", row.details
    refute_match "supersecret", row.details
    refute_match "1234567890abcd", row.details
  end
end
