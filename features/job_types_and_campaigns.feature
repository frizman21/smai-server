Feature: Job types and campaigns
  Mirrors docs/user-guide/01-job-types-and-campaigns.md — the admin-only
  catalog of job types, scenarios, and campaigns that every tenant
  inherits.

  Background:
    Given I am signed in as a system admin

  Scenario: §1.1 Create a job type
    When I open the Job Types admin page
    And I click "+ New Job Type"
    And I fill in the job type form with name "Trauma Cleanup" and code "trauma_cleanup"
    And I click "Create Job Type"
    Then the Job Types page lists "Trauma Cleanup"

  Scenario: §1.2 Add a scenario under a job type
    Given a job type "Water Mitigation" in the catalog
    When I open the "Water Mitigation" job type page
    And I click "+ New Scenario"
    And I fill in the scenario form with code "pipe_burst" and short name "Pipe burst"
    And I click "Create Scenario"
    Then the "Water Mitigation" job type page lists the scenario "Pipe burst"

  Scenario: §1.3 Create a campaign
    When I open the Campaigns admin page
    And I click "New campaign"
    And I fill in the campaign name "Pipe Burst — v1"
    And I click "Create Campaign"
    Then the campaign "Pipe Burst — v1" exists as a Draft

  Scenario: §1.4 Add a step to a campaign
    Given a draft campaign "Pipe Burst — v1"
    When I open the draft revision of "Pipe Burst — v1"
    And I click "Add step"
    And I fill in the step subject "Following up" and body "Hi {{customer_first_name}}"
    And I click "Create Campaign step"
    Then the campaign "Pipe Burst — v1" has one step

  Scenario: §1.5 Approve a campaign
    Given a draft campaign "Pipe Burst — v1" with one step
    When I open the campaign page for "Pipe Burst — v1"
    And I click "Approve"
    Then the campaign "Pipe Burst — v1" is Approved

  Scenario: §1.6 Wire a campaign to its scenario
    Given a job type "Water Mitigation" in the catalog
    And a scenario "Pipe burst" under "Water Mitigation"
    And a campaign "Pipe Burst — v1" attributed to the "Pipe burst" scenario
    When I open the edit page for the "Pipe burst" scenario
    And I pick "Pipe Burst — v1" from the Campaign dropdown and save
    Then the "Pipe burst" scenario page links to the campaign "Pipe Burst — v1"
