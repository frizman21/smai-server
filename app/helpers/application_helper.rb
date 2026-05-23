module ApplicationHelper
  APP_NAME = "ServiceMark AI".freeze

  # Combines the page-specific title (set via `content_for :title, "..."`)
  # with the app name suffix. Falls back to the app name alone when a
  # view didn't set a title.
  def page_title
    page = content_for(:title).to_s.strip
    page.present? ? "#{page}. #{APP_NAME}" : APP_NAME
  end

  # URL the layout's 10s background poller hits to refresh the Needs
  # Attention badge and the index-page "Update available" banner. On the
  # job_proposals index we forward the current filter/search params so the
  # poll endpoint computes its list_signature against the exact scope the
  # page rendered — anywhere else, params would just be noise the poll
  # endpoint ignores, so we send the bare path. Sort and pagination are
  # dropped because they don't affect set membership.
  POLL_URL_PASSTHROUGH_KEYS = %w[filter status owner_id creator_id location_id q].freeze

  def current_poll_url
    if controller_path == "job_proposals" && action_name == "index"
      poll_job_proposals_path(request.query_parameters.slice(*POLL_URL_PASSTHROUGH_KEYS))
    else
      poll_job_proposals_path
    end
  end

  # Env vars whose absence we want admins warned about in the UI.
  # Mirrors .env.example so a fresh deploy can spot what's missing at a glance.
  REQUIRED_ENV_VARS = %w[
    GEMINI_API_KEY
    GOOGLE_CLIENT_ID
    GOOGLE_CLIENT_SECRET
  ].freeze

  # Required only in development, where CampaignSweepJob refuses to send
  # unless either Rails.env is production or TEST_TO_EMAIL is set. Surface
  # it in the banner so a developer notices before wondering why nothing
  # is going out.
  DEV_REQUIRED_ENV_VARS = %w[TEST_TO_EMAIL].freeze

  # Required only outside development. APP_HOST drives the host portion of
  # absolute URLs in mailers (invitations, password resets) and is read
  # only by config/environments/production.rb, which falls back to
  # "localhost" if unset. The banner flags it in non-dev environments so
  # the fallback's broken-looking links don't go out unnoticed.
  PROD_REQUIRED_ENV_VARS = %w[APP_HOST].freeze

  # Storage backend env-var groups. Either group fully set is enough —
  # they're alternatives, not both required. Order matches production.rb's
  # selection: GCS preferred, S3 fallback.
  GCS_ENV_VARS = %w[GCS_PROJECT GCS_BUCKET].freeze
  AWS_ENV_VARS = %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET].freeze

  def missing_env_vars
    required = REQUIRED_ENV_VARS.dup
    required.concat(DEV_REQUIRED_ENV_VARS) if development_environment?
    required.concat(PROD_REQUIRED_ENV_VARS) unless development_environment?
    missing = required.reject { |key| ENV[key].present? }
    missing.concat(missing_storage_env_vars)
    missing
  end

  # GCS is preferred when any GCS_* var is set; otherwise we expect AWS_*.
  # The banner surfaces only the gaps for whichever provider the operator
  # appears to have started configuring.
  def missing_storage_env_vars
    if GCS_ENV_VARS.any? { |key| ENV[key].present? }
      GCS_ENV_VARS.reject { |key| ENV[key].present? }
    elsif AWS_ENV_VARS.any? { |key| ENV[key].present? }
      AWS_ENV_VARS.reject { |key| ENV[key].present? }
    else
      ["GCS_BUCKET (or AWS_BUCKET)"]
    end
  end

  def development_environment?
    Rails.env.development?
  end

  GOOGLE_OAUTH_ENV_VARS = %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET].freeze

  def google_oauth_configured?
    GOOGLE_OAUTH_ENV_VARS.all? { |key| ENV[key].present? }
  end

  def missing_google_oauth_env_vars
    GOOGLE_OAUTH_ENV_VARS.reject { |key| ENV[key].present? }
  end

  # Friendly labels for the OAuth scopes we request from Google. Google
  # may report the email/profile scopes in either short form or as full
  # userinfo URLs depending on the consent flow, so both are mapped.
  OAUTH_SCOPE_LABELS = {
    "email"   => "Email address",
    "profile" => "Basic profile",
    "openid"  => "OpenID sign-in",
    "https://www.googleapis.com/auth/userinfo.email"   => "Email address",
    "https://www.googleapis.com/auth/userinfo.profile" => "Basic profile",
    "https://www.googleapis.com/auth/gmail.send"       => "Send email",
    "https://www.googleapis.com/auth/gmail.metadata"   => "Read email metadata"
  }.freeze

  # Operator-readable name for a raw Google OAuth scope string. Unknown
  # scopes fall through to the raw value so nothing is silently hidden.
  def oauth_scope_label(scope)
    OAUTH_SCOPE_LABELS[scope] || scope
  end

  # Render a CampaignStep offset (stored as minutes) in operator-friendly
  # words. Examples:
  #   0    → "Immediately"
  #   45   → "45 minutes"
  #   60   → "1 hour"
  #   240  → "4 hours"
  #   1440 → "1 day"
  #   1530 → "1 day 1 hour 30 minutes"
  def humanize_offset_minutes(minutes)
    n = minutes.to_i
    return "Immediately" if n.zero?

    days, rem  = n.divmod(24 * 60)
    hours, mins = rem.divmod(60)
    parts = []
    parts << pluralize(days,  "day")    if days  > 0
    parts << pluralize(hours, "hour")   if hours > 0
    parts << pluralize(mins,  "minute") if mins  > 0
    parts.join(" ")
  end
end
