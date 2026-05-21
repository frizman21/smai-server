require "test_helper"

class EmailDelegationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "delegation-test@example.com", password: "Password1", is_pending: false)
  end

  def build_delegation(scopes:)
    EmailDelegation.new(
      user: @user, provider: "google_oauth2",
      email: "delegate@gmail.example.com", access_token: "tok", scopes: scopes
    )
  end

  test "granted_scopes splits the space-delimited scope string" do
    delegation = build_delegation(scopes: "email https://www.googleapis.com/auth/gmail.send")
    assert_equal ["email", "https://www.googleapis.com/auth/gmail.send"], delegation.granted_scopes
  end

  test "granted_scopes is empty when no scopes were recorded" do
    assert_equal [], build_delegation(scopes: nil).granted_scopes
  end

  test "can_send? is true when the gmail.send scope was granted" do
    delegation = build_delegation(scopes: "email https://www.googleapis.com/auth/gmail.send")
    assert delegation.can_send?
  end

  test "can_send? is false when the gmail.send scope was not granted" do
    delegation = build_delegation(scopes: "email https://www.googleapis.com/auth/gmail.metadata")
    assert_not delegation.can_send?
  end
end
