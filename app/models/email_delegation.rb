class EmailDelegation < ApplicationRecord
  belongs_to :user

  # The Gmail scope a campaign send actually needs. Google's granular
  # consent lets a user connect their account while declining individual
  # permissions, so a delegation can exist without this one.
  GMAIL_SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send".freeze

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
end
