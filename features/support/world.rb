# Cucumber world helpers shared across all features.
# Loaded automatically by cucumber-rails (via env.rb).
#
# These builders create the records each feature needs. Kept in one place
# so the step definitions stay focused on operator-facing language.
#
# The tenant model is tenant -> locations (the old Organization layer is
# gone). A user with a location is an originator; a tenant user with no
# location is an account admin; is_admin is SMAI platform staff.

require "rspec/expectations"
World(RSpec::Matchers)

module FeatureWorldHelpers
  PASSWORD = "password123".freeze

  # --- Users ---------------------------------------------------------------

  # SMAI platform staff — sees the Platform Admin sidebar group.
  def admin_user
    @admin_user ||= User.create!(
      email: "cuke-staff@example.com",
      password: PASSWORD, password_confirmation: PASSWORD,
      is_admin: true, is_pending: false,
      first_name: "Avery", last_name: "Sloan"
    )
  end

  # Account admin — a tenant user with no location assignment. The tenant
  # is given an active location so invite/upload flows have one to pick.
  def account_admin_user
    @account_admin_user ||= begin
      feature_location
      User.create!(
        email: "cuke-admin@example.com",
        password: PASSWORD, password_confirmation: PASSWORD,
        tenant: feature_tenant, is_pending: false,
        first_name: "Pat", last_name: "Manager"
      )
    end
  end

  # Originator — a tenant user scoped to a single location.
  def originator_user
    @originator_user ||= User.create!(
      email: "cuke-originator@example.com",
      password: PASSWORD, password_confirmation: PASSWORD,
      tenant: feature_tenant, location: feature_location, is_pending: false,
      first_name: "Quinn", last_name: "Estimator"
    )
  end

  # --- Tenant / location ---------------------------------------------------

  def feature_tenant
    @feature_tenant ||= Tenant.create!(name: "Cuke Restoration")
  end

  def feature_location(tenant: feature_tenant)
    @feature_location ||= Location.create!(
      tenant: tenant,
      display_name: "Cuke HQ",
      address_line_1: "100 Main St",
      city: "Dallas", state: "TX", postal_code: "75201",
      phone_number: "(214) 555-0100",
      is_active: true
    )
  end

  # --- Catalog: job type / scenario / campaign -----------------------------

  def feature_job_type(name: "Water Mitigation", code: "water_mitigation")
    JobType.find_or_create_by!(type_code: code) { |jt| jt.name = name }
  end

  def feature_scenario(job_type: feature_job_type, code: "pipe_burst", short_name: "Pipe burst", campaign: nil)
    Scenario.find_or_create_by!(job_type: job_type, code: code) do |s|
      s.short_name = short_name
      s.campaign = campaign
    end
  end

  # A campaign in Draft with an empty draft revision (revision 0).
  def draft_campaign(name: "Cuke Campaign", scenario: nil)
    campaign = Campaign.create!(name: name, status: :draft, attributed_to: scenario)
    campaign.revisions.create!(revision_number: 0, status: :drafting, created_by_user: admin_user)
    campaign
  end

  # An approved campaign with one active revision carrying a single step.
  # This is the shape a launched CampaignInstance needs.
  def approved_campaign(name: "Cuke Outreach", scenario: nil)
    campaign = Campaign.create!(name: name, status: :approved, attributed_to: scenario)
    revision = campaign.revisions.create!(revision_number: 0, status: :active, created_by_user: admin_user)
    CampaignStep.create!(
      campaign: campaign, campaign_revision: revision,
      sequence_number: 1, offset_min: 0,
      template_subject: "Following up", template_body: "Hi {{customer_first_name}}"
    )
    campaign
  end

  # --- Job proposals -------------------------------------------------------

  # Builds a proposal owned by `owner` at their location. Extra attributes
  # (status, pipeline_stage, status_overlay) are merged so callers can put
  # the proposal into whatever state the scenario needs.
  def build_proposal(owner:, **attrs)
    defaults = {
      tenant: owner.tenant,
      location: owner.location || owner.tenant.locations.first,
      owner: owner,
      created_by_user: owner,
      customer_first_name: "Sample",
      customer_last_name: "Customer",
      customer_email: "sample.customer@example.com",
      customer_house_number: "100",
      customer_street: "Main St"
    }
    JobProposal.create!(defaults.merge(attrs))
  end

  # A campaign instance on `proposal` in the given status, backed by a
  # one-step active revision.
  def attach_campaign_instance(proposal, status:)
    campaign = approved_campaign
    CampaignInstance.create!(host: proposal, campaign: campaign, status: status)
  end

  # Activates a job type + scenario for the tenant so an uploaded job has
  # a campaign to attach to. Returns the scenario.
  def activate_catalog_for_tenant(tenant: feature_tenant)
    job_type = feature_job_type
    scenario = feature_scenario(job_type: job_type)
    TenantJobType.find_or_create_by!(tenant: tenant, job_type: job_type) { |r| r.is_active = true }
    TenantScenario.find_or_create_by!(tenant: tenant, scenario: scenario) { |r| r.is_active = true }
    scenario
  end

  # --- Misc ----------------------------------------------------------------

  def sample_pdf_path
    Rails.root.join("features/support/files/sample_proposal.pdf").to_s
  end

  # --- Auth ----------------------------------------------------------------

  def sign_in_via_form(user, password: PASSWORD)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_button "Log in"
  end
end

World(FeatureWorldHelpers)
World(Rails.application.routes.url_helpers)
