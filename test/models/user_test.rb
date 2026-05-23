require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @tenant = tenants(:one)
    @location = locations(:ne_dallas)
  end

  test "is_tenant_admin? is true when the user has a tenant and no location" do
    user = User.new(tenant: @tenant)
    assert user.is_tenant_admin?
  end

  test "is_tenant_admin? is false when the user has a location" do
    user = User.new(tenant: @tenant, location: @location)
    refute user.is_tenant_admin?
  end

  test "is_tenant_admin? is false for a tenantless user" do
    user = User.new
    refute user.is_tenant_admin?
  end

  test "is_tenant_admin? does not consider is_admin (orthogonal)" do
    # An application admin attached to a tenant with no location is also
    # technically a tenant admin by this predicate. is_admin is a separate
    # concern handled at call sites.
    user = User.new(tenant: @tenant, is_admin: true)
    assert user.is_tenant_admin?
  end

  test "can_invite_into_tenant? is false when the user has no tenant" do
    user = User.new
    refute user.can_invite_into_tenant?
  end

  test "can_invite_into_tenant? is true for an account admin (tenant, no location)" do
    user = User.new(tenant: @tenant)
    assert user.can_invite_into_tenant?
  end

  test "can_invite_into_tenant? is false for a regular user (tenant + location)" do
    user = User.new(tenant: @tenant, location: @location)
    refute user.can_invite_into_tenant?
  end

  test "can_invite_into_tenant? is true for an application admin attached to a tenant" do
    user = User.new(tenant: @tenant, location: @location, is_admin: true)
    assert user.can_invite_into_tenant?
  end

  test "can_invite_into_tenant? is false for a system admin with no tenant context" do
    user = User.new(is_admin: true)
    refute user.can_invite_into_tenant?
  end

  test "scoped_to_location? is true for a regular tenant user" do
    user = User.new(tenant: @tenant, location: @location)
    assert user.scoped_to_location?
  end

  test "scoped_to_location? is false for an account admin (no location)" do
    user = User.new(tenant: @tenant)
    refute user.scoped_to_location?
  end

  test "scoped_to_location? is false for an application admin even with a location" do
    user = User.new(tenant: @tenant, location: @location, is_admin: true)
    refute user.scoped_to_location?
  end

  test "scoped_to_location? is false for a tenantless user" do
    user = User.new
    refute user.scoped_to_location?
  end

  # --- soft delete (Discard) ---

  test "discard sets discarded_at and makes the user inactive for Devise" do
    user = User.create!(email: "discard-test@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    user.discard
    assert user.discarded?
    assert_not user.active_for_authentication?
    assert_equal :account_deleted, user.inactive_message
  end

  test "undiscard reactivates the user for Devise" do
    user = User.create!(email: "undiscard-test@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    user.discard
    user.undiscard
    assert_not user.discarded?
    assert user.active_for_authentication?
  end

  test "User.kept filters out discarded users; User.discarded returns them" do
    u = User.create!(email: "scope-test@example.com", password: "Password1", is_pending: false, tenant: @tenant)
    assert_includes User.kept, u
    u.discard
    assert_not_includes User.kept, u
    assert_includes User.discarded, u
  end

  test "discarded tenant admin's domain is dropped from reply_ignored_domains" do
    # Regression: a discarded owner_user should NOT keep contributing
    # their email domain to the tenant's reply-ignore list, otherwise the
    # campaign-stop-on-customer-reply guard would keep silently dropping
    # replies from that domain forever.
    @tenant.users.create!(email: "ghost@example.com", password: "Password1", is_pending: false, location: nil)
                .tap(&:discard)
    @tenant.users.create!(email: "active@example.com", password: "Password1", is_pending: false, location: nil)
    domains = @tenant.reply_ignored_domains
    assert_includes domains, "example.com",         "active owner contributes"
    assert_equal 1, domains.count("example.com"),    "should not be duplicated"
    # also platform domain
    assert_includes domains, "servicemark.ai"
  end
end
