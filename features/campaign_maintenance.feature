Feature: Campaign maintenance
  Mirrors docs/user-guide/04-campaign-maintenance.md — the day-to-day
  work an originator does against jobs: uploading them, watching the
  Jobs board, pausing and resuming, handling a reply, and closing them
  out won or lost.

  Background:
    Given I am signed in as an originator

  Scenario: §4a Uploading a job lands on the Confirm page
    Given my tenant has an activated scenario
    When I open the New Job page and upload a sample proposal
    Then I land on the Confirm page for the new job

  Scenario: §4b The Jobs board lists my jobs
    Given a job proposal at my location
    When I open the Jobs board
    Then I see the proposal on the board with an action button

  Scenario: §4c Pausing and resuming a campaign
    Given a job proposal at my location with a running campaign
    When I open the proposal's page
    And I click "Pause"
    Then the campaign is paused
    When I resume the campaign from the Jobs board
    Then the campaign is running again

  Scenario: §4d A customer reply routes me to Gmail
    Given a job proposal whose customer has replied
    When I open the Jobs board
    Then the proposal's action button opens the Gmail conversation

  Scenario: §4e Marking a job as won
    Given a job proposal at my location in a campaign
    When I open the proposal's page
    And I click "Mark Won"
    Then the job is marked won

  Scenario: §4e Marking a job as lost
    Given a loss reason "Other" exists
    And a job proposal at my location in a campaign
    When I open the proposal's page
    And I mark the job lost
    Then the job is marked lost
