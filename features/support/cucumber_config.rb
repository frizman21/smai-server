# Local additions to the cucumber-rails generated env.rb. Kept in a
# separate file so env.rb can be regenerated without losing this.

# Invitations are gated on APP_HOST being set (Invitation.send_blockers) —
# without a host the invite link in the email would be broken, so the UI
# hides the invite form. The feature suite exercises the invite flow, so
# give the test run a host.
ENV["APP_HOST"] ||= "cuke.test"

# Cucumber must never reach the real Gmail API. Referencing the constant
# triggers autoload; prepending an inert #send_mail makes invitation and
# campaign sends resolve deterministically in-process.
module GmailSenderCucumberStub
  def send_mail(*)
    true
  end
end
GmailSender.prepend(GmailSenderCucumberStub)
