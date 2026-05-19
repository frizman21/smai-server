Feature: Tenant onboarding
  Mirrors docs/user-guide/02-tenant-onboarding.md — the system-admin
  activities that stand up a new account.

  Background:
    Given I am signed in as a system admin

  Scenario: §2.1 Create a tenant
    When I open the Tenants admin page
    And I click "New tenant"
    And I fill in the tenant name "Acme Restoration"
    And I click "Create tenant"
    Then the Tenants page lists "Acme Restoration"

  Scenario: §2.2 Add a location to a tenant
    Given a tenant "Acme Restoration"
    When I open the admin page for tenant "Acme Restoration"
    And I click "Add location"
    And I fill in the location form for "Acme — Dallas"
    And I click "Create Location"
    Then the tenant page lists the location "Acme — Dallas"

  Scenario: §2.3 Invite the first account admin for a tenant
    Given a tenant "Acme Restoration"
    When I open the admin page for tenant "Acme Restoration"
    And I invite "owner@acme.example" as an account admin
    Then "owner@acme.example" appears under Pending invitations

  Scenario: §2.4 Activate a job type for a tenant
    Given a tenant "Acme Restoration"
    And a job type "Water Mitigation" in the catalog
    When I open Manage activations for tenant "Acme Restoration"
    And I activate the "Water Mitigation" job type
    Then "Water Mitigation" shows as active on the activations page
