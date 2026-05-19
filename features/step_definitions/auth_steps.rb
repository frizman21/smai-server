# Auth + identity steps used across every feature.
#
# Roles: a system admin is SMAI platform staff; an account admin is a
# tenant user with no location; an originator is a tenant user scoped to
# one location.

Given("I am signed in as a system admin") do
  @current_user = admin_user
  sign_in_via_form(@current_user)
end

Given("I am signed in as an account admin") do
  @current_user = account_admin_user
  sign_in_via_form(@current_user)
end

Given("I am signed in as an originator") do
  @current_user = originator_user
  sign_in_via_form(@current_user)
end
