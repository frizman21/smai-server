Feature: User onboarding and account
  Mirrors docs/user-guide/03-user-onboarding-and-account.md — the things
  a tenant user handles for their own account: accepting an invitation,
  signing in, resetting a password, editing a profile, and inviting
  teammates.

  Scenario: §3.1 An invitation link leads to the sign-up page
    Given an invitation has been sent to "newhire@example.com"
    When I open the invitation link
    Then I land on the sign-up page

  Scenario: §3.2 Signing in takes an originator to Needs Attention
    Given I am signed in as an originator
    Then I land on the Needs Attention page

  Scenario: §3.3 Resetting my password
    Given a tenant user with email "reset-me@example.com"
    When I request a password reset for "reset-me@example.com"
    And I open the reset link and set a new password
    Then I can sign in with the new password

  Scenario: §3.4 Editing my profile
    Given I am signed in as an originator
    When I open my profile and change my first name to "Quincy"
    Then my profile shows "Quincy"

  Scenario: §3.5 My profile offers a Google connection for sending email
    Given I am signed in as an originator
    When I open my profile
    Then I see the Email sending card

  Scenario: §3.6 Inviting a teammate
    Given I am signed in as an account admin
    When I open the Team page
    And I invite "teammate@example.com" as an originator
    Then "teammate@example.com" appears under Pending invitations
