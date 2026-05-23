require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:admin)
    @non_admin = users(:one)
    @tenant = tenants(:one)
    @teammate = User.create!(email: "admin-edit-victim@example.com", password: "Password1", is_pending: false, tenant: @tenant)
  end

  test "non-admin cannot reach the admin user edit page" do
    sign_in @non_admin
    get edit_admin_tenant_user_url(@tenant, @teammate)
    assert_redirected_to root_path
  end

  test "non-admin cannot update via the admin path" do
    sign_in @non_admin
    patch admin_tenant_user_url(@tenant, @teammate), params: { user: { first_name: "Hax" } }
    assert_redirected_to root_path
    assert_nil @teammate.reload.first_name
  end

  test "admin sees the edit form" do
    sign_in @admin
    get edit_admin_tenant_user_url(@tenant, @teammate)
    assert_response :success
    assert_select "form input[name='user[first_name]']"
    assert_select "form input[name='user[last_name]']"
    assert_select "form input[name='user[title]']"
    assert_select "form input[name='user[phone_number]']"
    assert_select "form select[name='user[location_id]']"
  end

  test "admin can update name, title, phone, and location with audit log" do
    location = locations(:ne_dallas)
    sign_in @admin

    assert_difference "AuditLog.count", 1 do
      patch admin_tenant_user_url(@tenant, @teammate), params: { user: {
        first_name: "Pat", last_name: "Quinn",
        title: "Estimator", phone_number: "(214) 555-1212",
        location_id: location.id
      } }
    end
    assert_redirected_to admin_tenant_path(@tenant)
    @teammate.reload
    assert_equal "Pat", @teammate.first_name
    assert_equal "Quinn", @teammate.last_name
    assert_equal "Estimator", @teammate.title
    assert_equal "(214) 555-1212", @teammate.phone_number
    assert_equal location, @teammate.location

    log = AuditLog.where(target_type: "User", target_id: @teammate.id, action: "user.update").last
    assert_equal @admin, log.actor_user
    assert_equal "Pat", log.payload["after"]["first_name"]
  end

  test "admin update drops a tampered location_id from another tenant" do
    other_tenant = Tenant.create!(name: "OtherCo-admin-edit")
    foreign_location = other_tenant.locations.create!(
      display_name: "Foreign", address_line_1: "9 Foreign", city: "Reno",
      state: "NV", postal_code: "89501", phone_number: "(775) 555-0303", is_active: true
    )
    sign_in @admin

    patch admin_tenant_user_url(@tenant, @teammate), params: { user: {
      first_name: "Pat", location_id: foreign_location.id
    } }
    assert_redirected_to admin_tenant_path(@tenant)
    @teammate.reload
    assert_equal "Pat", @teammate.first_name
    assert_nil @teammate.location_id, "cross-tenant location_id must be dropped"
  end

  test "admin gets a friendly redirect when the user isn't in the tenant" do
    other_tenant = Tenant.create!(name: "OtherCo-edit-mismatch")
    outsider = User.create!(email: "outsider-admin-edit@example.com", password: "Password1", is_pending: false, tenant: other_tenant)
    sign_in @admin
    get edit_admin_tenant_user_url(@tenant, outsider)
    assert_redirected_to admin_tenant_path(@tenant)
    assert_match(/not found in this tenant/i, flash[:alert].to_s)
  end

  test "admin tenant show renders an Edit link for each user" do
    sign_in @admin
    get admin_tenant_url(@tenant)
    assert_response :success
    assert_select "a[href=?]", edit_admin_tenant_user_path(@tenant, @teammate), text: "Edit"
  end

  # --- show ---------------------------------------------------------------

  test "non-admin cannot reach the admin user show page" do
    sign_in @non_admin
    get admin_tenant_user_url(@tenant, @teammate)
    assert_redirected_to root_path
  end

  test "admin sees the user show page with stored profile and activity details" do
    @teammate.update!(
      first_name: "Pat", last_name: "Quinn", title: "Estimator",
      phone_number: "(214) 555-1212", sign_in_count: 3
    )
    EmailDelegation.create!(
      user: @teammate, provider: "google_oauth2",
      email: "pat@gmail.example.com", access_token: "tok"
    )
    sign_in @admin
    get admin_tenant_user_url(@tenant, @teammate)
    assert_response :success
    assert_match @teammate.email,    response.body
    assert_match "Estimator",        response.body
    assert_match "(214) 555-1212",   response.body
    assert_match "pat@gmail.example.com", response.body
    assert_select "body", text: /Sign-in count/
  end

  test "admin user show page lists the OAuth permissions the user granted" do
    EmailDelegation.create!(
      user: @teammate, provider: "google_oauth2",
      email: "pat@gmail.example.com", access_token: "tok",
      scopes: "email https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.metadata"
    )
    sign_in @admin
    get admin_tenant_user_url(@tenant, @teammate)
    assert_response :success
    assert_match "Send email",          response.body
    assert_match "Read email metadata", response.body
    assert_no_match(/Missing the .Send email. permission/, response.body)
  end

  test "admin user show page warns when the send permission was not granted" do
    EmailDelegation.create!(
      user: @teammate, provider: "google_oauth2",
      email: "pat@gmail.example.com", access_token: "tok",
      scopes: "email https://www.googleapis.com/auth/gmail.metadata"
    )
    sign_in @admin
    get admin_tenant_user_url(@tenant, @teammate)
    assert_response :success
    assert_match(/Missing the .Send email. permission/, response.body)
  end

  test "admin user show page does not expose password details" do
    @teammate.update!(reset_password_token: "secret-reset-token")
    sign_in @admin
    get admin_tenant_user_url(@tenant, @teammate)
    assert_response :success
    assert_no_match @teammate.encrypted_password, response.body
    assert_no_match(/secret-reset-token/, response.body)
  end

  test "admin gets a friendly redirect when showing a user not in the tenant" do
    other_tenant = Tenant.create!(name: "OtherCo-show-mismatch")
    outsider = User.create!(email: "outsider-admin-show@example.com", password: "Password1", is_pending: false, tenant: other_tenant)
    sign_in @admin
    get admin_tenant_user_url(@tenant, outsider)
    assert_redirected_to admin_tenant_path(@tenant)
    assert_match(/not found in this tenant/i, flash[:alert].to_s)
  end

  test "admin tenant show links each user name to the user show page" do
    sign_in @admin
    get admin_tenant_url(@tenant)
    assert_response :success
    assert_select "a[href=?]", admin_tenant_user_path(@tenant, @teammate)
  end

  # --- index --------------------------------------------------------------

  test "index redirects to sign-in when not signed in" do
    get admin_users_url
    assert_redirected_to new_user_session_path
  end

  test "non-admin cannot reach the cross-tenant users index" do
    sign_in @non_admin
    get admin_users_url
    assert_redirected_to root_path
  end

  test "admin index lists users from every tenant" do
    sign_in @admin
    get admin_users_url
    assert_response :success
    assert_match users(:one).email,   response.body  # tenant: one
    assert_match users(:two).email,   response.body  # tenant: two
    assert_match @teammate.email,     response.body  # created in setup, tenant: one
  end

  test "tenant filter narrows the index to that tenant's users" do
    sign_in @admin
    get admin_users_url, params: { tenant_id: tenants(:two).id }
    assert_response :success
    assert_match users(:two).email,    response.body
    assert_no_match users(:one).email, response.body
    assert_no_match @teammate.email,   response.body
  end

  test "search query matches by email substring" do
    sign_in @admin
    get admin_users_url, params: { q: "admin-edit-victim" }
    assert_response :success
    assert_match @teammate.email,      response.body
    assert_no_match users(:one).email, response.body
  end

  test "search query matches by full name" do
    @teammate.update!(first_name: "Pat", last_name: "Sample")
    sign_in @admin
    get admin_users_url, params: { q: "pat sample" }
    assert_response :success
    assert_match @teammate.email,      response.body
    assert_no_match users(:one).email, response.body
  end

  test "index renders an Edit link routed through the user's tenant" do
    sign_in @admin
    get admin_users_url
    assert_response :success
    assert_select "a[href=?]", edit_admin_tenant_user_path(@tenant, @teammate), text: "Edit"
  end

  test "index shows a Tenant Admin badge for users with a tenant and no location" do
    @teammate.update!(tenant: @tenant, location: nil)
    sign_in @admin
    get admin_users_url
    assert_response :success
    assert_select "tr", text: /#{@teammate.email}.*Tenant Admin/m
  end
end
