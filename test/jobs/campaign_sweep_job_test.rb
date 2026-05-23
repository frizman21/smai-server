require "test_helper"

class CampaignSweepJobTest < ActiveSupport::TestCase
  setup do
    @mailbox = ApplicationMailbox.create!(
      provider: "google_oauth2",
      email: "ops@example.com",
      access_token: "atk",
      refresh_token: "rtk",
      expires_at: 1.hour.from_now
    )
    @campaign = campaigns(:approved_campaign)
    @step_one = campaign_steps(:approved_step_one)
    @step_two = campaign_steps(:approved_step_two)
    @proposal = job_proposals(:in_users_org)
    # status:approved gates operator approval. pipeline_stage:in_campaign
    # is the canonical PRD-09 §9.2 check-2 condition for a job that has
    # been launched into a campaign — fixtures don't set it explicitly,
    # so plug it in here so the pre-send checklist passes.
    @proposal.update!(
      status: :approved,
      pipeline_stage: :in_campaign,
      customer_email: "alice@example.com",
      customer_house_number: "100",
      customer_street: "Oak Ridge"
    )
    @instance = CampaignInstance.create!(campaign: @campaign, host: @proposal, status: :active)

    # Per PRD-09 §1, customer email goes out from the originator's own Gmail.
    # The pre-send checklist's originator_mailbox check requires this — set
    # it up by default and let tests opt out (delete it, expire it) to
    # exercise the failure paths.
    @owner_delegation = EmailDelegation.create!(
      user: @proposal.owner,
      provider: "google_oauth2",
      email: "originator@example.com",
      access_token: "atk",
      refresh_token: "rtk",
      expires_at: 1.hour.from_now
    )

    # Existing tests assume mail goes out. The send gates require either
    # production OR TEST_TO_EMAIL set, so default tests to redirect-mode
    # and let gate-specific tests below opt out explicitly.
    @prior_test_to_email = ENV["TEST_TO_EMAIL"]
    ENV["TEST_TO_EMAIL"] = "redirect@test.example.com"
  end

  teardown do
    if @prior_test_to_email.nil?
      ENV.delete("TEST_TO_EMAIL")
    else
      ENV["TEST_TO_EMAIL"] = @prior_test_to_email
    end
  end

  test "skips a step when host JobProposal status is not approved" do
    @proposal.update!(status: :approving)
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "pending", step_instance.reload.email_delivery_status
    assert_empty GmailSender.deliveries
  end

  test "sends a due pending step and marks it sent (redirected to TEST_TO_EMAIL)" do
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    step_instance.reload
    assert_equal "sent", step_instance.email_delivery_status
    assert_equal @step_one.template_subject, step_instance.final_subject
    # final_body is template_body rendered through MailGenerator, which
    # also prepends a salutation and appends a signature block. Assert
    # the substituted body content appears between the wrappers; the
    # salutation/signature are verified by MailGenerator's own tests.
    assert_includes step_instance.final_body, @step_one.template_body,
      "final_body should contain the rendered template; got: #{step_instance.final_body.inspect}"

    assert_equal 1, GmailSender.deliveries.size
    delivery = GmailSender.deliveries.first
    assert_equal "redirect@test.example.com", delivery[:to]
    # From header is the originator's own Gmail (per PRD-09 §1) with their
    # display name attached when set — not the shared ApplicationMailbox.
    expected_from = @proposal.owner.full_name.present? ? %("#{@proposal.owner.full_name}" <originator@example.com>) : "originator@example.com"
    assert_equal expected_from, delivery[:from]
    assert_equal @step_one.template_subject, delivery[:subject]
  end

  test "From header carries the proposal owner's display name when set" do
    @proposal.owner.update!(first_name: "Mike", last_name: "Frizzell")
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "sent", step_instance.reload.email_delivery_status
    assert_equal 1, GmailSender.deliveries.size
    assert_equal %("Mike Frizzell" <originator@example.com>), GmailSender.deliveries.first[:from]
  end

  test "From email is the originator's Gmail, not the shared ApplicationMailbox" do
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "sent", step_instance.reload.email_delivery_status
    delivery = GmailSender.deliveries.first
    assert_includes delivery[:from], "originator@example.com",
      "campaign mail must be sent from the originator's own Gmail"
    refute_includes delivery[:from], "ops@example.com",
      "campaign mail must NOT be sent from the shared ApplicationMailbox"
  end

  test "in production with no TEST_TO_EMAIL, mail goes to the customer's address" do
    ENV.delete("TEST_TO_EMAIL")
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_production_environment(true) { CampaignSweepJob.new.perform }

    assert_equal "sent", step_instance.reload.email_delivery_status
    assert_equal 1, GmailSender.deliveries.size
    assert_equal "alice@example.com", GmailSender.deliveries.first[:to]
  end

  test "in production, the originator's Gmail is BCC'd on the customer send" do
    ENV.delete("TEST_TO_EMAIL")
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_production_environment(true) { CampaignSweepJob.new.perform }

    assert_equal "sent", step_instance.reload.email_delivery_status
    delivery = GmailSender.deliveries.first
    assert_equal "originator@example.com", delivery[:bcc],
      "the originator should receive a BCC copy of every customer send"
  end

  test "BCC is suppressed when TEST_TO_EMAIL is set so the originator's real inbox doesn't get the redirected mail" do
    # TEST_TO_EMAIL is set by the default setup. The redirect is for QA, so
    # leaking a copy to the originator's real Gmail would defeat the point.
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "sent", step_instance.reload.email_delivery_status
    delivery = GmailSender.deliveries.first
    assert_nil delivery[:bcc], "TEST_TO_EMAIL redirect must not leak a copy to the originator"
  end

  test "in development with no TEST_TO_EMAIL, the sweep is a no-op" do
    ENV.delete("TEST_TO_EMAIL")
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_production_environment(false) { CampaignSweepJob.new.perform }

    assert_equal "pending", step_instance.reload.email_delivery_status
    assert_empty GmailSender.deliveries
  end

  test "TEST_TO_EMAIL overrides the customer address in production too" do
    ENV["TEST_TO_EMAIL"] = "qa@test.example.com"
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_production_environment(true) { CampaignSweepJob.new.perform }

    assert_equal "sent", step_instance.reload.email_delivery_status
    assert_equal 1, GmailSender.deliveries.size
    assert_equal "qa@test.example.com", GmailSender.deliveries.first[:to]
  end

  test "skips steps whose planned_delivery_at is in the future" do
    step_instance = build_step_instance(@step_one, status: :pending, due: 10.minutes.from_now)

    CampaignSweepJob.new.perform

    assert_equal "pending", step_instance.reload.email_delivery_status
    assert_empty GmailSender.deliveries
  end

  test "skips steps whose campaign is not approved" do
    @campaign.update!(status: :paused, paused_by_user: users(:one), paused_at: Time.current)
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "pending", step_instance.reload.email_delivery_status
    assert_empty GmailSender.deliveries
  end

  test "skips steps whose campaign instance is not active" do
    @instance.update!(status: :paused)
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "pending", step_instance.reload.email_delivery_status
    assert_empty GmailSender.deliveries
  end

  test "marks campaign instance completed when its final step is sent" do
    sent_step = build_step_instance(@step_one, status: :sent, due: 2.hours.ago)
    sent_step.update!(final_subject: "x", final_body: "y")
    final_step = build_step_instance(@step_two, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "sent", final_step.reload.email_delivery_status
    assert_equal "completed", @instance.reload.status
  end

  test "leaves campaign instance active while later steps remain pending" do
    build_step_instance(@step_one, status: :pending, due: 1.minute.ago)
    build_step_instance(@step_two, status: :pending, due: 1.day.from_now)

    CampaignSweepJob.new.perform

    assert_equal "active", @instance.reload.status
  end

  test "marks step failed and stops instance when customer_email is missing in production" do
    ENV.delete("TEST_TO_EMAIL")
    @proposal.update!(customer_email: nil)
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_production_environment(true) { CampaignSweepJob.new.perform }

    assert_equal "failed", step_instance.reload.email_delivery_status
    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_empty GmailSender.deliveries
  end

  test "marks step failed and stops instance when final_subject is missing (legacy/un-approved row)" do
    step_instance = CampaignStepInstance.create!(
      campaign_instance: @instance,
      campaign_step: @step_one,
      planned_delivery_at: 1.minute.ago,
      email_delivery_status: :pending,
      final_subject: nil,
      final_body: nil
    )

    CampaignSweepJob.new.perform

    assert_equal "failed", step_instance.reload.email_delivery_status
    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_empty GmailSender.deliveries
  end

  test "marks step failed and stops instance when GmailSender returns nil" do
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_gmail_sender_returning(nil) do
      CampaignSweepJob.new.perform
    end

    assert_equal "failed", step_instance.reload.email_delivery_status
    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_not_nil @instance.reload.ended_at, "ended_at should be stamped when the instance is stopped"
  end

  test "a delivery failure flags the proposal so it surfaces in Needs Attention" do
    # Issue #239 — a synchronous send failure must drive the host proposal's
    # status_overlay to "delivery_issue", same as an async bounce, so it shows
    # up in the operator's "Needs Attention" filter on the proposals index.
    build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_gmail_sender_returning(nil) do
      CampaignSweepJob.new.perform
    end

    assert_equal "delivery_issue", @proposal.reload.status_overlay
    assert_includes JobProposal.needs_attention, @proposal
  end

  test "a checklist-blocked delivery (BLOCK_DELIVERY_ISSUE) also flags the proposal for Needs Attention" do
    # Suppression list hits the BLOCK_DELIVERY_ISSUE branch via claim_to_failed,
    # which is a separate code path from the synchronous send-failure case above.
    EmailSuppression.create!(
      location: @proposal.location,
      email: @proposal.customer_email,
      reason: "manual"
    )
    build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "delivery_issue", @proposal.reload.status_overlay
    assert_includes JobProposal.needs_attention, @proposal
  end

  test "persists gmail send response and thread snapshot on a successful send" do
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform
    step_instance.reload

    assert_equal "sent", step_instance.email_delivery_status
    assert step_instance.gmail_send_response.present?, "send response should be stored"
    assert step_instance.gmail_send_response["threadId"].present?, "send response should include threadId"
    assert_equal step_instance.gmail_send_response["threadId"], step_instance.gmail_thread_id
    assert step_instance.gmail_thread_snapshot.present?, "thread snapshot should be captured"
    assert_equal step_instance.gmail_thread_id, step_instance.gmail_thread_snapshot["id"]
  end

  test "stamps ended_at when the final step completes the campaign instance" do
    sent_step = build_step_instance(@step_one, status: :sent, due: 2.hours.ago)
    sent_step.update!(final_subject: "x", final_body: "y")
    final_step = build_step_instance(@step_two, status: :pending, due: 1.minute.ago)

    freeze_time = Time.current
    travel_to(freeze_time) { CampaignSweepJob.new.perform }

    @instance.reload
    assert_equal "sent", final_step.reload.email_delivery_status
    assert_equal "completed", @instance.status
    assert_in_delta freeze_time, @instance.ended_at, 1.second
  end

  test "first step attaches PDF attachments from the proposal" do
    attach_pdf!(@proposal, filename: "proposal.pdf")
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "sent", step_instance.reload.email_delivery_status
    delivery = GmailSender.deliveries.first
    assert_equal 1, delivery[:attachments].size
    assert_equal "proposal.pdf", delivery[:attachments].first[:filename]
    assert_equal "application/pdf", delivery[:attachments].first[:mime_type]
  end

  test "later steps do not attach the proposal PDF" do
    attach_pdf!(@proposal, filename: "proposal.pdf")
    sent_step_one = build_step_instance(@step_one, status: :sent, due: 2.hours.ago)
    sent_step_one.update!(final_subject: "x", final_body: "y")
    final_step = build_step_instance(@step_two, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "sent", final_step.reload.email_delivery_status
    delivery = GmailSender.deliveries.first
    assert_equal [], delivery[:attachments], "step two should not carry the proposal PDF"
  end

  test "non-PDF attachments are not sent on the first email" do
    image = @proposal.attachments.build(uploaded_by_user: users(:one))
    image.file.attach(io: StringIO.new("\x89PNG fake"), filename: "ceiling.png", content_type: "image/png")
    image.save!
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "sent", step_instance.reload.email_delivery_status
    assert_equal [], GmailSender.deliveries.first[:attachments]
  end

  test "FAKE-SEND mode does not populate gmail_send_response or thread snapshot" do
    @mailbox.destroy!
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)
    ENV.delete("TEST_TO_EMAIL")

    with_production_environment(false) { CampaignSweepJob.new.perform }

    step_instance.reload
    assert_equal "sent", step_instance.email_delivery_status
    assert_nil step_instance.gmail_send_response
    assert_nil step_instance.gmail_thread_id
    assert_nil step_instance.gmail_thread_snapshot
  end

  test "in production, a missing originator Gmail surfaces a delivery issue on the step" do
    # Per PRD-09 §10.1 a disconnected originator Gmail is a delivery_issue,
    # not a silent skip. The checklist's originator-mailbox check fires
    # first; the step is marked failed and the campaign run is stopped.
    @owner_delegation.destroy!
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    with_production_environment(true) { CampaignSweepJob.new.perform }

    assert_equal "failed", step_instance.reload.email_delivery_status
    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_empty GmailSender.deliveries
  end

  test "in development with no mailbox, runs in FAKE-SEND mode and progresses the step" do
    @mailbox.destroy!
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)
    # No TEST_TO_EMAIL set in this test path so we use the real customer
    # email as the fake recipient — exercises the resolution logic.
    ENV.delete("TEST_TO_EMAIL")

    with_production_environment(false) { CampaignSweepJob.new.perform }

    assert_equal "sent", step_instance.reload.email_delivery_status
    assert_equal @step_one.template_subject, step_instance.final_subject
    # final_body is template_body rendered through MailGenerator, which
    # also prepends a salutation and appends a signature block. Assert
    # the substituted body content appears between the wrappers; the
    # salutation/signature are verified by MailGenerator's own tests.
    assert_includes step_instance.final_body, @step_one.template_body,
      "final_body should contain the rendered template; got: #{step_instance.final_body.inspect}"
    # Crucially: no real GmailSender call happened. The dev fake-send
    # path bypasses the sender entirely.
    assert_empty GmailSender.deliveries
  end

  test "in development, routes campaign step sends through Action Mailer (letter_opener path) and never calls GmailSender" do
    # A connected mailbox is intentionally still around — dev mode has to
    # win regardless, so we can't accidentally relay through real Gmail
    # while developing.
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)
    ENV.delete("TEST_TO_EMAIL")
    ActionMailer::Base.deliveries.clear

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      with_development_environment(true) { CampaignSweepJob.new.perform }
    end
    assert_empty GmailSender.deliveries, "dev path must not call GmailSender"

    step_instance.reload
    assert_equal "sent", step_instance.email_delivery_status

    delivery = ActionMailer::Base.deliveries.last
    assert_equal [@proposal.customer_email], delivery.to
    assert_equal @step_one.template_subject, delivery.subject
    # No Gmail metadata captured — the dev path skips persist_send_metadata.
    assert_nil step_instance.gmail_send_response
    assert_nil step_instance.gmail_thread_id
  end

  test "skips a step silently when the proposal has a status_overlay set" do
    @proposal.update!(status_overlay: "paused")
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "pending", step_instance.reload.email_delivery_status, "block_silent should leave the step pending"
    assert_equal "active", @instance.reload.status, "block_silent should not stop the campaign run"
    assert_empty GmailSender.deliveries
  end

  test "marks step failed and stops instance when the recipient is on the suppression list" do
    EmailSuppression.create!(
      location: @proposal.location,
      email: @proposal.customer_email,
      reason: "manual"
    )
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "failed", step_instance.reload.email_delivery_status
    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_empty GmailSender.deliveries
  end

  test "marks step failed and stops instance when the customer email is malformed" do
    @proposal.update!(customer_email: "not-an-email")
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform

    assert_equal "failed", step_instance.reload.email_delivery_status
    assert_equal "stopped_on_delivery_issue", @instance.reload.status
    assert_empty GmailSender.deliveries
  end

  test "claim is idempotent across overlapping sweeps" do
    step_instance = build_step_instance(@step_one, status: :pending, due: 1.minute.ago)

    CampaignSweepJob.new.perform
    CampaignSweepJob.new.perform

    assert_equal "sent", step_instance.reload.email_delivery_status
    assert_equal 1, GmailSender.deliveries.size
  end

  private

  def build_step_instance(step, status:, due:)
    # Post-approve, every step instance carries its final_subject /
    # final_body — content is locked in at approve time and the sweep
    # ships that frozen copy. Render here via MailGenerator so each
    # test starts with a realistic post-approve row.
    rendered = MailGenerator.render(campaign_step: step, job_proposal: @proposal)
    CampaignStepInstance.create!(
      campaign_instance: @instance,
      campaign_step: step,
      planned_delivery_at: due,
      email_delivery_status: status,
      final_subject: rendered.subject,
      final_body: rendered.body
    )
  end

  def attach_pdf!(proposal, filename:)
    att = proposal.attachments.build(uploaded_by_user: users(:one))
    att.file.attach(
      io: StringIO.new("%PDF-1.4 fake content"),
      filename: filename,
      content_type: "application/pdf"
    )
    att.save!
    att
  end

  def with_gmail_sender_returning(value)
    original = GmailSender.instance_method(:send_email)
    GmailSender.define_method(:send_email) { |to:, subject:, body:, from_name: nil, attachments: [], bcc: nil| value }
    yield
  ensure
    GmailSender.define_method(:send_email, original)
  end

  def with_production_environment(value)
    original = CampaignSweepJob.singleton_method(:production_environment?)
    CampaignSweepJob.define_singleton_method(:production_environment?) { value }
    yield
  ensure
    CampaignSweepJob.define_singleton_method(:production_environment?, original)
  end

  def with_development_environment(value)
    original = CampaignSweepJob.singleton_method(:development_environment?)
    CampaignSweepJob.define_singleton_method(:development_environment?) { value }
    yield
  ensure
    CampaignSweepJob.define_singleton_method(:development_environment?, original)
  end
end
