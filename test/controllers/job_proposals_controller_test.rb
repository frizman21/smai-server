require "test_helper"

class JobProposalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)               # tenant: one
    @other_tenant_user = users(:two)  # tenant: two
    @admin = users(:admin)            # is_admin
  end

  test "redirects to sign-in when not signed in" do
    get job_proposals_url
    assert_redirected_to new_user_session_path
  end

  test "user sees all proposals in their tenant" do
    sign_in @user
    get job_proposals_url
    assert_response :success
    assert_match "Alice", response.body  # in_users_org: tenant=one ✓
    assert_match "Bob", response.body    # same_tenant_other_org: tenant=one ✓
  end

  test "user does not see proposals from other tenants" do
    sign_in @user
    get job_proposals_url
    assert_response :success
    assert_no_match "Carol", response.body  # other_tenant: tenant=two ✗
  end

  test "user from another tenant only sees their own tenant's proposals" do
    sign_in @other_tenant_user
    get job_proposals_url
    assert_response :success
    assert_match "Carol", response.body
    assert_no_match "Alice", response.body
    assert_no_match "Bob", response.body
  end

  test "user with no tenant sees empty state" do
    orphan = User.create!(email: "orphan-jp@example.com", password: "Password1")
    sign_in orphan
    get job_proposals_url
    assert_response :success
    assert_no_match "Alice", response.body
    assert_no_match "Bob", response.body
    assert_no_match "Carol", response.body
    assert_match "No job proposals match these filters.", response.body
  end

  test "admin sees all proposals across tenants" do
    sign_in @admin
    get job_proposals_url
    assert_response :success
    assert_match "Alice", response.body
    assert_match "Bob", response.body
    assert_match "Carol", response.body
  end

  test "status filter narrows the list to that status" do
    sign_in @admin
    get job_proposals_url, params: { status: "approving" }
    assert_response :success
    # Fixtures: in_users_org=drafting(0), same_tenant_other_org=approving(1), other_tenant=drafting(0)
    assert_match "Bob", response.body
    assert_no_match "Alice", response.body
    assert_no_match "Carol", response.body
  end

  test "owner filter narrows the list to proposals owned by that user" do
    sign_in @admin
    get job_proposals_url, params: { owner_id: users(:two).id }
    assert_response :success
    assert_match "Carol", response.body                # other_tenant: owner=two
    assert_no_match "Alice", response.body             # in_users_org: owner=one
    assert_no_match "Bob", response.body               # same_tenant_other_org: owner=one
  end

  test "creator filter narrows the list to proposals created by that user" do
    sign_in @admin
    get job_proposals_url, params: { creator_id: users(:one).id }
    assert_response :success
    assert_match "Alice", response.body
    assert_match "Bob", response.body
    assert_no_match "Carol", response.body
  end

  test "needs_attention filter narrows the list to proposals operator must act on" do
    # Fixtures: in_users_org=drafting(Alice), same_tenant_other_org=approving(Bob),
    # other_tenant=drafting(Carol). All three are inherently needs-attention because
    # of their statuses. Move Alice out of attention to verify the filter excludes her.
    job_proposals(:in_users_org).update!(
      status: :approved,
      pipeline_stage: :in_campaign,
      status_overlay: nil,
      customer_email: "alice@example.com",
      customer_house_number: "1",
      customer_street: "Oak"
    )

    sign_in @admin
    get job_proposals_url, params: { filter: "needs_attention" }
    assert_response :success
    assert_match "Bob", response.body                  # status=approving — included
    assert_match "Carol", response.body                # status=drafting — included
    assert_no_match "Alice", response.body             # approved + no overlay — excluded
  end

  test "filters compose with each other" do
    sign_in @admin
    get job_proposals_url, params: { status: "drafting", owner_id: users(:one).id }
    assert_response :success
    assert_match "Alice", response.body                # status=drafting + owner=one
    assert_no_match "Bob", response.body               # status=approving
    assert_no_match "Carol", response.body             # owner=two
  end

  test "new renders the upload form" do
    sign_in @user
    get new_job_proposal_url
    assert_response :success
    assert_select "form#job-upload-form"
    assert_select "input[type='file'][name='file']"
    assert_match(/Drop a file here/i, response.body)
  end

  test "create with no file re-renders the form with an error" do
    sign_in @user
    assert_no_difference "JobProposal.count" do
      post job_proposals_url, params: {}
    end
    assert_response :unprocessable_content
    assert_match(/Please choose a file/i, response.body)
  end

  test "create persists a proposal with the uploaded file as an attachment" do
    sign_in @user
    file = Rack::Test::UploadedFile.new(StringIO.new("hello world"), "text/plain", original_filename: "proposal.txt")

    assert_difference "JobProposal.count", 1 do
      post job_proposals_url, params: { file: file }
    end
    proposal = JobProposal.order(:created_at).last
    assert_redirected_to edit_job_proposal_path(proposal)
    assert_match(/Confirm the details/i, flash[:notice])
    assert_equal @user, proposal.owner
    assert_equal @user, proposal.created_by_user
    assert_equal @user.tenant, proposal.tenant
    assert_equal 1, proposal.attachments.count
    assert proposal.attachments.first.file.attached?
    assert_equal "proposal.txt", proposal.attachments.first.file.filename.to_s

    # Without AI credentials (Rails.env.test? short-circuits the processor),
    # the stub fills in the customer fields.
    assert_equal "Sample", proposal.customer_first_name
    assert_equal "Customer", proposal.customer_last_name
    assert_equal 10260.00, proposal.proposal_value.to_f
    assert proposal.internal_reference.to_s.start_with?("STUB-")
  end

  test "create fails when user has no tenant" do
    orphan = User.create!(email: "orphan-jp-create@example.com", password: "Password1")
    sign_in orphan
    file = Rack::Test::UploadedFile.new(StringIO.new("x"), "text/plain", original_filename: "x.txt")

    assert_no_difference "JobProposal.count" do
      post job_proposals_url, params: { file: file }
    end
    assert_response :unprocessable_content
    assert_match(/tenant/i, response.body)
  end

  # --- soft delete ---

  test "destroy refuses location-scoped tenant users and leaves the row alone" do
    location_user = User.create!(
      email: "loc@example.com", password: "Password1", is_pending: false,
      tenant: tenants(:one), location: locations(:ne_dallas)
    )
    sign_in location_user
    jp = job_proposals(:in_users_org)

    delete job_proposal_url(jp)
    assert_redirected_to root_path
    refute jp.reload.discarded?
  end

  test "destroy refuses a tenant admin acting on another tenant's proposal" do
    sign_in @user  # tenant: one, no location → tenant admin of tenant one
    jp = job_proposals(:other_tenant)  # tenant: two

    delete job_proposal_url(jp)
    refute jp.reload.discarded?
  end

  test "destroy soft-deletes when called by a tenant admin in the same tenant" do
    sign_in @user  # tenant: one, no location → tenant admin of tenant one
    jp = job_proposals(:in_users_org)

    delete job_proposal_url(jp)
    assert_redirected_to job_proposals_path
    assert_match(/trash/i, flash[:notice])
    assert jp.reload.discarded?
  end

  test "destroy soft-deletes when called by an admin, hides the row from kept queries" do
    sign_in @admin
    jp = job_proposals(:in_users_org)

    delete job_proposal_url(jp)
    assert_redirected_to job_proposals_path
    assert_match(/trash/i, flash[:notice])
    assert jp.reload.discarded?
    refute JobProposal.exists?(jp.id), "kept scope should hide the discarded proposal"
    assert JobProposal.with_discarded.exists?(jp.id)
  end

  test "destroy refuses while an active CampaignInstance is on the proposal" do
    sign_in @admin
    jp = job_proposals(:in_users_org)
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)

    delete job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    assert_match(/active campaign/i, flash[:alert])
    refute jp.reload.discarded?
  end

  test "destroy allows deletion while a drafting CampaignInstance is on the proposal" do
    sign_in @admin
    jp = job_proposals(:in_users_org)
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :drafting)

    delete job_proposal_url(jp)
    assert_redirected_to job_proposals_path
    assert jp.reload.discarded?, "drafting (Review Campaign) instance must not block delete"
  end

  test "restore is admin-only and brings a discarded proposal back" do
    jp = job_proposals(:in_users_org)
    jp.discard
    assert jp.reload.discarded?

    sign_in @user
    patch restore_job_proposal_url(jp)
    assert_redirected_to root_path
    assert jp.reload.discarded?, "non-admins must not be able to restore"

    sign_in @admin
    patch restore_job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    refute jp.reload.discarded?
  end

  test "discarded proposals do not appear on the index" do
    sign_in @admin
    jp = job_proposals(:in_users_org)
    jp.discard

    get job_proposals_url
    assert_response :success
    assert_no_match "Alice", response.body
  end

  # --- show action ---

  test "index links the address column to the show page" do
    sign_in @user
    @jp = job_proposals(:in_users_org)
    @jp.update!(customer_house_number: "1247", customer_street: "Oak Ridge Drive")
    get job_proposals_url
    assert_response :success
    # Each card body wraps its content in a link to the show page; the
    # address renders inside the link, so the address text appears within
    # an anchor pointing at the proposal.
    assert_select "a[href=?]", job_proposal_path(@jp) do
      assert_select "*", text: /1247 Oak Ridge Drive/
    end
  end

  test "show renders for a proposal the user can access" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(customer_house_number: "1247", customer_street: "Oak Ridge Drive")
    get job_proposal_url(jp)
    assert_response :success
    assert_match "1247 Oak Ridge Drive", response.body
    assert_match "Alice", response.body
  end

  test "show offers a Resume campaign button when the campaign stopped on a customer reply" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "in_campaign", status_overlay: "customer_waiting")
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :stopped_on_reply)

    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?][method=post]", resume_job_proposal_path(jp) do
      assert_select "input[name='_method'][value=patch]"
    end
    assert_match(/Resume campaign/i, response.body)
  end

  test "show returns 404 for a proposal outside the user's scope (no info leak)" do
    sign_in @user
    other_jp = job_proposals(:other_tenant)
    get job_proposal_url(other_jp)
    assert_response :not_found
  end

  test "show returns 404 for a missing proposal" do
    sign_in @user
    get job_proposal_url(id: 0)
    assert_response :not_found
  end

  test "show renders the customer's email in the Customer section as a mailto link" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(customer_email: "alice@example.com")

    get job_proposal_url(jp)
    assert_response :success
    assert_select "a[href=?]", "mailto:alice@example.com", text: "alice@example.com"
  end

  test "show falls back to a Job Proposal #N heading when address is missing" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(customer_house_number: nil, customer_street: nil)
    get job_proposal_url(jp)
    assert_response :success
    assert_match "Job Proposal ##{jp.id}", response.body
  end

  test "show step table includes a Thread column linking to the Gmail conversation when present" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    si_with_thread = CampaignStepInstance.create!(
      campaign_instance: instance, campaign_step: campaign_steps(:approved_step_one),
      planned_delivery_at: 1.hour.ago, email_delivery_status: :sent,
      gmail_thread_id: "THREAD-ABC", final_subject: "x", final_body: "y"
    )
    si_no_thread = CampaignStepInstance.create!(
      campaign_instance: instance, campaign_step: campaign_steps(:approved_step_two),
      planned_delivery_at: 1.hour.from_now, email_delivery_status: :pending
    )

    get job_proposal_url(jp)
    assert_response :success
    assert_select "thead th", text: "Thread"
    # Sent step has a link to the Gmail thread URL, opens in a new tab.
    assert_select "a[href*=?][target=_blank]", "THREAD-ABC", text: /Open/
    # Pending step has no thread id → em-dash placeholder, no Gmail link.
    refute_match si_no_thread.id.to_s + "[^\"]*Open", response.body
  end

  # --- pre-send checklist card ---

  test "show renders the pre-send checklist for a proposal with a pending campaign step" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approved, pipeline_stage: :in_campaign, customer_email: "alice@example.com")
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    CampaignStepInstance.create!(
      campaign_instance: instance, campaign_step: campaign_steps(:approved_step_one),
      planned_delivery_at: 1.hour.from_now, email_delivery_status: :pending,
      final_subject: "ready", final_body: "hi"
    )

    get job_proposal_url(jp)
    assert_response :success
    assert_select "h2", text: "Pre-send checklist"
    # The apostrophe in "Originator's Gmail connected" gets HTML-escaped in
    # the rendered page, so match with a regex that doesn't care.
    assert_match(/Originator(['&#39;]+s)? Gmail connected/, response.body)
    assert_match "Recipient email present and valid", response.body
    assert_match "Recipient is not on the suppression list", response.body
  end

  test "show flags 'Action needed' when a delivery-issue check fails" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approved, pipeline_stage: :in_campaign, customer_email: nil)
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    CampaignStepInstance.create!(
      campaign_instance: instance, campaign_step: campaign_steps(:approved_step_one),
      planned_delivery_at: 1.hour.from_now, email_delivery_status: :pending,
      final_subject: "x", final_body: "y"
    )

    get job_proposal_url(jp)
    assert_response :success
    assert_match "Action needed", response.body
    assert_match "customer email field is blank", response.body
  end

  test "show hides the pre-send checklist when there is no pending campaign step" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    # No CampaignInstance at all.

    get job_proposal_url(jp)
    assert_response :success
    assert_no_match "Pre-send checklist", response.body
  end

  # --- sort ---

  test "default sort is created_at desc" do
    sign_in @admin
    get job_proposals_url
    assert_response :success
    # admin sees three fixture rows: created_at order is fixture-load order; assert presence
    assert_match "Alice", response.body
    assert_match "Bob", response.body
    assert_match "Carol", response.body
  end

  test "sort by proposal_value asc orders cheapest first" do
    sign_in @admin
    get job_proposals_url, params: { sort: "proposal_value", dir: "asc" }
    assert_response :success
    # Carol(5000) < Bob(8000) < Alice(12500): assert Carol appears before Alice
    assert_operator response.body.index("Carol"), :<, response.body.index("Alice")
  end

  test "sort by proposal_value desc orders priciest first" do
    sign_in @admin
    get job_proposals_url, params: { sort: "proposal_value", dir: "desc" }
    assert_response :success
    assert_operator response.body.index("Alice"), :<, response.body.index("Carol")
  end

  test "invalid sort columns silently fall back to default" do
    sign_in @admin
    get job_proposals_url, params: { sort: "customer_email" }
    assert_response :success
  end

  test "invalid sort direction silently falls back to desc" do
    sign_in @admin
    get job_proposals_url, params: { sort: "proposal_value", dir: "sideways" }
    assert_response :success
    assert_operator response.body.index("Alice"), :<, response.body.index("Carol")
  end

  # --- search ---

  test "search filters by customer first name" do
    sign_in @admin
    get job_proposals_url, params: { q: "Alic" }
    assert_response :success
    assert_match "Alice", response.body
    assert_no_match "Bob", response.body
    assert_no_match "Carol", response.body
  end

  test "search is case-insensitive" do
    sign_in @admin
    get job_proposals_url, params: { q: "alice" }
    assert_response :success
    assert_match "Alice", response.body
  end

  test "search across address fields" do
    sign_in @admin
    jp = job_proposals(:in_users_org)
    jp.update!(customer_city: "Madison")
    get job_proposals_url, params: { q: "Madison" }
    assert_match "Alice", response.body
  end

  test "search uses parameterized SQL (no injection)" do
    sign_in @admin
    get job_proposals_url, params: { q: "'; DROP TABLE job_proposals; --" }
    assert_response :success
  end

  test "search preserves filters across submits via query params" do
    sign_in @admin
    get job_proposals_url, params: { q: "alice", status: "drafting" }
    assert_response :success
    assert_match "Alice", response.body
  end

  # --- location-based scoping ---------------------------------------------

  test "regular tenant user only sees proposals at their location" do
    # users(:one) is tenant: one with no location set in the fixture
    location_a = locations(:ne_dallas)  # tenant: one
    location_b = tenants(:one).locations.create!(
      display_name: "South Dallas", address_line_1: "5 Side", city: "Dallas",
      state: "TX", postal_code: "75002", phone_number: "(214) 555-0202", is_active: true
    )
    job_proposals(:in_users_org).update!(location: location_a, customer_first_name: "Alice")
    job_proposals(:same_tenant_other_org).update!(location: location_b, customer_first_name: "Bob")

    @user.update!(location: location_a)
    sign_in @user
    get job_proposals_url
    assert_response :success
    assert_match "Alice", response.body
    assert_no_match "Bob", response.body
  end

  test "regular tenant user cannot bypass the location filter via params" do
    location_a = locations(:ne_dallas)
    location_b = tenants(:one).locations.create!(
      display_name: "South Dallas", address_line_1: "5 Side", city: "Dallas",
      state: "TX", postal_code: "75002", phone_number: "(214) 555-0202", is_active: true
    )
    job_proposals(:in_users_org).update!(location: location_a, customer_first_name: "Alice")
    job_proposals(:same_tenant_other_org).update!(location: location_b, customer_first_name: "Bob")

    @user.update!(location: location_a)
    sign_in @user
    get job_proposals_url, params: { location_id: location_b.id }
    assert_response :success
    assert_match "Alice", response.body
    assert_no_match "Bob", response.body
  end

  test "tenant admin sees the location label on each card and can filter by location" do
    location_a = locations(:ne_dallas)
    location_b = tenants(:one).locations.create!(
      display_name: "South Dallas", address_line_1: "5 Side", city: "Dallas",
      state: "TX", postal_code: "75002", phone_number: "(214) 555-0202", is_active: true
    )
    job_proposals(:in_users_org).update!(location: location_a, customer_first_name: "Alice")
    job_proposals(:same_tenant_other_org).update!(location: location_b, customer_first_name: "Bob")

    tenant_admin = User.create!(email: "ta@example.com", password: "Password1", is_pending: false, tenant: tenants(:one))
    sign_in tenant_admin

    get job_proposals_url
    assert_response :success
    assert_select "select[name=location_id]"
    assert_match location_a.display_name, response.body
    assert_match location_b.display_name, response.body
    assert_match "Alice", response.body
    assert_match "Bob", response.body

    get job_proposals_url, params: { location_id: location_a.id }
    assert_response :success
    assert_match "Alice", response.body
    assert_no_match "Bob", response.body
  end

  test "regular tenant user does not see the Location column or filter" do
    @user.update!(location: locations(:ne_dallas))
    sign_in @user
    get job_proposals_url
    assert_response :success
    assert_select "th", text: "Location", count: 0
    assert_select "select[name=location_id]", count: 0
  end

  test "regular tenant user sees their location name near the H1" do
    @user.update!(location: locations(:ne_dallas))
    sign_in @user
    get job_proposals_url
    assert_response :success
    assert_select "h1", text: /Jobs/
    assert_match "at #{locations(:ne_dallas).display_name}", response.body
  end

  test "filter form preserves the needs_attention filter across submits" do
    sign_in @admin
    get job_proposals_url, params: { filter: "needs_attention" }
    assert_select "input[type=hidden][name=filter][value=?]", "needs_attention"
  end

  test "needs_attention filter renders the Jobs Requiring Attention header" do
    sign_in @admin
    get job_proposals_url, params: { filter: "needs_attention" }
    assert_response :success
    assert_select "h1", text: "Jobs Requiring Attention"
  end

  # --- edit / update ---

  test "edit redirects to sign-in when not signed in" do
    get edit_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  test "edit returns 404 for a proposal outside the user's scope" do
    sign_in @user
    get edit_job_proposal_url(job_proposals(:other_tenant))
    assert_response :not_found
  end

  test "edit renders the form with editable fields when no campaign is in flight" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?][method=post]", job_proposal_path(jp)
    assert_select "input[name='job_proposal[customer_first_name]']:not([disabled])"
    assert_select "select[name='job_proposal[scenario_id]']:not([disabled])"
    # Drafting fixture → submit reads "Approve Proposal Content" (the act of
    # approving the proposal content kicks off the campaign instance).
    assert_select "input[type=submit][value='Approve Proposal Content']"
    assert_no_match(/in process/i, response.body)
  end

  test "edit renders the proposal's location as a disabled field for regular users" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(location: locations(:ne_dallas))
    @user.update!(location: locations(:ne_dallas))   # make @user a regular tenant user
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_select "input[name=proposal_location][disabled][value=?]", locations(:ne_dallas).display_name
    assert_select "select[name='job_proposal[location_id]']", count: 0
  end

  test "regular user update ignores location_id (location is not editable for them)" do
    sign_in @user
    @user.update!(location: locations(:ne_dallas))   # regular user
    jp = job_proposals(:in_users_org)
    original_location = locations(:ne_dallas)
    jp.update!(location: original_location)

    other = tenants(:one).locations.create!(
      display_name: "Other", address_line_1: "9 Elsewhere", city: "Plano",
      state: "TX", postal_code: "75024", phone_number: "(214) 555-0303", is_active: true
    )

    patch job_proposal_url(jp), params: { job_proposal: { location_id: other.id, customer_first_name: "Edited" } }
    assert_equal original_location, jp.reload.location
    assert_equal "Edited", jp.customer_first_name
  end

  test "edit renders a Location select for account admins" do
    tenant_admin = User.create!(email: "ta-edit@example.com", password: "Password1", is_pending: false, tenant: tenants(:one))
    sign_in tenant_admin
    jp = job_proposals(:in_users_org)
    jp.update!(location: locations(:ne_dallas))
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_select "select[name='job_proposal[location_id]']"
    assert_select "input[name=proposal_location][disabled]", count: 0
  end

  test "account admin can reassign the proposal's location" do
    tenant_admin = User.create!(email: "ta-update@example.com", password: "Password1", is_pending: false, tenant: tenants(:one))
    sign_in tenant_admin
    jp = job_proposals(:in_users_org)
    jp.update!(location: locations(:ne_dallas))
    other = tenants(:one).locations.create!(
      display_name: "South Dallas", address_line_1: "9 Side", city: "Dallas",
      state: "TX", postal_code: "75002", phone_number: "(214) 555-0303", is_active: true
    )

    patch job_proposal_url(jp), params: { job_proposal: { location_id: other.id, customer_first_name: "Edited" } }
    assert_equal other, jp.reload.location
    assert_equal "Edited", jp.customer_first_name
  end

  test "account admin cannot reassign to a location in another tenant" do
    tenant_admin = User.create!(email: "ta-cross@example.com", password: "Password1", is_pending: false, tenant: tenants(:one))
    sign_in tenant_admin
    jp = job_proposals(:in_users_org)
    original = locations(:ne_dallas)
    jp.update!(location: original)
    foreign_tenant = Tenant.create!(name: "ForeignCo")
    foreign_location = foreign_tenant.locations.create!(
      display_name: "Foreign", address_line_1: "1 Foreign", city: "Reno",
      state: "NV", postal_code: "89501", phone_number: "(775) 555-0303", is_active: true
    )

    patch job_proposal_url(jp), params: { job_proposal: { location_id: foreign_location.id, customer_first_name: "Edited" } }
    assert_equal original, jp.reload.location
  end

  test "edit hides the Loss notes section while the proposal is still drafting" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :drafting)
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_no_match(/Loss notes/, response.body)
    assert_select "select[name='job_proposal[loss_reason_id]']", count: 0
  end

  test "edit shows the Loss notes section once the proposal is past drafting" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approving)
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_match(/Loss notes/, response.body)
    assert_select "select[name='job_proposal[loss_reason_id]']"
  end

  test "edit job_type select only includes job types this tenant has activated" do
    sign_in @user
    jp = job_proposals(:in_users_org) # tenants(:one): activates job_types(:one) only
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_select "select[name='job_proposal[job_type_id]'] option[value='#{job_types(:one).id}']"
    assert_select "select[name='job_proposal[job_type_id]'] option[value='#{job_types(:two).id}']", count: 0
  end

  test "edit scenario select only includes scenarios this tenant has activated, with data-job-type-id" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_select "select[name='job_proposal[scenario_id]'] option[value='#{scenarios(:sewage_backup).id}'][data-job-type-id='#{scenarios(:sewage_backup).job_type_id}']"
    # clean_water scenario isn't activated for tenant one — must be omitted
    assert_select "select[name='job_proposal[scenario_id]'] option[value='#{scenarios(:clean_water).id}']", count: 0
  end

  test "edit renders read-only with a warning when a campaign instance exists" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    get edit_job_proposal_url(jp)
    assert_response :success
    assert_match(/in process/i, response.body)
    assert_select "input[name='job_proposal[customer_first_name]'][disabled]"
    assert_select "input[type=submit][value='Approve Proposal Content']", count: 0
    assert_select "input[type=submit][value=Save]", count: 0
  end

  test "update redirects to sign-in when not signed in" do
    patch job_proposal_url(job_proposals(:in_users_org)), params: { job_proposal: { customer_first_name: "X" } }
    assert_redirected_to new_user_session_path
  end

  test "update returns 404 for a proposal outside the user's scope" do
    sign_in @user
    patch job_proposal_url(job_proposals(:other_tenant)),
          params: { job_proposal: { customer_first_name: "X" } }
    assert_response :not_found
  end

  test "update saves editable fields and launches a campaign when scenario is set" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    other_owner = User.create!(email: "assistant@example.com", password: "Password1", tenant: jp.tenant)

    assert_difference "CampaignInstance.count", 1 do
      assert_difference "CampaignStepInstance.count", 2 do  # approved_campaign has 2 steps
        patch job_proposal_url(jp), params: { job_proposal: {
          customer_first_name: "Edited",
          customer_email: "edited@example.com",
          customer_house_number: "100",
          customer_street: "Test Street",
          loss_reason_id: loss_reasons(:price_too_high).id,
          loss_notes: "Customer chose competitor.",
          internal_reference: "REF-123",
          owner_id: other_owner.id,
          job_type_id: job_types(:one).id,
          scenario_id: scenarios(:sewage_backup).id,
          proposal_value: 13_500.50
        } }
      end
    end

    instance = jp.reload.campaign_instances.first
    assert_redirected_to job_proposal_campaign_instance_path(jp, instance)
    assert_match(/Campaign created/i, flash[:notice])
    assert_equal "approving", jp.status

    assert_equal "Edited", jp.customer_first_name
    assert_equal "edited@example.com", jp.customer_email
    assert_equal loss_reasons(:price_too_high), jp.loss_reason
    assert_equal "Customer chose competitor.", jp.loss_notes
    assert_equal "REF-123", jp.internal_reference
    assert_equal other_owner, jp.owner
    assert_equal scenarios(:sewage_backup), jp.scenario
    assert_equal 13_500.50, jp.proposal_value.to_f

    instance = jp.campaign_instances.first
    assert_equal campaigns(:approved_campaign), instance.campaign
    # Freshly-launched instances are in :drafting; approve transitions them
    # to :active. See CampaignInstance enum doc.
    assert instance.status_drafting?
    # planned_delivery_at is set by approve, not by launch (per PRD-03 §6.4
    # — timing anchored to operator approval, not save).
    assert_nil instance.started_at
    instance.step_instances.each do |si|
      assert si.email_delivery_status_pending?
      assert_nil si.final_subject
      assert_nil si.final_body
      assert_nil si.planned_delivery_at
    end
  end

  test "update without a scenario saves but does not launch — flash lists the gaps" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    assert_no_difference "CampaignInstance.count" do
      patch job_proposal_url(jp), params: { job_proposal: { customer_first_name: "Edited" } }
    end
    assert_redirected_to job_proposal_path(jp)
    assert_match(/missing/i, flash[:notice])
    assert_match(/scenario_id/, flash[:notice])
    assert_equal "Edited", jp.reload.customer_first_name
  end

  test "update is idempotent — does not create a second campaign instance" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(scenario: scenarios(:sewage_backup))
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)

    assert_no_difference "CampaignInstance.count" do
      patch job_proposal_url(jp), params: { job_proposal: { customer_first_name: "Edited" } }
    end
    # Locked path: rejected with 422, original value unchanged.
    assert_response :unprocessable_content
    assert_equal "Alice", jp.reload.customer_first_name
  end

  test "update is rejected when a campaign is in flight" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)

    patch job_proposal_url(jp), params: { job_proposal: { customer_first_name: "ShouldNotSave" } }
    assert_response :unprocessable_content
    assert_match(/in flight/i, response.body)
    assert_equal "Alice", jp.reload.customer_first_name
  end

  # --- resume ---

  test "resume redirects to sign-in when not signed in" do
    patch resume_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  test "resume returns 404 for a proposal outside the user's scope" do
    sign_in @user
    patch resume_job_proposal_url(job_proposals(:other_tenant))
    assert_response :not_found
  end

  test "resume flips the paused instance back to active and clears the overlay" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "in_campaign", status_overlay: "paused")
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :paused)

    patch resume_job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    assert_match(/Campaign resumed/i, flash[:notice])

    assert instance.reload.status_active?
    assert_nil jp.reload.status_overlay
  end

  test "resume is a no-op alert when no campaign is paused" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)

    patch resume_job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    assert_match(/isn't paused/i, flash[:alert])
  end

  test "resume flips a campaign stopped on a customer reply back to active and clears the overlay" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "in_campaign", status_overlay: "customer_waiting")
    instance = CampaignInstance.create!(
      host: jp, campaign: campaigns(:approved_campaign),
      status: :stopped_on_reply, ended_at: 1.day.ago
    )

    patch resume_job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    assert_match(/Campaign resumed/i, flash[:notice])

    instance.reload
    assert instance.status_active?
    assert_nil instance.ended_at, "ended_at is cleared so the reply poller treats it as live again"
    assert_nil jp.reload.status_overlay
  end

  test "resume folds the recorded customer reply into the step snapshot so the poller won't re-stop" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "in_campaign", status_overlay: "customer_waiting")
    instance = CampaignInstance.create!(
      host: jp, campaign: campaigns(:approved_campaign), status: :stopped_on_reply
    )
    reply = { "id" => "reply-1", "payload" => { "headers" => [] } }
    step = CampaignStepInstance.create!(
      campaign_instance: instance,
      campaign_step: campaign_steps(:approved_step_one),
      planned_delivery_at: 1.hour.ago,
      email_delivery_status: :sent,
      final_subject: "s", final_body: "b",
      gmail_thread_id: "t1",
      gmail_thread_snapshot: { "id" => "t1", "messages" => [{ "id" => "sent-1" }] },
      customer_replied: true,
      gmail_reply_payload: reply
    )

    patch resume_job_proposal_url(jp)

    step.reload
    assert_not step.customer_replied, "step is unflagged once the reply is absorbed"
    assert_equal %w[sent-1 reply-1], step.gmail_thread_snapshot["messages"].map { |m| m["id"] },
      "the recorded reply becomes part of the baseline snapshot"
  end

  # --- launch_campaign (manual relaunch from the show page) ---------------

  test "launch_campaign redirects to sign-in when not signed in" do
    post launch_campaign_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  # Helper: bring a proposal up to the readiness bar so launch isn't blocked
  # by missing customer fields. Tests that exercise the not_ready branch
  # explicitly blank specific fields after calling this.
  def make_ready(jp, scenario: scenarios(:sewage_backup))
    jp.update!(
      scenario:              scenario,
      customer_email:        "alice@example.com",
      customer_first_name:   "Alice",
      customer_house_number: "123",
      customer_street:       "Oak Ridge"
    )
    jp
  end

  test "launch_campaign creates a CampaignInstance when scenario + campaign are in place and proposal is ready" do
    sign_in @user
    jp = make_ready(job_proposals(:in_users_org))

    assert_difference "CampaignInstance.count", 1 do
      post launch_campaign_job_proposal_url(jp)
    end
    instance = jp.reload.campaign_instances.first
    assert_redirected_to job_proposal_campaign_instance_path(jp, instance)
    assert_match(/Campaign created/i, flash[:notice].to_s)
    assert_equal "approving", jp.status
  end

  test "launch_campaign reports already-running on a second click" do
    sign_in @user
    jp = make_ready(job_proposals(:in_users_org))
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)

    assert_no_difference "CampaignInstance.count" do
      post launch_campaign_job_proposal_url(jp)
    end
    assert_redirected_to job_proposal_campaign_instance_path(jp, instance)
    assert_match(/already running/i, flash[:notice].to_s)
  end

  test "launch_campaign refuses and lists missing fields when proposal isn't ready" do
    sign_in @user
    jp = make_ready(job_proposals(:in_users_org))
    jp.update!(customer_email: nil, customer_first_name: nil)

    assert_no_difference "CampaignInstance.count" do
      post launch_campaign_job_proposal_url(jp)
    end
    assert_redirected_to edit_job_proposal_path(jp)
    assert_match(/missing/i, flash[:alert].to_s)
    assert_match(/customer_email/, flash[:alert].to_s)
    assert_match(/customer_first_name/, flash[:alert].to_s)
  end

  test "launch_campaign refuses when scenario has no attached campaign" do
    sign_in @user
    jp = make_ready(job_proposals(:in_users_org), scenario: scenarios(:clean_water)) # fixture: campaign: nil

    assert_no_difference "CampaignInstance.count" do
      post launch_campaign_job_proposal_url(jp)
    end
    assert_match(/no campaign attached/i, flash[:alert].to_s)
  end

  # --- CTA column on the index ---

  test "index renders Review CTA for drafting proposals" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :drafting, pipeline_stage: nil, status_overlay: nil)
    get job_proposals_url
    assert_select "a[href=?]", edit_job_proposal_path(jp), text: /\AReview\z/
  end

  test "index renders View job CTA for approved proposals not in a campaign" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approved, pipeline_stage: nil, status_overlay: nil)
    get job_proposals_url
    assert_select "a[href=?]", job_proposal_path(jp), text: /View job/
  end

  test "index renders Resume CTA for paused in-flight proposals" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approved, pipeline_stage: "in_campaign", status_overlay: "paused")
    get job_proposals_url
    assert_select "form[action=?]", resume_job_proposal_path(jp) do
      assert_select "input[name=_method][value=patch]", true
      assert_select "button", text: /Resume/
    end
  end

  test "index renders Fix delivery issue CTA pointing at the edit page" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approved, pipeline_stage: "in_campaign", status_overlay: "delivery_issue")
    get job_proposals_url
    assert_select "a[href=?]", edit_job_proposal_path(jp), text: /Fix Issue/
  end

  test "index renders Open in Gmail CTA targeting a new tab" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approved, pipeline_stage: "in_campaign", status_overlay: "customer_waiting")
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    CampaignStepInstance.create!(
      campaign_instance: instance, campaign_step: campaign_steps(:approved_step_one),
      gmail_thread_id: "THREAD-XYZ", email_delivery_status: :sent
    )

    get job_proposals_url
    assert_select "a[target=_blank][href*=?]", "THREAD-XYZ", text: /Open in Gmail/
  end

  # --- mark_won / mark_lost -----------------------------------------------

  test "mark_won redirects to sign-in when not signed in" do
    patch mark_won_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  test "mark_won 404s for a proposal outside the user's scope" do
    sign_in @user
    patch mark_won_job_proposal_url(job_proposals(:other_tenant))
    assert_response :not_found
  end

  test "mark_won flips pipeline_stage to won and redirects with notice" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    patch mark_won_job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    assert_match(/won/i, flash[:notice])
    assert_equal "won", jp.reload.pipeline_stage
  end

  test "mark_lost redirects to sign-in when not signed in" do
    patch mark_lost_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  test "mark_lost 404s for a proposal outside the user's scope" do
    sign_in @user
    patch mark_lost_job_proposal_url(job_proposals(:other_tenant))
    assert_response :not_found
  end

  test "mark_lost with both loss fields flips pipeline_stage to lost and persists them" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    patch mark_lost_job_proposal_url(jp), params: {
      loss_reason_id: loss_reasons(:price_too_high).id,
      loss_notes:     "Picked the lower bid."
    }
    assert_redirected_to job_proposal_path(jp)
    assert_match(/lost/i, flash[:notice])
    jp.reload
    assert_equal "lost", jp.pipeline_stage
    assert_equal loss_reasons(:price_too_high), jp.loss_reason
    assert_equal "Picked the lower bid.", jp.loss_notes
  end

  test "mark_lost rejects when loss_reason_id is blank" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: nil)
    patch mark_lost_job_proposal_url(jp), params: { loss_reason_id: "", loss_notes: "Notes." }
    assert_redirected_to job_proposal_path(jp)
    assert_match(/required/i, flash[:alert])
    assert_nil jp.reload.pipeline_stage
  end

  test "mark_lost rejects when loss_reason_id refers to an unknown row" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: nil)
    patch mark_lost_job_proposal_url(jp), params: { loss_reason_id: 0, loss_notes: "Notes." }
    assert_redirected_to job_proposal_path(jp)
    assert_match(/required/i, flash[:alert])
    assert_nil jp.reload.pipeline_stage
  end

  test "mark_lost rejects when loss_notes is blank" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: nil)
    patch mark_lost_job_proposal_url(jp), params: { loss_reason_id: loss_reasons(:price_too_high).id, loss_notes: "" }
    assert_redirected_to job_proposal_path(jp)
    assert_match(/required/i, flash[:alert])
    assert_nil jp.reload.pipeline_stage
  end

  test "show page renders Mark Won button and a Mark Lost trigger when pipeline_stage is not won/lost" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: nil)
    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?] button", mark_won_job_proposal_path(jp), text: /Mark Won/
    # Mark Lost is now a modal trigger button (not a form), and the modal
    # contains the form posting to mark_lost.
    assert_select "button[data-bs-target='#markLostModal']", text: /Mark Lost/
    assert_select "#markLostModal form[action=?]", mark_lost_job_proposal_path(jp)
  end

  test "show page hides Mark Won/Lost trigger and modal when pipeline_stage is already won" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "won")
    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?]", mark_won_job_proposal_path(jp), count: 0
    assert_select "button[data-bs-target='#markLostModal']", count: 0
    assert_select "#markLostModal", count: 0
  end

  # --- revert_pipeline_stage ----------------------------------------------

  test "revert_pipeline_stage redirects to sign-in when not signed in" do
    patch revert_pipeline_stage_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  test "revert_pipeline_stage 404s for a proposal outside the user's scope" do
    sign_in @user
    patch revert_pipeline_stage_job_proposal_url(job_proposals(:other_tenant))
    assert_response :not_found
  end

  # --- revert_to_edit (Review Campaign → editing) ----------------------

  test "revert_to_edit flips approving back to drafting and destroys the drafting instance" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approving)
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :drafting)
    CampaignStepInstance.create!(
      campaign_instance: instance, campaign_step: campaign_steps(:approved_step_one),
      planned_delivery_at: 1.hour.from_now, email_delivery_status: :pending,
      final_subject: "preview", final_body: "preview body"
    )

    patch revert_to_edit_job_proposal_url(jp)
    assert_redirected_to edit_job_proposal_path(jp)
    assert_match(/reverted/i, flash[:notice])
    assert_equal "drafting", jp.reload.status
    refute CampaignInstance.exists?(instance.id), "drafting instance should be destroyed so a fresh one launches on next save"
  end

  test "revert_to_edit refuses when the proposal isn't in approving status" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approved)
    patch revert_to_edit_job_proposal_url(jp)
    assert_redirected_to edit_job_proposal_path(jp)
    assert_match(/nothing to revert/i, flash[:alert])
    assert_equal "approved", jp.reload.status
  end

  test "revert_to_edit 404s for a proposal outside the user's scope" do
    sign_in @user
    jp = job_proposals(:other_tenant)
    patch revert_to_edit_job_proposal_url(jp)
    assert_response :not_found
  end

  test "campaign instance show page renders Revert to edit button when approving" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(status: :approving)
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :drafting)
    get job_proposal_campaign_instance_url(jp, instance)
    assert_response :success
    assert_select "form[action=?] button", revert_to_edit_job_proposal_path(jp), text: /Revert to edit/
  end

  test "revert_pipeline_stage flips won back to in_campaign" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "won")
    patch revert_pipeline_stage_job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    assert_match(/in campaign/i, flash[:notice])
    assert_equal "in_campaign", jp.reload.pipeline_stage
  end

  test "revert_pipeline_stage flips lost back to in_campaign" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "lost")
    patch revert_pipeline_stage_job_proposal_url(jp)
    assert_equal "in_campaign", jp.reload.pipeline_stage
  end

  test "show page renders Revert button when pipeline_stage is won" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "won")
    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?] button", revert_pipeline_stage_job_proposal_path(jp), text: /Revert/
    assert_select "form[action=?]", mark_won_job_proposal_path(jp), count: 0
  end

  test "show page renders Revert button when pipeline_stage is lost" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "lost")
    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?] button", revert_pipeline_stage_job_proposal_path(jp), text: /Revert/
  end

  test "show page hides Revert button when pipeline_stage is not won/lost" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: nil)
    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?]", revert_pipeline_stage_job_proposal_path(jp), count: 0
  end

  test "show page renders the loss-details card with reason and notes when pipeline_stage is lost" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(
      pipeline_stage: "lost",
      loss_reason: loss_reasons(:went_with_competitor),
      loss_notes: "Customer chose ABC Restoration after the second visit."
    )
    get job_proposal_url(jp)
    assert_response :success
    assert_match(/Why we lost this job/, response.body)
    assert_match(/Went with competitor/, response.body)
    assert_match(/Customer chose ABC Restoration/, response.body)
  end

  test "show page hides the loss-details card when pipeline_stage is not lost" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "won")
    get job_proposal_url(jp)
    assert_response :success
    assert_no_match(/Why we lost this job/, response.body)
  end

  # --- pause --------------------------------------------------------------

  test "pause redirects to sign-in when not signed in" do
    patch pause_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  test "pause 404s for a proposal outside the user's scope" do
    sign_in @user
    patch pause_job_proposal_url(job_proposals(:other_tenant))
    assert_response :not_found
  end

  test "pause sets status_overlay to paused even when no campaign instance exists" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    patch pause_job_proposal_url(jp)
    assert_redirected_to job_proposal_path(jp)
    assert_match(/paused/i, flash[:notice])
    assert_equal "paused", jp.reload.status_overlay
  end

  test "pause flips an active campaign instance to paused and sets overlay" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    patch pause_job_proposal_url(jp)
    assert_equal "paused", jp.reload.status_overlay
    assert instance.reload.status_paused?
  end

  test "show page renders Pause button only when an active CampaignInstance exists" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "in_campaign", status_overlay: nil)
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)

    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?] button", pause_job_proposal_path(jp), text: /Pause/
  end

  test "show page hides Pause button when the latest CampaignInstance has completed" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "in_campaign", status_overlay: nil)
    CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :completed)

    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?]", pause_job_proposal_path(jp), count: 0
  end

  test "show page hides Pause button when no CampaignInstance exists at all" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: nil, status_overlay: nil)

    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?]", pause_job_proposal_path(jp), count: 0
  end

  test "show page hides Pause button when pipeline_stage is won" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "won")
    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?]", pause_job_proposal_path(jp), count: 0
  end

  test "show page hides Pause button when status_overlay is already paused" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    jp.update!(pipeline_stage: "in_campaign", status_overlay: "paused")
    get job_proposal_url(jp)
    assert_response :success
    assert_select "form[action=?]", pause_job_proposal_path(jp), count: 0
  end

  # --- approve ------------------------------------------------------------

  test "approve redirects to sign-in when not signed in" do
    patch approve_job_proposal_url(job_proposals(:in_users_org))
    assert_redirected_to new_user_session_path
  end

  test "approve 404s for a proposal outside the user's scope" do
    sign_in @user
    patch approve_job_proposal_url(job_proposals(:other_tenant))
    assert_response :not_found
  end

  test "approve flips status to approved, transitions a drafting instance to active, and redirects to the campaign instance show page" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :drafting)
    jp.update!(status: :approving)

    patch approve_job_proposal_url(jp)
    assert_redirected_to job_proposal_campaign_instance_path(jp, instance)
    assert_match(/Approved/i, flash[:notice])
    assert_equal "approved", jp.reload.status
    assert_equal "active", instance.reload.status,
      "approving a proposal must move its instance out of :drafting so the sweep can ship steps"
  end

  test "approve stamps started_at and accumulates offset_min across the step sequence" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    # offset_min is interpreted as "delay from the previous step". Setting
    # step one to 60 (1h after start) and step two to 1440 (1d after step one)
    # — the test asserts step two lands 25h after start, not 24h, proving
    # cumulation rather than absolute-from-start.
    step_one = campaign_steps(:approved_step_one)
    step_two = campaign_steps(:approved_step_two)
    step_one.update!(offset_min: 60, template_subject: "S1", template_body: "Hi {customer_first_name}")
    step_two.update!(offset_min: 1440, template_subject: "S2", template_body: "Following up")

    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    si_one = CampaignStepInstance.create!(campaign_instance: instance, campaign_step: step_one, email_delivery_status: :pending)
    si_two = CampaignStepInstance.create!(campaign_instance: instance, campaign_step: step_two, email_delivery_status: :pending)
    jp.update!(status: :approving, customer_first_name: "Alice")

    freeze_time = Time.zone.parse("2026-05-04T10:00:00Z")
    travel_to freeze_time do
      patch approve_job_proposal_url(jp)
    end

    instance.reload
    assert_in_delta freeze_time.to_f, instance.started_at.to_f, 1.0
    assert_in_delta (freeze_time + 60.minutes).to_f, si_one.reload.planned_delivery_at.to_f, 1.0
    assert_in_delta (freeze_time + (60 + 1440).minutes).to_f, si_two.reload.planned_delivery_at.to_f, 1.0
  end

  test "approve renders and locks each step's final_subject and final_body" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    step_one = campaign_steps(:approved_step_one)
    step_one.update!(template_subject: "Hi {customer_first_name}", template_body: "Body for {customer_first_name}")
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    si = CampaignStepInstance.create!(campaign_instance: instance, campaign_step: step_one, email_delivery_status: :pending)
    jp.update!(status: :approving, customer_first_name: "Alice")

    patch approve_job_proposal_url(jp)
    si.reload
    assert_equal "Hi Alice", si.final_subject
    assert_match(/Body for Alice/, si.final_body)
  end

  test "approve refuses and rolls back when a step's template has unresolved merge fields" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    step_one = campaign_steps(:approved_step_one)
    step_one.update!(template_body: "Hi {totally_unknown_token}")
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)
    si = CampaignStepInstance.create!(campaign_instance: instance, campaign_step: step_one, email_delivery_status: :pending)
    jp.update!(status: :approving)

    patch approve_job_proposal_url(jp)
    assert_redirected_to job_proposal_campaign_instance_path(jp, instance)
    assert_match(/Can't approve/i, flash[:alert])
    assert_match(/totally_unknown_token/, flash[:alert])
    assert_equal "approving", jp.reload.status
    assert_nil instance.reload.started_at
    assert_nil si.reload.final_subject
  end

  test "campaign instance show renders Approve button only when host status is approving" do
    sign_in @user
    jp = job_proposals(:in_users_org)
    instance = CampaignInstance.create!(host: jp, campaign: campaigns(:approved_campaign), status: :active)

    jp.update!(status: :approving)
    get job_proposal_campaign_instance_url(jp, instance)
    assert_response :success
    assert_select "form[action=?] button", approve_job_proposal_path(jp), text: /Approve/

    jp.update!(status: :approved)
    get job_proposal_campaign_instance_url(jp, instance)
    assert_select "form[action=?]", approve_job_proposal_path(jp), count: 0
    assert_match "Approved", response.body
  end
end
