require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
  end

  test "show redirects to sign-in when not signed in" do
    get profile_url
    assert_redirected_to new_user_session_path
  end

  test "show renders the user's profile" do
    sign_in @user
    get profile_url
    assert_response :success
    assert_match @user.email, response.body
    assert_select "a[href=?]", edit_profile_path, text: "Edit"
  end

  test "show offers Setup G Suite when the user has no email delegations" do
    sign_in @user
    get profile_url
    assert_select "form[action='/auth/google_oauth2']"
    assert_match "No connected accounts", response.body
  end

  test "show hides Setup G Suite once the user has connected an account" do
    @user.email_delegations.create!(provider: "google_oauth2", email: "owner@example.com", access_token: "tok")
    sign_in @user
    get profile_url
    assert_select "form[action='/auth/google_oauth2']", false
    assert_match "owner@example.com", response.body
    # Disconnect button is still rendered for the existing delegation
    assert_select "form[action=?]", email_delegation_path(@user.email_delegations.first)
  end

  test "show warns when a connected account is missing required Gmail scopes" do
    @user.email_delegations.create!(
      provider: "google_oauth2", email: "owner@example.com", access_token: "tok",
      scopes: "email https://www.googleapis.com/auth/gmail.send"
    )
    sign_in @user
    get profile_url
    assert_response :success
    assert_match(/missing permissions ServiceMark AI needs/i, response.body)
    assert_match "Read email metadata", response.body
  end

  test "show does not warn when a connected account has every required Gmail scope" do
    @user.email_delegations.create!(
      provider: "google_oauth2", email: "owner@example.com", access_token: "tok",
      scopes: "email https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.metadata"
    )
    sign_in @user
    get profile_url
    assert_response :success
    assert_no_match(/missing permissions ServiceMark AI needs/i, response.body)
  end

  test "edit renders the form with current profile values" do
    @user.update!(first_name: "Jane", last_name: "Doe", phone_number: "555-1234")
    sign_in @user
    get edit_profile_url
    assert_response :success
    assert_select "input[name='user[first_name]'][value='Jane']"
    assert_select "input[name='user[last_name]'][value='Doe']"
    assert_select "input[name='user[phone_number]'][value='555-1234']"
    assert_select "input[name='user[email]']", false  # email is intentionally not in this form
  end

  test "update with valid params saves and redirects to show" do
    sign_in @user
    patch profile_url, params: { user: { first_name: "Jane", last_name: "Doe", phone_number: "555-7777", title: "Estimator" } }
    assert_redirected_to profile_path
    @user.reload
    assert_equal "Jane", @user.first_name
    assert_equal "Doe", @user.last_name
    assert_equal "555-7777", @user.phone_number
    assert_equal "Estimator", @user.title
  end

  test "update ignores email even if submitted" do
    sign_in @user
    original_email = @user.email
    patch profile_url, params: { user: { first_name: "Jane", email: "hacker@example.com" } }
    assert_redirected_to profile_path
    @user.reload
    assert_equal "Jane", @user.first_name
    assert_equal original_email, @user.email
  end

  # --- role indicators ----------------------------------------------------

  test "show renders Application Admin badge for is_admin users" do
    sign_in users(:admin)
    get profile_url
    assert_select "dd", text: /Application Admin/
  end

  test "show renders Tenant Admin badge for tenant users with no location" do
    @user.update!(location: nil)
    sign_in @user
    get profile_url
    assert_select "dd", text: /Tenant Admin/
    assert_no_match(/Application Admin/, response.body)
  end

  test "show hides Tenant Admin badge for tenant users with a location" do
    @user.update!(location: locations(:ne_dallas))
    sign_in @user
    get profile_url
    assert_no_match(/Tenant Admin/, response.body)
    assert_match locations(:ne_dallas).display_name, response.body
  end

  test "show renders both badges when an application admin also has a tenant and no location" do
    admin = users(:admin)
    admin.update!(tenant: tenants(:one), location: nil)
    sign_in admin
    get profile_url
    assert_match(/Application Admin/, response.body)
    assert_match(/Tenant Admin/, response.body)
  end

  test "show falls back to em-dash when user has no role indicators" do
    orphan = User.create!(email: "no-role@example.com", password: "Password1", is_pending: false)
    sign_in orphan
    get profile_url
    # Role row's dd shows "—" when neither badge applies
    assert_select "dt", text: "Role"
    assert_no_match(/Application Admin/, response.body)
    assert_no_match(/Tenant Admin/, response.body)
  end
end
