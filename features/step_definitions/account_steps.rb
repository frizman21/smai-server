# Steps for features/user_onboarding_and_account.feature (user guide §3).
#
# The "{string} appears under Pending invitations" step is shared with
# §2 and defined in tenant_onboarding_steps.rb.

# --- §3.1 Accepting an invitation ----------------------------------------

Given("an invitation has been sent to {string}") do |email|
  @invitation = Invitation.create!(
    tenant: feature_tenant,
    invited_by_user: admin_user,
    email: email
  )
end

When("I open the invitation link") do
  visit invitation_path(@invitation.token)
end

Then("I land on the sign-up page") do
  expect(page).to have_current_path(/sign_up/)
  expect(page).to have_field("Email")
  expect(page).to have_field("Password")
end

# --- §3.2 Signing in -----------------------------------------------------

Then("I land on the Needs Attention page") do
  expect(page).to have_content("Jobs Requiring Attention")
end

# --- §3.3 Password reset -------------------------------------------------

Given("a tenant user with email {string}") do |email|
  @reset_user = User.create!(
    email: email,
    password: FeatureWorldHelpers::PASSWORD,
    password_confirmation: FeatureWorldHelpers::PASSWORD,
    tenant: feature_tenant,
    is_pending: false
  )
end

When("I request a password reset for {string}") do |email|
  ActionMailer::Base.deliveries.clear
  visit new_user_password_path
  fill_in "Email", with: email
  click_button "Send me password reset instructions"
end

When("I open the reset link and set a new password") do
  visit link_in_last_email(matching: "reset_password_token")
  fill_in "New password", with: "NewPassword2"
  fill_in "Confirm new password", with: "NewPassword2"
  click_button "Change my password"
end

Then("I can sign in with the new password") do
  page.driver.submit :delete, destroy_user_session_path, {}
  visit new_user_session_path
  fill_in "Email", with: @reset_user.email
  fill_in "Password", with: "NewPassword2"
  click_button "Log in"
  expect(page).not_to have_content("Invalid Email or password")
end

# --- §3.4 / §3.5 Profile -------------------------------------------------

When("I open my profile and change my first name to {string}") do |name|
  visit edit_profile_path
  fill_in "First name", with: name
  click_on "Save"
end

Then("my profile shows {string}") do |text|
  expect(page).to have_content(text)
end

When("I open my profile") do
  visit profile_path
end

Then("I see the Email sending card") do
  expect(page).to have_content("Email sending")
end

# --- §3.6 Inviting a teammate --------------------------------------------

When("I open the Team page") do
  visit users_path
end

When("I invite {string} as an originator") do |email|
  fill_in "First name", with: "Sam"
  fill_in "Last name", with: "Teammate"
  fill_in "Email address", with: email
  # The select carries a custom id, so its label's `for` doesn't match —
  # target it by id rather than label text.
  select feature_location.display_name, from: "invite-location-select"
  click_on "Send invite"
end
