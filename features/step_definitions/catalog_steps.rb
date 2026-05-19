# Steps for features/job_types_and_campaigns.feature (user guide §1).

# --- Job types -----------------------------------------------------------

When("I open the Job Types admin page") do
  visit admin_job_types_path
end

When("I fill in the job type form with name {string} and code {string}") do |name, code|
  fill_in "Name", with: name
  fill_in "Type code", with: code
end

Then("the Job Types page lists {string}") do |name|
  visit admin_job_types_path
  expect(page).to have_content(name)
end

Given("a job type {string} in the catalog") do |name|
  @job_type = feature_job_type(name: name, code: name.parameterize(separator: "_"))
end

When("I open the {string} job type page") do |name|
  visit admin_job_type_path(JobType.find_by!(name: name))
end

# --- Scenarios -----------------------------------------------------------

When("I fill in the scenario form with code {string} and short name {string}") do |code, short_name|
  fill_in "Code", with: code
  fill_in "Short name", with: short_name
end

Then("the {string} job type page lists the scenario {string}") do |job_type_name, short_name|
  visit admin_job_type_path(JobType.find_by!(name: job_type_name))
  expect(page).to have_content(short_name)
end

Given("a scenario {string} under {string}") do |short_name, job_type_name|
  job_type = feature_job_type(name: job_type_name, code: job_type_name.parameterize(separator: "_"))
  @scenario = feature_scenario(
    job_type: job_type,
    code: short_name.parameterize(separator: "_"),
    short_name: short_name
  )
end

When("I open the edit page for the {string} scenario") do |short_name|
  visit edit_admin_scenario_path(Scenario.find_by!(short_name: short_name))
end

When("I pick {string} from the Campaign dropdown and save") do |campaign_name|
  select campaign_name, from: "Campaign"
  click_on "Save Changes"
end

Then("the {string} scenario page links to the campaign {string}") do |short_name, campaign_name|
  visit admin_scenario_path(Scenario.find_by!(short_name: short_name))
  expect(page).to have_link(campaign_name)
end

# --- Campaigns -----------------------------------------------------------

When("I open the Campaigns admin page") do
  visit admin_campaigns_path
end

When("I fill in the campaign name {string}") do |name|
  fill_in "Name", with: name
end

Then("the campaign {string} exists as a Draft") do |name|
  expect(Campaign.find_by!(name: name).status).to eq("draft")
end

Given("a draft campaign {string}") do |name|
  @campaign = draft_campaign(name: name)
end

Given("a draft campaign {string} with one step") do |name|
  @campaign = draft_campaign(name: name)
  revision = @campaign.revisions.find_by!(status: :drafting)
  CampaignStep.create!(
    campaign: @campaign, campaign_revision: revision,
    sequence_number: 1, offset_min: 0,
    template_subject: "Following up", template_body: "Hi"
  )
end

Given("a campaign {string} attributed to the {string} scenario") do |campaign_name, short_name|
  scenario = Scenario.find_by!(short_name: short_name)
  @campaign = Campaign.create!(name: campaign_name, status: :draft, attributed_to: scenario)
end

When("I open the draft revision of {string}") do |name|
  campaign = Campaign.find_by!(name: name)
  revision = campaign.revisions.find_by!(status: :drafting)
  visit admin_campaign_revision_path(campaign, revision)
end

When("I fill in the step subject {string} and body {string}") do |subject, body|
  fill_in "Subject", with: subject
  fill_in "Body", with: body
end

Then("the campaign {string} has one step") do |name|
  expect(Campaign.find_by!(name: name).steps.count).to eq(1)
end

When("I open the campaign page for {string}") do |name|
  visit admin_campaign_path(Campaign.find_by!(name: name))
end

Then("the campaign {string} is Approved") do |name|
  expect(Campaign.find_by!(name: name).status).to eq("approved")
end
