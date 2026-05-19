# An ApplicationMailbox must be connected for the app to consider itself
# ready to send invitations and campaign email (Invitation.send_blockers,
# the integrations page). Every scenario runs inside a transaction that
# rolls back, so this is recreated fresh per scenario.
Before do
  unless ApplicationMailbox.exists?
    ApplicationMailbox.create!(
      provider: "google",
      email: "outreach@cuke.test",
      access_token: "cuke-access-token"
    )
  end
end

# Scenarios tagged @pending document an activity in the user guide whose
# Cucumber coverage hasn't landed yet. They show as skipped, not failing,
# so the run summary stays honest about coverage gaps. Nothing is tagged
# @pending today — the hook is kept so a gap can be parked deliberately.
Before("@pending") do
  skip_this_scenario("Pending — see the user guide §ref in the scenario name")
end
