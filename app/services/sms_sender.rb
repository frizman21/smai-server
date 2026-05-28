require "net/http"
require "uri"
require "json"

# Sends outbound SMS through whichever provider is wired by env. The
# first provider in PROVIDERS whose required env vars are all present
# wins — that's the "use the existence of an env variable as signal"
# rule from issue #231. Add a new provider by appending it to PROVIDERS
# and giving it the same class-level interface (.label, .configured?,
# .partially_configured?, .missing_env_vars, .status_row, .env_vars)
# plus an instance #send_sms(to:, body:).
#
# In Rails.env.test no HTTP fires — sends are recorded on `deliveries`
# so tests can assert what would have gone out, matching GmailSender.
#
# In any environment, when TEST_TO_PHONE is set, all SMS is redirected
# to that number instead of going to the real recipient. Mirrors the
# TEST_TO_EMAIL gate used by the campaign sweep — lets a developer
# point real Twilio sends at a test phone without touching code.
class SmsSender
  Result = Struct.new(:provider, :sid, :to, :body, :status, keyword_init: true)

  PROVIDERS = %w[SmsSenders::Twilio].freeze

  class << self
    def deliveries
      @deliveries ||= []
    end

    def reset_deliveries!
      @deliveries = []
    end

    # First provider class whose env vars are all present, or nil when
    # nothing is configured.
    def active_provider
      provider_classes.find(&:configured?)
    end

    def configured?
      active_provider.present?
    end

    def provider_name
      active_provider&.label
    end

    # Send an SMS. Returns a Result on success, nil when nothing was
    # sent (no provider configured, blank recipient, or provider failure).
    def deliver(to:, body:)
      provider = active_provider
      if provider.nil?
        Rails.logger.warn "[SmsSender] no SMS provider configured; dropping send to #{to.inspect}"
        return nil
      end

      destination = effective_recipient(to)
      if destination.blank?
        Rails.logger.warn "[SmsSender] no destination phone (override or real) — dropping send"
        return nil
      end

      if Rails.env.test?
        stub = Result.new(
          provider: provider.label,
          sid:      "test-#{SecureRandom.hex(4)}",
          to:       destination,
          body:     body,
          status:   "queued"
        )
        deliveries << stub
        return stub
      end

      provider.new.send_sms(to: destination, body: body)
    end

    # Snapshot of every known provider for the Integrations admin page.
    # Each entry is whatever the provider's .status_row returns — an
    # IntegrationStatus::Status with the provider's name baked in.
    def provider_status_rows
      provider_classes.map(&:status_row)
    end

    def provider_classes
      PROVIDERS.map(&:constantize)
    end

    private

    def effective_recipient(to)
      override = ENV["TEST_TO_PHONE"].to_s.strip
      override.present? ? override : to.to_s.strip
    end
  end
end
