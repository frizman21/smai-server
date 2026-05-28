require "application_system_test_case"

class JobProposalsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @proposal = job_proposals(:in_users_org)
    @proposal.update!(pipeline_stage: :in_campaign)

    visit new_user_session_path
    fill_in "Email", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Log in"
  end

  # --- Mark Won confirmation modal (SPEC-09 v1.2.1 §2.2) -------------------

  test "Mark Won opens a confirmation modal with the exact SPEC-09 copy" do
    visit job_proposal_path(@proposal)

    within "#markWonModal" do
      assert_text "Mark this job as won"
      assert_text "This job will be marked as won. All automated follow-ups will stop and the job will be removed from active campaigns."
      assert_button "Cancel"
      assert_button "Mark Won"
    end
  end

  test "Cancel on the Mark Won modal makes no state change" do
    visit job_proposal_path(@proposal)

    within "#markWonModal" do
      click_button "Cancel"
    end

    @proposal.reload
    assert_equal "in_campaign", @proposal.pipeline_stage
  end

  test "Confirming Mark Won transitions the proposal to won" do
    visit job_proposal_path(@proposal)

    within "#markWonModal" do
      click_button "Mark Won"
    end

    assert_current_path job_proposal_path(@proposal)
    assert_equal "won", @proposal.reload.pipeline_stage
  end

  # --- Outcome action row (SPEC-09 v1.2.1 §8.1) ----------------------------

  test "outcome action row renders both buttons for an in-campaign job" do
    visit job_proposal_path(@proposal)

    assert_selector "button.btn-outline-secondary[data-bs-target='#markWonModal']", text: "Mark Won"
    assert_selector "button.btn-outline-secondary[data-bs-target='#markLostModal']", text: "Mark Lost"
  end

  test "Mark Lost in the outcome row has no red fill on its default state" do
    visit job_proposal_path(@proposal)

    assert_no_selector "button.btn-outline-danger", text: "Mark Lost"
    assert_no_selector "button.btn-danger[data-bs-target='#markLostModal']"
  end

  test "outcome action row is hidden for a won job" do
    @proposal.update!(pipeline_stage: :won)
    visit job_proposal_path(@proposal)

    assert_no_selector "button[data-bs-target='#markWonModal']"
    assert_no_selector "button[data-bs-target='#markLostModal']"
  end

  test "outcome action row is hidden for a lost job" do
    @proposal.update!(
      pipeline_stage: :lost,
      loss_reason: loss_reasons(:price_too_high),
      loss_notes: "Customer chose a cheaper bid."
    )
    visit job_proposal_path(@proposal)

    assert_no_selector "button[data-bs-target='#markWonModal']"
    assert_no_selector "button[data-bs-target='#markLostModal']"
  end

  test "header no longer renders the old Mark Won / Mark Lost buttons" do
    visit job_proposal_path(@proposal)

    assert_no_selector "button.btn-outline-success.btn-sm", text: "Mark Won"
    assert_no_selector "button.btn-outline-danger.btn-sm", text: "Mark Lost"
  end
end
