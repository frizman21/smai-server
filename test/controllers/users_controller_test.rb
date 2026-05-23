require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @tenant = Tenant.create!(name: "TenantCo")
    @user = User.create!(
      email: "leader@example.com",
      password: "Password1",
      is_pending: false,
      tenant: @tenant,
      first_name: "Tina",
      last_name: "Lee"
    )
  end

  test "redirects to sign-in when unauthenticated" do
    get users_url
    assert_redirected_to new_user_session_path
  end

  test "lists members of the current user's tenant and shows the invite button" do
    other = User.create!(email: "second@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    ApplicationMailbox.create!(provider: "google_oauth2", email: "noreply@app.example.com", access_token: "tok")

    sign_in @user
    get users_url
    assert_response :success
    assert_match @user.email, response.body
    assert_match other.email, response.body
    assert_match(/Invite user/i, response.body)
    assert_select "form[action=?]", invitations_path
  end

  test "scopes member list to the current user's tenant" do
    other_tenant = Tenant.create!(name: "OtherCo")
    outsider = User.create!(email: "outsider@example.com", password: "Password1", is_pending: false, tenant: other_tenant)

    sign_in @user
    get users_url
    assert_response :success
    assert_no_match outsider.email, response.body
  end

  test "shows pending invitations for the tenant" do
    Invitation.create!(
      tenant: @tenant,
      invited_by_user: @user,
      email: "pending@example.com"
    )

    sign_in @user
    get users_url
    assert_response :success
    assert_match "pending@example.com", response.body
  end

  test "users with a Gmail delegation get a Linked badge with the delegated address" do
    EmailDelegation.create!(
      user: @user,
      provider: "google",
      email: "ops-mike@example.com",
      access_token: "tok"
    )

    sign_in @user
    get users_url
    assert_response :success
    assert_match "Linked", response.body
    assert_match "ops-mike@example.com", response.body
  end

  test "users without a Gmail delegation show 'Not linked'" do
    sign_in @user
    get users_url
    assert_response :success
    assert_match "Not linked", response.body
  end

  test "tenant-less user sees an info message and no invite button" do
    orphan = User.create!(email: "orphan@example.com", password: "Password1", is_pending: false)
    sign_in orphan

    get users_url
    assert_response :success
    assert_match(/not assigned to a tenant/i, response.body)
    assert_no_match(/Invite user/i, response.body)
  end

  test "team table renders Role column with Admin for tenant admins and Originator for users with a location" do
    location = @tenant.locations.create!(
      display_name: "Main", address_line_1: "1 Main", city: "Dallas",
      state: "TX", postal_code: "75001", phone_number: "(214) 555-0101", is_active: true
    )
    User.create!(email: "originator@example.com", password: "Password1", is_pending: false, tenant: @tenant, location: location)

    sign_in @user # @user has tenant: one, no location → tenant admin
    get users_url
    assert_response :success
    assert_select "th", text: "Role"
    # The team table contains both badge labels
    assert_match "Admin", response.body
    assert_match "Originator", response.body
  end

  test "lists the ignored reply domains for the tenant" do
    sign_in @user
    get users_url
    assert_response :success
    assert_match(/Ignored reply domains/i, response.body)
    # @user is the account owner (no location); its email domain is the
    # tenant's own domain, alongside the platform domain.
    assert_match "@example.com", response.body
    assert_match "@servicemark.ai", response.body
  end

  # --- edit / update ------------------------------------------------------

  test "edit redirects to sign-in when not signed in" do
    teammate = User.create!(email: "victim@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    get edit_user_url(teammate)
    assert_redirected_to new_user_session_path
  end

  test "tenant admin can open the edit form for a teammate" do
    teammate = User.create!(email: "teammate@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    sign_in @user # tenant admin (no location)
    get edit_user_url(teammate)
    assert_response :success
    assert_select "form input[name='user[first_name]']"
    assert_select "form input[name='user[last_name]']"
    assert_select "form input[name='user[title]']"
    assert_select "form input[name='user[phone_number]']"
    assert_select "form select[name='user[location_id]']"
  end

  test "tenant admin can update a teammate and writes an audit log row" do
    location = @tenant.locations.create!(
      display_name: "Main", address_line_1: "1 Main", city: "Dallas",
      state: "TX", postal_code: "75001", phone_number: "(214) 555-0101", is_active: true
    )
    teammate = User.create!(email: "teammate-up@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    sign_in @user

    assert_difference "AuditLog.count", 1 do
      patch user_url(teammate), params: { user: {
        first_name: "Pat", last_name: "Quinn",
        title: "Estimator", phone_number: "(214) 555-1212",
        location_id: location.id
      } }
    end
    assert_redirected_to users_path
    teammate.reload
    assert_equal "Pat", teammate.first_name
    assert_equal "Quinn", teammate.last_name
    assert_equal "Estimator", teammate.title
    assert_equal "(214) 555-1212", teammate.phone_number
    assert_equal location, teammate.location
  end

  test "regular tenant user can't reach edit or update" do
    @user.update!(location: locations(:ne_dallas))   # make @user regular
    teammate = User.create!(email: "teammate-blocked@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    sign_in @user

    get edit_user_url(teammate)
    assert_redirected_to users_path
    assert_match(/Only account admins/i, flash[:alert].to_s)

    patch user_url(teammate), params: { user: { first_name: "Hax" } }
    assert_redirected_to users_path
    assert_nil teammate.reload.first_name
  end

  test "edit can't reach a user from another tenant" do
    other_tenant = Tenant.create!(name: "OtherCo")
    outsider = User.create!(email: "outsider-edit@example.com", password: "Password1", is_pending: false, tenant: other_tenant)
    sign_in @user

    get edit_user_url(outsider)
    assert_redirected_to users_path
    assert_match(/not found in your team/i, flash[:alert].to_s)
  end

  test "update drops a tampered location_id from another tenant" do
    other_tenant = Tenant.create!(name: "OtherCo2")
    foreign_location = other_tenant.locations.create!(
      display_name: "Foreign", address_line_1: "9 Foreign", city: "Reno",
      state: "NV", postal_code: "89501", phone_number: "(775) 555-0303", is_active: true
    )
    teammate = User.create!(email: "teammate-cross@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    sign_in @user

    patch user_url(teammate), params: { user: { first_name: "X", location_id: foreign_location.id } }
    assert_redirected_to users_path
    teammate.reload
    assert_equal "X", teammate.first_name
    assert_nil teammate.location_id, "cross-tenant location_id must be dropped"
  end

  test "regular tenant user does not see the Pending invitations card" do
    Invitation.create!(tenant: @tenant, invited_by_user: @user, email: "pending-hidden@example.com")
    @user.update!(location: locations(:ne_dallas)) # regular user
    sign_in @user
    get users_url
    assert_response :success
    assert_no_match(/Pending invitations/i, response.body)
    assert_no_match("pending-hidden@example.com", response.body)
  end

  test "tenant admin still sees the Pending invitations card" do
    Invitation.create!(tenant: @tenant, invited_by_user: @user, email: "pending-shown@example.com")
    sign_in @user # tenant admin
    get users_url
    assert_response :success
    assert_match(/Pending invitations/i, response.body)
    assert_match("pending-shown@example.com", response.body)
  end

  test "regular tenant user (with a location) does not see the Invite button or modal" do
    location = @tenant.locations.create!(
      display_name: "Main", address_line_1: "1 Main", city: "Dallas",
      state: "TX", postal_code: "75001", phone_number: "(214) 555-0101", is_active: true
    )
    regular = User.create!(email: "regular@example.com", password: "Password1", is_pending: false, tenant: @tenant, location: location)
    sign_in regular

    get users_url
    assert_response :success
    assert_no_match(/Invite user/i, response.body)
    assert_select "#inviteUserModal", false
  end
end
