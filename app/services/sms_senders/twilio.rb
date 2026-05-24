require "net/http"
require "uri"
require "json"

# Twilio Programmable Messaging implementation of the SmsSender
# provider interface. Selected automatically by SmsSender when all
# three env vars are set — see SmsSender for the dispatch contract
# and the test-mode / TEST_TO_PHONE override behavior.
module SmsSenders
  class Twilio
    ENV_VARS = %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER].freeze
    API_HOST = "api.twilio.com".freeze

    def self.label
      "Twilio"
    end

    def self.configured?
      ENV_VARS.all? { |k| ENV[k].present? }
    end

    def self.partially_configured?
      ENV_VARS.any? { |k| ENV[k].present? } && !configured?
    end

    def self.missing_env_vars
      ENV_VARS.reject { |k| ENV[k].present? }
    end

    # Row consumed by IntegrationStatus → admin Integrations page.
    def self.status_row
      if configured?
        IntegrationStatus::Status.new(
          name:           "Text messaging (Twilio)",
          state:          :ok,
          details:        "Sending from #{ENV['TWILIO_FROM_NUMBER']} as account #{redacted_account_sid}.",
          recommendation: nil
        )
      elsif partially_configured?
        IntegrationStatus::Status.new(
          name:           "Text messaging (Twilio)",
          state:          :warn,
          details:        "Partial Twilio config — missing: #{missing_env_vars.join(', ')}.",
          recommendation: "Finish setting the remaining Twilio env vars and redeploy."
        )
      else
        IntegrationStatus::Status.new(
          name:           "Text messaging (Twilio)",
          state:          :missing,
          details:        "Not configured. Reply notifications by SMS will not send.",
          recommendation: "Set #{ENV_VARS.join(', ')} and redeploy. See production setup §0.5a."
        )
      end
    end

    def self.redacted_account_sid
      sid = ENV["TWILIO_ACCOUNT_SID"].to_s
      sid.length > 8 ? "#{sid[0, 4]}…#{sid[-4, 4]}" : sid
    end

    def send_sms(to:, body:)
      account_sid = ENV.fetch("TWILIO_ACCOUNT_SID")
      auth_token  = ENV.fetch("TWILIO_AUTH_TOKEN")
      from        = ENV.fetch("TWILIO_FROM_NUMBER")

      uri = URI("https://#{API_HOST}/2010-04-01/Accounts/#{account_sid}/Messages.json")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri)
      req.basic_auth(account_sid, auth_token)
      req.set_form_data(From: from, To: to, Body: body)
      response = http.request(req)

      if response.code.to_i.between?(200, 299)
        data = JSON.parse(response.body) rescue {}
        SmsSender::Result.new(
          provider: self.class.label,
          sid:      data["sid"],
          to:       to,
          body:     body,
          status:   data["status"] || "queued"
        )
      else
        Rails.logger.warn "[SmsSenders::Twilio] send failed (#{response.code}): #{response.body}"
        nil
      end
    end
  end
end
