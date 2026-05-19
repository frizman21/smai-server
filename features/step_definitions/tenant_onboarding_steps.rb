# Steps for features/tenant_onboarding.feature (user guide §2).

When("I open the Tenants admin page") do
  visit admin_tenants_path
end

When("I fill in the tenant name {string}") do |name|
  fill_in "Name", with: name
end

Then("the Tenants page lists {string}") do |name|
  visit admin_tenants_path
  expect(page).to have_content(name)
end

Given("a tenant {string}") do |name|
  @tenant = Tenant.create!(name: name)
end

When("I open the admin page for tenant {string}") do |name|
  visit admin_tenant_path(Tenant.find_by!(name: name))
end

When("I fill in the location form for {string}") do |display_name|
  fill_in "Display name", with: display_name
  fill_in "Address line 1", with: "200 Commerce St"
  fill_in "City", with: "Dallas"
  fill_in "State", with: "TX"
  fill_in "Postal code", with: "75201"
  fill_in "Phone number", with: "(214) 555-0199"
  check "Active"
end

Then("the tenant page lists the location {string}") do |display_name|
  expect(page).to have_content(display_name)
end

When("I invite {string} as an account admin") do |email|
  fill_in "First name", with: "Casey"
  fill_in "Last name", with: "Owner"
  fill_in "Email address", with: email
  check "Is Account Admin"
  click_on "Send invite"
end

Then("{string} appears under Pending invitations") do |email|
  expect(page).to have_content("Pending invitations")
  expect(page).to have_content(email)
end

When("I open Manage activations for tenant {string}") do |name|
  visit admin_tenant_activations_path(Tenant.find_by!(name: name))
end

When("I activate the {string} job type") do |job_type_name|
  within(:xpath, "//tr[contains(., '#{job_type_name}')]") do
    click_on "Activate"
  end
end

Then("{string} shows as active on the activations page") do |job_type_name|
  within(:xpath, "//tr[contains(., '#{job_type_name}')]") do
    expect(page).to have_content("Active")
  end
end
