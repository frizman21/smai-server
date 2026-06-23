require "test_helper"

class EmailDelegationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "1234567890",
      info: { email: "owner@example.com", name: "Owner" },
      credentials: {
        token: "access-token-abc",
        refresh_token: "refresh-token-xyz",
        expires_at: 1.hour.from_now.to_i,
        scope: "email profile https://www.googleapis.com/auth/gmail.send"
      },
      extra: { raw_info: { scope: "email profile https://www.googleapis.com/auth/gmail.send" } }
    )
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "callback redirects unauthenticated users to sign-in" do
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
    get "/auth/google_oauth2/callback"
    assert_redirected_to new_user_session_path
  end

  test "callback creates an EmailDelegation tied to the current user" do
    sign_in @user
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]

    assert_difference -> { @user.email_delegations.count }, 1 do
      get "/auth/google_oauth2/callback"
    end
    assert_redirected_to profile_path
    follow_redirect!
    assert_match "Connected owner@example.com", response.body

    delegation = @user.email_delegations.last
    assert_equal "google_oauth2", delegation.provider
    assert_equal "owner@example.com", delegation.email
    assert_equal "access-token-abc", delegation.access_token
    assert_equal "refresh-token-xyz", delegation.refresh_token
    assert delegation.expires_at > Time.current
    assert_includes delegation.scopes, "gmail.send"
  end

  test "callback updates an existing delegation rather than duplicating" do
    sign_in @user
    @user.email_delegations.create!(
      provider: "google_oauth2",
      email: "owner@example.com",
      access_token: "old-token",
      refresh_token: "old-refresh"
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]

    assert_no_difference -> { @user.email_delegations.count } do
      get "/auth/google_oauth2/callback"
    end
    delegation = @user.email_delegations.first
    assert_equal "access-token-abc", delegation.access_token
    assert_equal "refresh-token-xyz", delegation.refresh_token
  end

  # Google omits the refresh token on a reconnect when it still remembers a
  # prior grant. A delegation saved without one can't be renewed and dies at
  # access-token expiry, so the callback must refuse to persist it rather than
  # create a connection that silently breaks within the hour.
  test "callback refuses to save a new delegation when Google returns no refresh token" do
    sign_in @user
    OmniAuth.config.mock_auth[:google_oauth2] = auth_without_refresh_token
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]

    assert_no_difference -> { @user.email_delegations.count } do
      get "/auth/google_oauth2/callback"
    end
    assert_redirected_to profile_path
    follow_redirect!
    assert_match(/return a renewal token/i, response.body)
    assert_match %r{myaccount\.google\.com/permissions}, response.body
  end

  # The legitimate reconnect case: a delegation already has a stored refresh
  # token and Google returns none. The stored token is preserved and the
  # connection keeps working — the guard must not block this.
  test "callback keeps an existing delegation working when reconnect returns no refresh token" do
    sign_in @user
    @user.email_delegations.create!(
      provider: "google_oauth2",
      email: "owner@example.com",
      access_token: "old-token",
      refresh_token: "kept-refresh"
    )
    OmniAuth.config.mock_auth[:google_oauth2] = auth_without_refresh_token
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]

    assert_no_difference -> { @user.email_delegations.count } do
      get "/auth/google_oauth2/callback"
    end
    assert_redirected_to profile_path
    delegation = @user.email_delegations.first
    assert_equal "access-token-abc", delegation.access_token, "access token should refresh"
    assert_equal "kept-refresh", delegation.refresh_token, "stored refresh token should be preserved"
  end

  test "failure path shows an alert" do
    sign_in @user
    get "/auth/failure", params: { message: "invalid_credentials" }
    assert_redirected_to profile_path
    follow_redirect!
    assert_match(/invalid_credentials/i, response.body)
  end

  test "destroy removes the delegation" do
    sign_in @user
    delegation = @user.email_delegations.create!(
      provider: "google_oauth2",
      email: "owner@example.com",
      access_token: "tok"
    )

    assert_difference -> { @user.email_delegations.count }, -1 do
      delete email_delegation_path(delegation)
    end
    assert_redirected_to profile_path
  end

  test "user can't destroy another user's delegation" do
    other = User.create!(email: "stranger@example.com", password: "Password1", tenant: tenants(:one), is_pending: false)
    delegation = other.email_delegations.create!(
      provider: "google_oauth2",
      email: "stranger-gmail@example.com",
      access_token: "tok"
    )

    sign_in @user
    assert_no_difference -> { EmailDelegation.count } do
      delete email_delegation_path(delegation)
    end
    assert delegation.reload.persisted?
  end

  # --- application mailbox round-trip ---
  #
  # The Connect / Reconnect form on admin/application_mailbox/show.html.erb
  # tells OmniAuth where to write the resulting OAuth token via a
  # `target=application_mailbox` URL-query-string param. OmniAuth's request
  # phase captures URL params into the session under "omniauth.params"; the
  # callback phase restores them into request.env. To exercise that round
  # trip in tests we drive the request phase first (allowing GET so we
  # bypass omniauth-rails_csrf_protection) and follow the mock redirect to
  # the callback path.

  # A google_oauth2 auth hash with no refresh token, mirroring what Google
  # returns on a reconnect when it still holds a prior grant.
  def auth_without_refresh_token
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "1234567890",
      info: { email: "owner@example.com", name: "Owner" },
      credentials: {
        token: "access-token-abc",
        refresh_token: nil,
        expires_at: 1.hour.from_now.to_i,
        scope: "email profile https://www.googleapis.com/auth/gmail.send"
      },
      extra: { raw_info: { scope: "email profile https://www.googleapis.com/auth/gmail.send" } }
    )
  end

  def with_omniauth_get_allowed
    prior = OmniAuth.config.allowed_request_methods.dup
    OmniAuth.config.allowed_request_methods = [:get]
    yield
  ensure
    OmniAuth.config.allowed_request_methods = prior
  end

  test "round-trip with target=application_mailbox writes the singleton ApplicationMailbox when the user is admin" do
    admin = users(:admin)
    sign_in admin

    with_omniauth_get_allowed do
      assert_no_difference -> { admin.email_delegations.count } do
        assert_difference "ApplicationMailbox.count", 1 do
          get "/auth/google_oauth2?target=application_mailbox"
          follow_redirect! # mock_request_call → /auth/google_oauth2/callback
        end
      end
    end

    mailbox = ApplicationMailbox.first
    assert_equal "owner@example.com", mailbox.email
    assert_equal "access-token-abc", mailbox.access_token
    assert_equal "refresh-token-xyz", mailbox.refresh_token
    assert_includes mailbox.scopes, "gmail.send"
    assert_redirected_to admin_application_mailbox_path
    follow_redirect!
    assert_match(/Application mailbox connected/i, response.body)
  end

  test "round-trip updates the existing ApplicationMailbox rather than duplicating" do
    admin = users(:admin)
    ApplicationMailbox.create!(provider: "google_oauth2", email: "old@example.com", access_token: "old")
    sign_in admin

    with_omniauth_get_allowed do
      assert_no_difference "ApplicationMailbox.count" do
        get "/auth/google_oauth2?target=application_mailbox"
        follow_redirect!
      end
    end

    mailbox = ApplicationMailbox.first
    assert_equal "owner@example.com", mailbox.email
    assert_equal "access-token-abc", mailbox.access_token
  end

  test "round-trip with target=application_mailbox refuses non-admin users (no token written anywhere)" do
    sign_in @user # tenant user, not admin

    with_omniauth_get_allowed do
      assert_no_difference -> { @user.email_delegations.count } do
        assert_no_difference "ApplicationMailbox.count" do
          get "/auth/google_oauth2?target=application_mailbox"
          follow_redirect!
        end
      end
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_match(/Only an admin/i, response.body)
  end

  test "round-trip without target falls back to the per-user delegation path even for an admin" do
    admin = users(:admin)
    sign_in admin

    with_omniauth_get_allowed do
      assert_no_difference "ApplicationMailbox.count" do
        assert_difference -> { admin.email_delegations.count }, 1 do
          get "/auth/google_oauth2"
          follow_redirect!
        end
      end
    end

    assert_redirected_to profile_path
  end
end
