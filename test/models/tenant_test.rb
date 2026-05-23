require "test_helper"

class TenantTest < ActiveSupport::TestCase
  test "activated_job_types returns only those with an active join row" do
    tenant = tenants(:one)
    assert_includes tenant.activated_job_types, job_types(:one)
    assert_not_includes tenant.activated_job_types, job_types(:two)
  end

  test "activated_job_types excludes job_types whose join row is inactive" do
    tenant = tenants(:one)
    tenant_job_types(:one_active).update!(is_active: false)
    assert_not_includes tenant.activated_job_types, job_types(:one)
  end

  test "activated_scenarios returns only those with an active join row" do
    tenant = tenants(:one)
    assert_includes tenant.activated_scenarios, scenarios(:sewage_backup)
    assert_not_includes tenant.activated_scenarios, scenarios(:clean_water)
  end

  test "activated_scenarios excludes scenarios whose join row is inactive" do
    tenant = tenants(:one)
    tenant_scenarios(:sewage_active_for_one).update!(is_active: false)
    assert_not_includes tenant.activated_scenarios, scenarios(:sewage_backup)
  end

  test "tenants with no activations get an empty collection, not nil" do
    tenant = tenants(:two)
    assert_equal [], tenant.activated_job_types.to_a
    assert_equal [], tenant.activated_scenarios.to_a
  end

  # --- logo resolution ---------------------------------------------------

  test "logo_image_url returns the manual logo_url when no file is attached" do
    tenant = tenants(:one)
    tenant.update!(logo_url: "https://example.com/logo.png")
    assert_equal "https://example.com/logo.png", tenant.logo_image_url
  end

  test "logo_image_url returns nil when neither attachment nor manual URL is set" do
    tenant = tenants(:one)
    tenant.update!(logo_url: nil)
    assert_nil tenant.logo_image_url
  end

  test "logo_image_url prefers an attached blob over the manual URL" do
    tenant = tenants(:one)
    tenant.update!(logo_url: "https://example.com/manual.png")
    tenant.logo.attach(io: StringIO.new("fake image"), filename: "uploaded.png", content_type: "image/png")
    assert_match(/rails\/active_storage\/blobs/, tenant.logo_image_url)
    refute_match(/manual.png/, tenant.logo_image_url)
  end

  # --- reply-ignored domains ---------------------------------------------

  test "email_domain extracts the lowercased domain" do
    assert_equal "acme.com", Tenant.email_domain("Owner@Acme.com")
    assert_equal "acme.com", Tenant.email_domain(" owner@acme.com ".strip)
  end

  test "email_domain returns nil for values with no domain part" do
    assert_nil Tenant.email_domain(nil)
    assert_nil Tenant.email_domain("")
    assert_nil Tenant.email_domain("not-an-email")
    assert_nil Tenant.email_domain("trailing@")
  end

  test "reply_ignored_domains includes the account owners' domains and the platform domain" do
    tenant = Tenant.create!(name: "Restoration Co")
    User.create!(email: "owner@restoration.co", password: "Password1", tenant: tenant)

    domains = tenant.reply_ignored_domains
    assert_includes domains, "restoration.co"
    assert_includes domains, Tenant::SERVICEMARK_DOMAIN
  end

  test "reply_ignored_domains excludes the domains of location-scoped users" do
    tenant = Tenant.create!(name: "Restoration Co")
    location = tenant.locations.create!(
      display_name: "Main", address_line_1: "1 Main", city: "Dallas",
      state: "TX", postal_code: "75001", phone_number: "(214) 555-0101", is_active: true
    )
    User.create!(email: "owner@restoration.co", password: "Password1", tenant: tenant)
    User.create!(email: "tech@gmail.com", password: "Password1", tenant: tenant, location: location)

    assert_not_includes tenant.reply_ignored_domains, "gmail.com"
  end

  test "reply_ignored_domains de-dupes owners that share a domain" do
    tenant = Tenant.create!(name: "Restoration Co")
    User.create!(email: "owner-a@restoration.co", password: "Password1", tenant: tenant)
    User.create!(email: "owner-b@restoration.co", password: "Password1", tenant: tenant)

    assert_equal 1, tenant.reply_ignored_domains.count("restoration.co")
  end

  test "reply_ignored_sender? is true for the tenant's own domain and the platform domain" do
    tenant = Tenant.create!(name: "Restoration Co")
    User.create!(email: "owner@restoration.co", password: "Password1", tenant: tenant)

    assert tenant.reply_ignored_sender?("someone-else@restoration.co")
    assert tenant.reply_ignored_sender?("staff@servicemark.ai")
    assert tenant.reply_ignored_sender?("Owner@Restoration.CO"), "matching is case-insensitive"
  end

  test "reply_ignored_sender? is false for an outside customer and blank input" do
    tenant = Tenant.create!(name: "Restoration Co")
    User.create!(email: "owner@restoration.co", password: "Password1", tenant: tenant)

    assert_not tenant.reply_ignored_sender?("customer@elsewhere.com")
    assert_not tenant.reply_ignored_sender?(nil)
    assert_not tenant.reply_ignored_sender?("")
  end
end
