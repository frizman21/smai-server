class EmailDelegation < ApplicationRecord
  belongs_to :user

  # The Gmail scopes the app needs to run a campaign end to end: send the
  # outbound email and poll the thread for replies and bounces. Google's
  # granular consent lets a user connect their account while declining
  # individual permissions, so a delegation can exist missing either one.
  GMAIL_SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send".freeze
  GMAIL_METADATA_SCOPE = "https://www.googleapis.com/auth/gmail.metadata".freeze
  REQUIRED_GMAIL_SCOPES = [GMAIL_SEND_SCOPE, GMAIL_METADATA_SCOPE].freeze

  validates :provider, :email, :access_token, presence: true
  validates :email, uniqueness: { scope: [:user_id, :provider] }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # The scopes Google reported the user actually granted, parsed from the
  # space-delimited `scopes` string captured at the OAuth callback.
  def granted_scopes
    scopes.to_s.split
  end

  # Whether the user granted the scope required to send campaign email.
  def can_send?
    granted_scopes.include?(GMAIL_SEND_SCOPE)
  end

  # Required Gmail scopes the user did not grant during the OAuth consent.
  def missing_scopes
    REQUIRED_GMAIL_SCOPES - granted_scopes
  end

  # Whether every Gmail scope the app needs was granted.
  def all_scopes_granted?
    missing_scopes.empty?
  end
end
