class Tenant < ApplicationRecord
  # ServiceMark AI's own email domain. Replies from this domain are
  # platform staff, never the customer, so they never stop a campaign —
  # see #reply_ignored_domains. Always present regardless of tenant.
  SERVICEMARK_DOMAIN = "servicemark.ai".freeze

  has_many :locations, dependent: :destroy
  has_many :users, dependent: :nullify
  has_many :job_proposals, dependent: :destroy
  has_many :invitations, dependent: :destroy

  # PRD-10 v1.3.1 §7 / SPEC-07 v1.4 §9 — every campaign email signature
  # references the account's logo. Stored via Active Storage so SMAI staff
  # (or eventually the operator UI) can upload via the admin portal. The
  # string column `logo_url` is preserved as a manual override for tenants
  # who'd rather link to a logo hosted elsewhere.
  has_one_attached :logo
  has_many :tenant_job_types, dependent: :destroy
  has_many :tenant_scenarios, dependent: :destroy

  # Job types and scenarios this tenant is allowed to use. The activation
  # join rows are written by admins via the activations admin UI. The
  # "active" scope on the join itself filters out rows that were activated
  # then deactivated — those rows are kept (not destroyed) so an admin can
  # toggle without losing config history.
  has_many :activated_job_types,
           -> { where(tenant_job_types: { is_active: true }) },
           through: :tenant_job_types,
           source: :job_type
  has_many :activated_scenarios,
           -> { where(tenant_scenarios: { is_active: true }) },
           through: :tenant_scenarios,
           source: :scenario

  validates :name, presence: true

  # Resolves the right URL for templates / signatures: prefer the
  # uploaded logo blob if attached, else the manual `logo_url` string,
  # else nil. Callers handle the nil case.
  def logo_image_url
    return Rails.application.routes.url_helpers.rails_blob_url(logo, only_path: true) if logo.attached?
    logo_url.presence
  end

  # The account's owners: tenant users not pinned to a single location
  # (the same population that carries the tenant-admin role). Their email
  # addresses define what counts as "the tenant's own domain".
  def owner_users
    users.where(location_id: nil)
  end

  # A campaign stops automatically when the *customer* replies. Mail that
  # comes back from the business's own people — a teammate CC'd on the
  # thread, an owner forwarding it internally — is not a customer reply
  # and must not stop the campaign. The same goes for ServiceMark AI staff.
  #
  # This returns the email domains whose replies are ignored for that
  # purpose: the tenant's own domains (derived from the email addresses of
  # #owner_users) plus the platform domain. Downcased and de-duped.
  def reply_ignored_domains
    owner_domains = owner_users.pluck(:email).filter_map { |email| self.class.email_domain(email) }
    (owner_domains << SERVICEMARK_DOMAIN).uniq
  end

  # True when a reply from `email` should NOT stop a campaign because it
  # came from this tenant's own domain or from ServiceMark AI.
  def reply_ignored_sender?(email)
    domain = self.class.email_domain(email)
    domain.present? && reply_ignored_domains.include?(domain)
  end

  # Extracts the lowercased domain from an email address, or nil when the
  # value has no usable domain part.
  def self.email_domain(email)
    domain = email.to_s.split("@", 2)[1]
    domain&.strip&.downcase.presence
  end
end
