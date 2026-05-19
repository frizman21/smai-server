# Steps for features/campaign_maintenance.feature (user guide §4).

# --- §4a Uploading a job -------------------------------------------------

Given("my tenant has an activated scenario") do
  activate_catalog_for_tenant
end

When("I open the New Job page and upload a sample proposal") do
  visit new_job_proposal_path
  attach_file "file", sample_pdf_path
  # The Upload button starts disabled (JavaScript enables it once a file
  # is chosen); the rack_test driver runs no JS, so click it as-is.
  find_button("Upload", disabled: :all).click
end

Then("I land on the Confirm page for the new job") do
  expect(page).to have_content("Confirm")
  expect(page).to have_content("Proposal uploaded")
end

# --- §4b The Jobs board --------------------------------------------------

Given("a job proposal at my location") do
  @proposal = build_proposal(owner: originator_user)
end

When("I open the Jobs board") do
  visit job_proposals_path
end

Then("I see the proposal on the board with an action button") do
  expect(page).to have_css(".jp-card")
  expect(page).to have_content(@proposal.customer_last_name)
  expect(page).to have_link("Review")
end

# --- §4c Pausing & resuming ----------------------------------------------

Given("a job proposal at my location with a running campaign") do
  @proposal = build_proposal(owner: originator_user, status: :approved, pipeline_stage: :in_campaign)
  @instance = attach_campaign_instance(@proposal, status: :active)
end

When("I open the proposal's page") do
  visit job_proposal_path(@proposal)
end

Then("the campaign is paused") do
  expect(@instance.reload.status_paused?).to be(true)
  expect(@proposal.reload.status_overlay).to eq("paused")
end

When("I resume the campaign from the Jobs board") do
  visit job_proposals_path
  click_on "Resume"
end

Then("the campaign is running again") do
  expect(@instance.reload.status_active?).to be(true)
  expect(@proposal.reload.status_overlay).to be_nil
end

# --- §4d Customer responds -----------------------------------------------

Given("a job proposal whose customer has replied") do
  @proposal = build_proposal(
    owner: originator_user, status: :approved,
    pipeline_stage: :in_campaign, status_overlay: "customer_waiting"
  )
  campaign = approved_campaign
  instance = CampaignInstance.create!(host: @proposal, campaign: campaign, status: :stopped_on_reply)
  CampaignStepInstance.create!(
    campaign_instance: instance,
    campaign_step: campaign.steps.first,
    email_delivery_status: :sent,
    gmail_thread_id: "CUKE-THREAD-1"
  )
end

Then("the proposal's action button opens the Gmail conversation") do
  link = find("a", text: "Open in Gmail")
  expect(link[:href]).to include("mail.google.com")
  expect(link[:href]).to include("CUKE-THREAD-1")
  expect(link[:target]).to eq("_blank")
end

# --- §4e Won / lost ------------------------------------------------------

Given("a loss reason {string} exists") do |display_name|
  LossReason.find_or_create_by!(code: display_name.parameterize(separator: "_")) do |r|
    r.display_name = display_name
    r.sort_order = 1
  end
end

Given("a job proposal at my location in a campaign") do
  @proposal = build_proposal(owner: originator_user, status: :approved, pipeline_stage: :in_campaign)
end

Then("the job is marked won") do
  expect(@proposal.reload.pipeline_stage).to eq("won")
end

When("I mark the job lost") do
  within("#markLostModal") do
    select "Other", from: "Loss reason"
    fill_in "Loss notes", with: "Customer went silent."
    click_on "Mark Lost"
  end
end

Then("the job is marked lost") do
  expect(@proposal.reload.pipeline_stage).to eq("lost")
end
