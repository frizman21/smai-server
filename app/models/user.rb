class User < ApplicationRecord
  # Soft delete via the discard gem. Unlike JobProposal we deliberately do
  # NOT set `default_scope { kept }` here — many `belongs_to :*_user`
  # associations across the codebase (proposal owner, campaign approver,
  # paper_trail whodunnit lookups) expect a record back even when the user
  # has been off-boarded, and a default scope would silently null them.
  # Listings that should hide discarded users opt in explicitly via `.kept`.
  include Discard::Model

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  belongs_to :tenant, optional: true
  belongs_to :location, optional: true
  has_many :email_delegations, dependent: :destroy

  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }, allow_blank: true

  # Devise's authentication gate. A discarded user is off-boarded — the row
  # stays for audit / FK integrity, but they cannot sign in. The paired
  # #inactive_message keys the flash shown on a blocked sign-in attempt.
  def active_for_authentication?
    super && !discarded?
  end

  def inactive_message
    discarded? ? :account_deleted : super
  end

  # All provider strings this app uses for Google delegations. OmniAuth's
  # Google strategy registers itself as `google_oauth2` (what
  # EmailDelegationsController persists today), but seeds and older fixtures
  # in the wild use the shorter `google`. Match either so a delegation an
  # operator already has connected isn't ignored on a string-mismatch.
  GOOGLE_PROVIDERS = %w[google_oauth2 google].freeze

  # The Gmail OAuth delegation a campaign send for this user (as a proposal
  # originator) would authenticate as. Per PRD-09 v1.3 §1, customer email goes
  # out from the originator's own Gmail — not from a shared location/admin
  # mailbox — so this is what PreSendChecklist and CampaignSweepJob look up
  # before each send. Returns nil when the originator has not connected Gmail.
  def gmail_delegation
    email_delegations.where(provider: GOOGLE_PROVIDERS).first
  end

  def full_name
    [first_name, last_name].compact_blank.join(" ").presence
  end

  def display_name
    full_name || email
  end

  # A tenant admin is a tenant user with no location assignment.
  # Tenant-wide privileges (invite, broad listings, no location filter)
  # are gated on this — sometimes alongside is_admin (SMAI staff) which
  # transcends a single tenant.
  def is_tenant_admin?
    tenant_id.present? && location_id.nil?
  end

  # SMAI staff (is_admin) can invite from any tenant context they're
  # attached to. Tenant admins can invite within their tenant. Regular
  # tenant users (those scoped to a location) can't invite.
  def can_invite_into_tenant?
    return false if tenant_id.nil?
    is_admin || is_tenant_admin?
  end

  # A regular tenant user is bound to a single location and should see
  # only their location's data on tenant-wide listings (the Job Proposals
  # index in particular). Tenant admins (no location) and SMAI staff
  # (is_admin) see broader scope.
  def scoped_to_location?
    !is_admin && tenant_id.present? && location_id.present?
  end
end
