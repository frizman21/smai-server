require "test_helper"

class Admin::TenantsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:admin)
    @non_admin = users(:one)
  end

  test "non-admin cannot reach the new tenant form" do
    sign_in @non_admin
    get new_admin_tenant_url
    assert_redirected_to root_path
  end

  test "admin sees the new tenant form" do
    sign_in @admin
    get new_admin_tenant_url
    assert_response :success
    assert_select "form input[name='tenant[name]']"
  end

  test "create makes a tenant" do
    sign_in @admin
    assert_difference "Tenant.count", 1 do
      post admin_tenants_url, params: { tenant: { name: "Acme Roofing" } }
    end

    tenant = Tenant.find_by!(name: "Acme Roofing")
    assert_redirected_to admin_tenant_path(tenant)
  end

  test "create with a blank name re-renders the form" do
    sign_in @admin
    assert_no_difference "Tenant.count" do
      post admin_tenants_url, params: { tenant: { name: "" } }
    end
    assert_response :unprocessable_content
  end

  test "show renders the invitation form when a tenant exists and the prereqs are met" do
    ApplicationMailbox.create!(provider: "google_oauth2", email: "noreply@app.example.com", access_token: "tok")
    sign_in @admin
    get admin_tenant_url(tenants(:one))
    assert_response :success
    assert_select "form[action=?]", admin_tenant_invitations_path(tenants(:one))
    assert_select "input[name='invitation[email]']"
  end

  test "edit renders the form" do
    sign_in @admin
    get edit_admin_tenant_url(tenants(:one))
    assert_response :success
    assert_select "input[name='tenant[name]']"
    assert_select "input[name='tenant[company_name]']"
    assert_select "input[name='tenant[logo_url]']"
    assert_select "input[name='tenant[job_reference_required]']"
  end

  test "update writes an audit log entry capturing the change" do
    sign_in @admin
    tenant = tenants(:one)
    assert_difference "AuditLog.count", 1 do
      patch admin_tenant_url(tenant), params: { tenant: {
        name: tenant.name,
        company_name: "Servpro of NE Dallas",
        logo_url: "https://example.com/logo.png",
        job_reference_required: "1"
      } }
    end
    assert_redirected_to admin_tenant_path(tenant)
    tenant.reload
    assert_equal "Servpro of NE Dallas", tenant.company_name
    assert tenant.job_reference_required
    log = AuditLog.where(target_type: "Tenant", target_id: tenant.id, action: "tenant.update").last
    assert_equal @admin, log.actor_user
    assert_equal "Servpro of NE Dallas", log.payload["after"]["company_name"]
  end

  test "update accepts a logo file upload via Active Storage" do
    sign_in @admin
    tenant = tenants(:one)
    file = Rack::Test::UploadedFile.new(StringIO.new("fake image bytes"), "image/png", original_filename: "logo.png")

    assert_difference "ActiveStorage::Attachment.count", 1 do
      patch admin_tenant_url(tenant), params: { tenant: { name: tenant.name, logo: file } }
    end
    assert_redirected_to admin_tenant_path(tenant)
    tenant.reload
    assert tenant.logo.attached?
    assert_equal "logo.png", tenant.logo.filename.to_s
  end

  test "non-admin can't edit or update a tenant" do
    sign_in @non_admin
    get edit_admin_tenant_url(tenants(:one))
    assert_redirected_to root_path

    assert_no_difference "AuditLog.count" do
      patch admin_tenant_url(tenants(:one)), params: { tenant: { name: "Hacked" } }
    end
    assert_redirected_to root_path
  end

  test "show replaces the invitation form with a warning when the mailbox isn't connected" do
    sign_in @admin
    get admin_tenant_url(tenants(:one))
    assert_response :success
    assert_select "form[action=?]", admin_tenant_invitations_path(tenants(:one)), count: 0
    assert_match(/Invitations aren't ready to send/i, response.body)
    assert_match(/Gmail account is connected/i, response.body)
  end

  test "show indicates Gmail OAuth status for each user in the tenant" do
    linked_user = users(:one)
    unlinked_user = User.create!(
      email: "no-gmail@example.com",
      password: "password123",
      tenant: tenants(:one),
      is_pending: false
    )
    expired_user = User.create!(
      email: "expired-gmail@example.com",
      password: "password123",
      tenant: tenants(:one),
      is_pending: false
    )
    EmailDelegation.create!(
      user: linked_user,
      provider: "google_oauth2",
      email: "linked@gmail.example.com",
      access_token: "tok"
    )
    EmailDelegation.create!(
      user: expired_user,
      provider: "google_oauth2",
      email: "expired@gmail.example.com",
      access_token: "tok",
      expires_at: 1.day.ago,
      refresh_token: nil
    )

    sign_in @admin
    get admin_tenant_url(tenants(:one))
    assert_response :success
    assert_match(/linked@gmail\.example\.com/, response.body)
    assert_match(/expired@gmail\.example\.com/, response.body)
    assert_select "th", text: "Gmail"
    assert_select "tr", text: /#{Regexp.escape(unlinked_user.email)}.*Not linked/m
    assert_select "tr", text: /#{Regexp.escape(expired_user.email)}.*Expired/m
  end
end
