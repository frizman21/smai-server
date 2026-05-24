# Aggregates the live status of every external integration the app talks
# to: the application mailbox, Google OAuth, Gemini for PDF extraction,
# Active Storage backend, Redis (Sidekiq), Sentry, the production host
# config, and the dev-only TEST_TO_EMAIL gate.
#
# Drives the Admin → Integrations index. Each entry returns a Status with
# one of three states:
#
#   :ok      — fully configured / connected.
#   :warn    — works in some form but is sub-optimal (e.g. Sentry falling
#              back to the bundled default DSN, partial storage config).
#   :missing — not configured; the feature it gates won't work.
#
# Each Status carries a one-line `details` describing the current state
# and an optional `recommendation` that tells the admin what to do when
# the state is not :ok.
class IntegrationStatus
  Status = Struct.new(:name, :state, :details, :recommendation, keyword_init: true)

  def self.all
    new.all
  end

  def all
    [
      application_mailbox,
      google_oauth,
      gemini,
      active_storage,
      sidekiq_redis,
      app_host,
      sentry,
      test_to_email
    ] + sms_provider_rows
  end

  # One row per known SMS provider (currently only Twilio). The provider
  # itself owns its label, env-var list, and recommendation text — see
  # SmsSender for the dispatch contract.
  def sms_provider_rows
    SmsSender.provider_status_rows
  end

  private

  def application_mailbox
    mb = ApplicationMailbox.current
    if mb.nil?
      Status.new(
        name: "Application Mailbox (Gmail)",
        state: :missing,
        details: "Not connected. Outbound invitations and campaign emails will not send.",
        recommendation: "Open Admin → Mailbox and connect a Gmail account."
      )
    else
      expiry_note =
        if mb.expires_at.nil?
          "no token expiry recorded"
        elsif mb.expired?
          "token expired #{time_ago(mb.expires_at)} — will refresh on next send"
        else
          "token expires in #{time_until(mb.expires_at)}"
        end
      Status.new(
        name: "Application Mailbox (Gmail)",
        state: :ok,
        details: "Connected as #{mb.email} · #{expiry_note}.",
        recommendation: nil
      )
    end
  end

  def google_oauth
    missing = ApplicationHelper::GOOGLE_OAUTH_ENV_VARS.reject { |k| ENV[k].present? }
    if missing.empty?
      Status.new(
        name: "Google OAuth (sign-in / mailbox connect)",
        state: :ok,
        details: "Client credentials configured.",
        recommendation: nil
      )
    else
      Status.new(
        name: "Google OAuth (sign-in / mailbox connect)",
        state: :missing,
        details: "Missing: #{missing.join(', ')}.",
        recommendation: "Set the environment variables and redeploy. The Connect button on Admin → Mailbox is disabled until both are present."
      )
    end
  end

  def gemini
    if ENV["GEMINI_API_KEY"].present?
      Status.new(
        name: "Gemini API (PDF extraction)",
        state: :ok,
        details: "API key configured.",
        recommendation: nil
      )
    else
      Status.new(
        name: "Gemini API (PDF extraction)",
        state: :missing,
        details: "GEMINI_API_KEY is not set. New job uploads will skip data extraction.",
        recommendation: "Set GEMINI_API_KEY and redeploy. See production setup §0.1."
      )
    end
  end

  def active_storage
    gcs_partial = ApplicationHelper::GCS_ENV_VARS.any? { |k| ENV[k].present? }
    aws_partial = ApplicationHelper::AWS_ENV_VARS.any? { |k| ENV[k].present? }
    gcs_full    = ApplicationHelper::GCS_ENV_VARS.all? { |k| ENV[k].present? }
    aws_full    = ApplicationHelper::AWS_ENV_VARS.all? { |k| ENV[k].present? }

    if gcs_full
      Status.new(
        name: "Active Storage",
        state: :ok,
        details: "Google Cloud Storage · bucket #{ENV['GCS_BUCKET']} · project #{ENV['GCS_PROJECT']}.",
        recommendation: nil
      )
    elsif aws_full
      Status.new(
        name: "Active Storage",
        state: :ok,
        details: "Amazon S3 · bucket #{ENV['AWS_BUCKET']} · region #{ENV['AWS_REGION']}.",
        recommendation: nil
      )
    elsif gcs_partial
      missing = ApplicationHelper::GCS_ENV_VARS.reject { |k| ENV[k].present? }
      Status.new(
        name: "Active Storage",
        state: :warn,
        details: "Partial GCS config — missing: #{missing.join(', ')}.",
        recommendation: "Finish the GCS setup or remove the partial config and use AWS instead."
      )
    elsif aws_partial
      missing = ApplicationHelper::AWS_ENV_VARS.reject { |k| ENV[k].present? }
      Status.new(
        name: "Active Storage",
        state: :warn,
        details: "Partial S3 config — missing: #{missing.join(', ')}.",
        recommendation: "Finish the S3 setup or remove the partial config and use GCS instead."
      )
    else
      Status.new(
        name: "Active Storage",
        state: :missing,
        details: "No GCS or S3 configuration. Uploads will fall back to local disk and will not survive a dyno restart.",
        recommendation: "Configure GCS_* (preferred) or AWS_*. See production setup §0.1a / §0.4."
      )
    end
  end

  def sidekiq_redis
    url = ENV["REDIS_URL"]
    if url.blank?
      Status.new(
        name: "Redis (Sidekiq)",
        state: :missing,
        details: "REDIS_URL is not set. Sidekiq cannot run; outbound campaign emails will not send.",
        recommendation: "Provision the Heroku Key-Value Store add-on (sets REDIS_URL automatically). See §0.3."
      )
    else
      scheme, host = redis_summary(url)
      Status.new(
        name: "Redis (Sidekiq)",
        state: :ok,
        details: "#{scheme}://#{host}",
        recommendation: nil
      )
    end
  end

  def app_host
    return dev_skip("App host (mailer URLs)") if Rails.env.development?

    if ENV["APP_HOST"].present?
      Status.new(
        name: "App host (mailer URLs)",
        state: :ok,
        details: "APP_HOST = #{ENV['APP_HOST']}.",
        recommendation: nil
      )
    else
      Status.new(
        name: "App host (mailer URLs)",
        state: :missing,
        details: "APP_HOST is not set. Invitation and password-reset emails will go out with localhost links.",
        recommendation: "Set APP_HOST to your Heroku domain and redeploy. See production setup §0.4 / §0.5."
      )
    end
  end

  def sentry
    if ENV["SENTRY_DSN"].present?
      Status.new(
        name: "Sentry (error reporting)",
        state: :ok,
        details: "DSN configured.",
        recommendation: nil
      )
    else
      Status.new(
        name: "Sentry (error reporting)",
        state: :warn,
        details: "SENTRY_DSN not set; falling back to the bundled default DSN. Errors are reported to a shared project, not yours.",
        recommendation: "Set your own SENTRY_DSN to scope errors to your own project."
      )
    end
  end

  def test_to_email
    return prod_skip("Test override (TEST_TO_EMAIL)") unless Rails.env.development?

    if ENV["TEST_TO_EMAIL"].present?
      Status.new(
        name: "Test override (TEST_TO_EMAIL)",
        state: :ok,
        details: "All campaign mail in this dev environment is redirected to #{ENV['TEST_TO_EMAIL']}.",
        recommendation: nil
      )
    else
      Status.new(
        name: "Test override (TEST_TO_EMAIL)",
        state: :missing,
        details: "Not set. Campaign sweeps in development are a no-op — nothing sends.",
        recommendation: "Set TEST_TO_EMAIL=you@example.com to see campaign mail land in your own inbox."
      )
    end
  end

  def dev_skip(name)
    Status.new(name: name, state: :ok, details: "Not required in development.", recommendation: nil)
  end

  def prod_skip(name)
    Status.new(name: name, state: :ok, details: "Only relevant in development.", recommendation: nil)
  end

  def redis_summary(url)
    parsed = URI.parse(url)
    [parsed.scheme || "redis", parsed.host || "(unknown)"]
  rescue URI::InvalidURIError
    ["?", url.to_s.slice(0, 40)]
  end

  def time_ago(t)
    "#{ActionController::Base.helpers.time_ago_in_words(t)} ago"
  end

  def time_until(t)
    ActionController::Base.helpers.time_ago_in_words(t)
  end
end
