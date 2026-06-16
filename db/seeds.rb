# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

admin = User.find_or_create_by!(email: "admin@example.com") do |u|
  u.password = "Password1"
  u.password_confirmation = "Password1"
  u.is_admin = true
  u.is_pending = false
end
admin.update!(first_name: "Avery", last_name: "Sloan") if admin.first_name.blank? && admin.last_name.blank?

# Gemini Model + PdfProcessingRevision are now created by CatalogLoader
# (production-safe path), which is called below. No duplication needed.

# --- Demo tenant + admin/owner membership ----------------------------------

demo_tenant = Tenant.find_or_create_by!(name: "Demo Roofing Co.")
# Real ServiceMark customers use Dash as their CRM; making the demo tenant
# require a DASH job number mirrors that and exercises the JobProposal
# validation in dash_job_number_required_when_approved. Deterministic
# here so dev-DB state doesn't drift away from what the seed assumes.
demo_tenant.update!(job_reference_required: true) unless demo_tenant.job_reference_required

demo_owner = User.find_or_create_by!(email: "owner@example.com") do |u|
  u.password = "Password1"
  u.password_confirmation = "Password1"
  u.is_pending = false
  u.tenant = demo_tenant
end
demo_owner.update!(tenant: demo_tenant) if demo_owner.tenant != demo_tenant
demo_owner.update!(first_name: "Jordan", last_name: "Pierce") if demo_owner.first_name.blank? && demo_owner.last_name.blank?
admin.update!(tenant: demo_tenant) if admin.tenant.nil?

# A rank-and-file teammate inside the demo tenant: not admin, doesn't own
# any of the demo proposals. Useful for poking at the "what does a regular
# user see" surface — sidebar contents, proposals they can't edit, ability
# checks — without having to grant or revoke flags by hand.
demo_teammate = User.find_or_create_by!(email: "teammate@example.com") do |u|
  u.password = "Password1"
  u.password_confirmation = "Password1"
  u.is_pending = false
  u.tenant = demo_tenant
end
demo_teammate.update!(tenant: demo_tenant) if demo_teammate.tenant != demo_tenant
demo_teammate.update!(first_name: "Riley", last_name: "Park") if demo_teammate.first_name.blank? && demo_teammate.last_name.blank?

# Two demo locations for the demo tenant. Proposals below are split across
# them so the Job Proposals location filter has interesting data.
DEMO_TENANT_LOCATIONS = [
  { display_name: "Naperville HQ", address_line_1: "200 W Jefferson Ave",
    city: "Naperville", state: "IL", postal_code: "60540", phone_number: "(630) 555-0140" },
  { display_name: "Rockford Branch", address_line_1: "120 W State St",
    city: "Rockford", state: "IL", postal_code: "61101", phone_number: "(815) 555-0118" }
].freeze

demo_locations = DEMO_TENANT_LOCATIONS.map do |attrs|
  demo_tenant.locations.find_or_initialize_by(display_name: attrs[:display_name]).tap do |loc|
    loc.assign_attributes(attrs.merge(is_active: true))
    loc.save!
  end
end

# Restoration job types and scenarios. Same code that powers the
# `catalog:load` rake task used in production.
CatalogLoader.load!

# --- Demo tenant activations ------------------------------------------------
# Activate every restoration job type for the demo tenant, plus every
# scenario under those job types. Mirrors the admin "Activate all scenarios"
# flow per Admin::JobTypeActivationsController, so the demo tenant lights up
# the full catalog out of the box.

restoration_codes = CatalogLoader::RESTORATION_JOB_TYPES.map { |attrs| attrs[:type_code] }
JobType.where(type_code: restoration_codes).includes(:scenarios).find_each do |job_type|
  TenantJobType.find_or_initialize_by(tenant: demo_tenant, job_type: job_type).tap do |tjt|
    tjt.is_active = true
    tjt.save!
  end

  job_type.scenarios.each do |scenario|
    TenantScenario.find_or_initialize_by(tenant: demo_tenant, scenario: scenario).tap do |ts|
      ts.is_active = true
      ts.save!
    end
  end
end

# --- Demo job proposals -----------------------------------------------------
# Wired to the restoration job types and the scenario codes seeded above.
# Pipeline stages and overlays follow PRD-01 v1.4.1 §10: in_campaign +
# optional overlay (paused, customer_waiting, delivery_issue) for active
# jobs; won / lost for terminal jobs.

DEMO_PROPOSALS = [
  # --- Water mitigation -----------------------------------------------------
  { ref: "DEMO-WM-001", scenario: "pipe_burst", first: "Marcus", last: "Holloway", title: "Mr.",
    house: "1842", street: "Glenwood Drive", city: "Naperville", state: "IL", zip: "60540",
    value: 8_640.00, status: :new, stage: "in_campaign", overlay: nil,
    description: "Second-floor supply line burst overnight; water through hallway ceiling and into living room. Customer shut main off. Cat 1, ~600 sq ft affected." },

  { ref: "DEMO-WM-002", scenario: "appliance_failure", first: "Priya", last: "Raman", title: "Mrs.",
    house: "27", street: "Linden Court", city: "Schaumburg", state: "IL", zip: "60173",
    value: 4_215.50, status: :open, stage: "in_campaign", overlay: "customer_waiting",
    description: "Dishwasher supply hose failed during cycle. Water under cabinets and toe-kick, traveled into adjacent dining room subfloor.",
    last_reply_from: "priya.raman@example.com", last_reply_subject: "Re: Drying plan for kitchen",
    last_reply_snippet: "Just checking — would Tuesday work for the moisture re-check? My husband will be home." },

  { ref: "DEMO-WM-003", scenario: "storm_related_flooding", first: "Doug", last: "McAllister", title: "Mr.",
    house: "504", street: "Riverbend Lane", city: "Rockford", state: "IL", zip: "61107",
    value: 14_780.00, status: :open, stage: "in_campaign", overlay: nil,
    description: "Basement flooded during Friday storm — ~4 inches standing water, finished rec room and home office both impacted. Three other bids on the property." },

  { ref: "DEMO-WM-004", scenario: "sewage_backup", first: "Beverly", last: "Okafor", title: "Ms.",
    house: "1201", street: "Commerce Park Blvd", city: "Aurora", state: "IL", zip: "60504",
    value: 22_540.00, status: :closed, stage: "won", overlay: nil,
    description: "Main line backup into ground-floor restrooms of single-tenant office building. Cat 3. Hard surfaces only on affected floor; carpet pad replaced." },

  { ref: "DEMO-WM-005", scenario: "clean_water_flooding", first: "Henry", last: "Vasquez", title: "Mr.",
    house: "318", street: "Chestnut Ave", city: "Joliet", state: "IL", zip: "60435",
    value: 6_320.00, status: :closed, stage: "lost", overlay: nil,
    description: "Water heater tank failure overnight; water across utility room and into hallway. Cat 1.",
    loss_reason: "price_too_high",
    loss_notes: "Customer's plumber referred a competitor at lower bid; chose them after 24h." },

  { ref: "DEMO-WM-006", scenario: "gray_water", first: "Lacey", last: "Burke", title: "Ms.",
    house: "76", street: "Sycamore Trail", city: "Evanston", state: "IL", zip: "60201",
    value: 3_975.00, status: :open, stage: "in_campaign", overlay: "paused",
    description: "Washing machine drain hose overflow into laundry/mudroom. Cat 2. Customer requested pause while traveling — resume Wed." },

  { ref: "DEMO-WM-007", scenario: "pipe_burst", first: "Greg", last: "Torres", title: "Mr.",
    house: "9", street: "Maple Hill Court", city: "Wheaton", state: "IL", zip: "60187",
    value: 11_240.00, status: :open, stage: "in_campaign", overlay: nil,
    description: "Outdoor hose bib failed mid-thaw; water tracked into finished basement through rim joist. Cat 1, drying day 2." },

  # --- Mold remediation -----------------------------------------------------
  { ref: "DEMO-MR-001", scenario: "visible_mold_growth", first: "Anita", last: "Park", title: "Mrs.",
    house: "412", street: "Brookline Way", city: "Oak Park", state: "IL", zip: "60302",
    value: 5_410.00, status: :open, stage: "in_campaign", overlay: nil,
    description: "Visible black growth on bathroom ceiling and around exhaust fan; tenant complaint prompted call. Pre-remediation testing scheduled." },

  { ref: "DEMO-MR-002", scenario: "crawlspace_mold", first: "Walter", last: "Kessler", title: "Mr.",
    house: "2207", street: "Oak Ridge Drive", city: "Lombard", state: "IL", zip: "60148",
    value: 8_870.00, status: :new, stage: "in_campaign", overlay: nil,
    description: "HVAC tech flagged surface mold across crawlspace floor joists during AC service. Customer has not been under the house. Referral from MidAmerica HVAC." },

  { ref: "DEMO-MR-003", scenario: "structural_mold", first: "Diane", last: "Albrecht", title: "Dr.",
    house: "55", street: "Briarcliff Place", city: "Hinsdale", state: "IL", zip: "60521",
    value: 34_280.00, status: :open, stage: "in_campaign", overlay: "customer_waiting",
    description: "Whole-attic mold across roof sheathing — ventilation issue; testing complete; protocol in draft. Awaiting customer decision on insulation replacement scope.",
    last_reply_from: "dalbrecht@example.com", last_reply_subject: "Re: Protocol draft and insulation question",
    last_reply_snippet: "Thanks for the protocol draft. We're discussing the insulation R-value with our energy auditor — back to you Friday." },

  { ref: "DEMO-MR-004", scenario: "post_water_mold_discovered", first: "Roman", last: "Chen", title: "Mr.",
    house: "143", street: "Evergreen Circle", city: "Skokie", state: "IL", zip: "60076",
    value: 11_750.00, status: :closed, stage: "won", overlay: nil,
    description: "Mold discovered behind drywall during reno, six months after a 2025 water event; testing confirmed elevated spores; standard remediation protocol." },

  { ref: "DEMO-MR-005", scenario: "visible_mold_growth", first: "Sara", last: "Whitfield", title: "Ms.",
    house: "1018", street: "Coventry Road", city: "Glen Ellyn", state: "IL", zip: "60137",
    value: 6_900.00, status: :open, stage: "in_campaign", overlay: "delivery_issue",
    description: "Mold growth around basement window wells and along sill plate; tenant moving in next month. Email bouncing — needs phone follow-up." },

  # --- Structural cleaning --------------------------------------------------
  { ref: "DEMO-SC-001", scenario: "post_fire_soot_smoke", first: "Jerome", last: "Bachmann", title: "Mr.",
    house: "603", street: "Willowbrook Lane", city: "Downers Grove", state: "IL", zip: "60515",
    value: 19_410.00, status: :open, stage: "in_campaign", overlay: nil,
    description: "Kitchen grease fire; soot through main floor and partial second floor; HVAC shut down at outage. Day 3 since loss; cleaning window narrowing." },

  { ref: "DEMO-SC-002", scenario: "post_water_deep_clean", first: "Inez", last: "Alvarado", title: "Mrs.",
    house: "88", street: "Park Forest Drive", city: "Cicero", state: "IL", zip: "60804",
    value: 7_820.00, status: :closed, stage: "won", overlay: nil,
    description: "Post-mitigation deep clean of finished basement after pipe burst job last month. Hard surfaces, baseboards, HVAC vent cleaning." },

  { ref: "DEMO-SC-003", scenario: "post_fire_soot_smoke", first: "Curtis", last: "Yeo", title: "Mr.",
    house: "315", street: "Hawthorne Street", city: "Berwyn", state: "IL", zip: "60402",
    value: 12_540.00, status: :new, stage: "in_campaign", overlay: nil,
    description: "Detached garage fire; smoke migration into adjacent home through shared wall and attic vents. Light soot on second-floor contents." },

  { ref: "DEMO-SC-004", scenario: "post_water_deep_clean", first: "Felicia", last: "Marsh", title: "Mrs.",
    house: "722", street: "Woodland Heights", city: "Bloomington", state: "IL", zip: "61704",
    value: 5_980.00, status: :closed, stage: "lost", overlay: nil,
    description: "Deep clean follow-up after gray water event. Customer attempted DIY cleanup before estimate.",
    loss_reason: "no_response_from_customer",
    loss_notes: "Customer went silent after Day 5 follow-up; assumed self-handled." },

  # --- General cleaning -----------------------------------------------------
  { ref: "DEMO-GC-001", scenario: "move_in_move_out", first: "Trevor", last: "Nakamura", title: "Mr.",
    house: "104", street: "Warwick Court", city: "La Grange", state: "IL", zip: "60525",
    value: 1_640.00, status: :closed, stage: "won", overlay: nil,
    description: "Three-bedroom rental turnover between tenants; deep clean including appliances, baseboards, and inside cabinets. Keys returned next Friday." },

  { ref: "DEMO-GC-002", scenario: "post_construction_cleanup", first: "Yvonne", last: "Petrov", title: "Mrs.",
    house: "2580", street: "Hollybrook Drive", city: "Lisle", state: "IL", zip: "60532",
    value: 4_915.00, status: :open, stage: "in_campaign", overlay: nil,
    description: "New-build single-family — contractor rough-clean is done; customer needs occupy-ready clean before move-in date (June 12)." },

  { ref: "DEMO-GC-003", scenario: "odor_remediation", first: "Beth", last: "Hollander", title: "Ms.",
    house: "47", street: "Cobblestone Lane", city: "Wheeling", state: "IL", zip: "60090",
    value: 2_785.00, status: :open, stage: "in_campaign", overlay: "delivery_issue",
    description: "Cigarette/tobacco odor in inherited 1,200 sq ft condo; listing prep. Source-then-air sequence proposed." },

  { ref: "DEMO-GC-004", scenario: "commercial_deep_clean", first: "Phil", last: "Donovan", title: "Mr.",
    house: "8800", street: "Industrial Parkway", city: "Aurora", state: "IL", zip: "60506",
    value: 6_720.00, status: :new, stage: "in_campaign", overlay: nil,
    description: "9,400 sq ft office floor — quarterly deep clean covering items janitorial doesn't (HVAC vent fronts, high dusting, baseboards, glass partitions). Off-hours required." },

  { ref: "DEMO-GC-005", scenario: "move_in_move_out", first: "Marisol", last: "Greene", title: "Ms.",
    house: "16", street: "Heatherfield Court", city: "Champaign", state: "IL", zip: "61820",
    value: 2_080.00, status: :closed, stage: "lost", overlay: nil,
    description: "Estate sale prep clean before listing.",
    loss_reason: "timing_scheduling_conflict",
    loss_notes: "Customer needed crew within 48 hours; we couldn't accommodate before her open-house deadline." },

  { ref: "DEMO-GC-006", scenario: "odor_remediation", first: "Devin", last: "Ramos", title: "Mr.",
    house: "239", street: "Westridge Drive", city: "Decatur", state: "IL", zip: "62526",
    value: 3_410.00, status: :open, stage: "in_campaign", overlay: nil,
    description: "Persistent musty odor in finished basement after a partial wet event last winter; customer wants source confirmation before treatment." },

  # --- Trauma / Biohazard ---------------------------------------------------
  { ref: "DEMO-TB-001", scenario: "trauma_crime_scene", first: "Karen", last: "Whitlock", title: "Ms.",
    house: "612", street: "Sunrise Place", city: "Peoria", state: "IL", zip: "61614",
    value: 8_410.00, status: :closed, stage: "won", overlay: nil,
    description: "Single-occupant apartment cleanup after coroner release. Property manager primary contact; daughter cc'd. Discreet entry; unmarked vehicles." },

  { ref: "DEMO-TB-002", scenario: "trauma_crime_scene", first: "Walter", last: "Eames", title: "Mr.",
    house: "47", street: "Larkspur Drive", city: "Madison", state: "WI", zip: "53704",
    value: 5_920.00, status: :open, stage: "in_campaign", overlay: nil,
    description: "Bathroom-confined incident; landlord-engaged after tenant family declined; standard biohazard protocol." }
].freeze

# Loss reasons. The 0509 migration seeded these inline, but a
# `db:schema:load`-based dev setup (db:setup / db:reset) skips
# migration bodies and leaves the table empty. Recreate idempotently
# here so a fresh dev DB has the lost-job dropdown populated.
[
  { code: "price_too_high",             display_name: "Price too high",                sort_order: 10 },
  { code: "went_with_competitor",       display_name: "Went with competitor",          sort_order: 20 },
  { code: "insurance_issue",            display_name: "Insurance issue",               sort_order: 30 },
  { code: "no_response_from_customer",  display_name: "No response from customer",     sort_order: 40 },
  { code: "timing_scheduling_conflict", display_name: "Timing / scheduling conflict",  sort_order: 50 },
  { code: "other",                      display_name: "Other",                         sort_order: 99 }
].each do |attrs|
  LossReason.find_or_create_by!(code: attrs[:code]) do |lr|
    lr.display_name = attrs[:display_name]
    lr.sort_order   = attrs[:sort_order]
  end
end

scenario_lookup = Scenario.includes(:job_type).index_by(&:code)
loss_reason_lookup = LossReason.all.index_by(&:code)

DEMO_PROPOSALS.each_with_index do |row, i|
  scenario = scenario_lookup[row[:scenario]]
  next unless scenario # skip if scenario seed didn't load (e.g., missing markdown)

  proposal = JobProposal.find_or_initialize_by(internal_reference: row[:ref])
  proposal.tenant = demo_tenant
  proposal.location = demo_locations[i % demo_locations.size]
  proposal.owner = demo_owner
  proposal.created_by_user = (i.even? ? demo_owner : admin)
  proposal.job_type = scenario.job_type
  proposal.scenario = scenario
  proposal.customer_first_name = row[:first]
  proposal.customer_last_name = row[:last]
  proposal.customer_title = row[:title]
  proposal.customer_house_number = row[:house]
  proposal.customer_street = row[:street]
  proposal.customer_city = row[:city]
  proposal.customer_state = row[:state]
  proposal.customer_zip = row[:zip]
  proposal.proposal_value = row[:value]
  proposal.job_description = row[:description]
  # Synthetic but stable per-row DASH number — demo_tenant requires one
  # before a proposal can be saved as :approved (see
  # JobProposal#dash_job_number_required_when_approved). The index-based
  # suffix keeps the value deterministic across re-seeds. The stored
  # value is just the identifier ("2026-1000", etc.) — the UI prepends
  # "DASH #" itself, so embedding it here would render as "DASH #DASH-…".
  proposal.dash_job_number = "2026-#{(1000 + i)}"
  # The row's symbolic :status (:new/:open/:closed) is a demo-state marker
  # used by the closed-branch logic below. The persisted JobProposal.status
  # enum is drafting/approving/approved — every demo row is past the
  # drafting/approving phase (all carry pipeline_stage in_campaign/won/lost),
  # so they all persist as :approved.
  proposal.status = :approved
  proposal.pipeline_stage = row[:stage]
  proposal.status_overlay = row[:overlay]
  proposal.status_details = row[:overlay]&.humanize

  if row[:last_reply_from].present?
    proposal.last_reply = {
      from: row[:last_reply_from],
      at: ((i % 4) + 1).hours.ago.iso8601,
      subject: row[:last_reply_subject],
      snippet: row[:last_reply_snippet]
    }
  else
    proposal.last_reply = nil
  end

  if row[:status] == :closed
    proposal.closed_at = ((i % 14) + 1).days.ago
    proposal.closed_by_user = demo_owner
    proposal.loss_reason = row[:stage] == "lost" ? loss_reason_lookup.fetch(row[:loss_reason]) : nil
    proposal.loss_notes = row[:stage] == "lost" ? row[:loss_notes] : nil
  else
    proposal.closed_at = nil
    proposal.closed_by_user = nil
    proposal.loss_reason = nil
    proposal.loss_notes = nil
  end

  proposal.save!
end

# --- A dozen demo tenants with seeded users -------------------------------
# Idempotent. Uses parameterized tenant names as the email domain so re-runs
# don't collide. None get is_admin — that's reserved for SMAI staff.

DEMO_TENANTS = [
  { name: "Pacific Coast Restoration",        users: [["Sarah", "Chen"], ["Marcus", "Reyes"], ["Nicole", "Park"], ["David", "O'Brien"]] },
  { name: "Greater Boston Disaster Services", users: [["Liam", "Sullivan"], ["Mei", "Tanaka"], ["Kwame", "Adusei"]] },
  { name: "Heartland Restoration Group",      users: [["Avery", "Lindquist"], ["Jamal", "Booker"], ["Priya", "Shah"], ["Tomas", "Ortiz"]] },
  { name: "Sunbelt Cleanup Co.",              users: [["Jenna", "Whitcomb"], ["Hector", "Romero"], ["Aisha", "Bello"]] },
  { name: "Mountain View Restoration",        users: [["Eli", "Frost"], ["Maya", "Patel"], ["Diego", "Velasquez"], ["Naomi", "Liu"]] },
  { name: "Lakeshore Mitigation Partners",    users: [["Brett", "Donovan"], ["Camille", "Beaulieu"], ["Sergio", "Marin"]] },
  { name: "Desert Vista Services",            users: [["Lena", "Halverson"], ["Ravi", "Subramaniam"], ["Esme", "Caldera"]] },
  { name: "Northern Forest Restoration",      users: [["Soren", "Eklund"], ["Adaeze", "Okafor"], ["Felix", "Mueller"], ["Iris", "Hoang"]] },
  { name: "Coastal Cleanup Network",          users: [["Theo", "Marchetti"], ["Renee", "Aubert"], ["Kenji", "Nakamura"]] },
  { name: "Midwest Property Recovery",        users: [["Hank", "Brubaker"], ["Lucia", "Esposito"], ["Olamide", "Akande"], ["Margaret", "Doyle"]] },
  { name: "Gulf Stream Restoration",          users: [["Beatriz", "Quintero"], ["Jonas", "Van Houten"], ["Ines", "Carvalho"]] },
  { name: "River Valley Services",            users: [["Rowan", "Halloran"], ["Yusuf", "Demir"], ["Anika", "Khatri"], ["Pia", "Lindgren"]] }
].freeze

DEMO_TENANTS.each do |entry|
  tenant = Tenant.find_or_create_by!(name: entry[:name])
  domain = tenant.name.parameterize

  entry[:users].each do |(first, last)|
    slug = "#{first}.#{last}".downcase.gsub(/[^a-z.]/, "")
    email = "#{slug}@#{domain}.example.com"
    user = User.find_or_create_by!(email: email) do |u|
      u.password = "Password1"
      u.password_confirmation = "Password1"
      u.first_name = first
      u.last_name = last
      u.is_pending = false
      u.tenant = tenant
    end
    user.update!(tenant: tenant) if user.tenant != tenant
  end
end

# --- Demo locations for the dozen tenants ----------------------------------
# Idempotent. Cities/states roughly fit the tenant's geographic flavor.

DEMO_LOCATIONS = {
  "Pacific Coast Restoration"        => { city: "San Diego",      state: "CA", street: "1240 Harbor Drive",     zip: "92101", phone: "(619) 555-0142" },
  "Greater Boston Disaster Services" => { city: "Cambridge",      state: "MA", street: "88 Kendall Square",     zip: "02139", phone: "(617) 555-0107" },
  "Heartland Restoration Group"      => { city: "Kansas City",    state: "MO", street: "4421 Main Street",      zip: "64111", phone: "(816) 555-0188" },
  "Sunbelt Cleanup Co."              => { city: "Phoenix",        state: "AZ", street: "2900 Camelback Road",   zip: "85016", phone: "(602) 555-0149" },
  "Mountain View Restoration"        => { city: "Boulder",        state: "CO", street: "1755 Pearl Street",     zip: "80302", phone: "(303) 555-0163" },
  "Lakeshore Mitigation Partners"    => { city: "Milwaukee",      state: "WI", street: "612 Lakefront Drive",   zip: "53202", phone: "(414) 555-0124" },
  "Desert Vista Services"            => { city: "Las Vegas",      state: "NV", street: "3700 W Sahara Avenue",  zip: "89102", phone: "(702) 555-0156" },
  "Northern Forest Restoration"      => { city: "Duluth",         state: "MN", street: "210 Lake Avenue",       zip: "55802", phone: "(218) 555-0119" },
  "Coastal Cleanup Network"          => { city: "Wilmington",     state: "NC", street: "415 South Front Street", zip: "28401", phone: "(910) 555-0173" },
  "Midwest Property Recovery"        => { city: "Indianapolis",   state: "IN", street: "1 American Square",     zip: "46282", phone: "(317) 555-0181" },
  "Gulf Stream Restoration"          => { city: "Tampa",          state: "FL", street: "401 East Jackson Street", zip: "33602", phone: "(813) 555-0167" },
  "River Valley Services"            => { city: "Portland",       state: "OR", street: "1100 SW 6th Avenue",    zip: "97204", phone: "(503) 555-0192" }
}.freeze

DEMO_LOCATIONS.each do |tenant_name, attrs|
  tenant = Tenant.find_by(name: tenant_name)
  next unless tenant

  display_name = tenant_name.split.first(2).join(" ") # e.g. "Pacific Coast"
  next if tenant.locations.where(display_name: display_name).exists?

  tenant.locations.create!(
    display_name: display_name,
    address_line_1: attrs[:street],
    city: attrs[:city],
    state: attrs[:state],
    postal_code: attrs[:zip],
    phone_number: attrs[:phone],
    is_active: true
  )
end

# --- Approve catalog-loaded campaigns for the demo ------------------------
# CatalogLoader (called above at the top of this seed file) created one
# Campaign per Scenario with status :new and steps populated from the
# authored markdown under docs/specs-repo/specs/templates/v1-output/.
# A real production
# install leaves them :new so an admin reviews + approves via the UI
# before any sends. The demo bumps them to :approved outright so the
# in-flight CampaignInstance fixtures below have something runnable to
# attach to. Idempotent: campaigns already :approved are left alone.

Campaign.where(status: :draft, attributed_to_type: "Scenario").find_each do |campaign|
  campaign.update!(
    status: :approved,
    approved_by_user: admin,
    approved_at: 30.days.ago
  )
end

# --- In-flight CampaignInstances against in_campaign proposals ------------
# For each proposal whose pipeline_stage is "in_campaign", create one
# CampaignInstance hosted by the proposal, then per-step instances reflecting
# realistic in-flight state. Closed proposals (won / lost) are intentionally
# skipped — the user asked for in-flight runs.

OVERLAY_TO_INSTANCE_STATUS = {
  nil                       => :active,
  "paused"                  => :paused,
  "customer_waiting"        => :stopped_on_reply,
  "delivery_issue"          => :stopped_on_delivery_issue
}.freeze

# How many "real" days into a campaign each fixture sits, so the seed has a
# spread of progress. Indexed off the scenario code's hash so the same proposal
# always falls at the same point on re-seed.
def days_into_campaign_for(proposal)
  (proposal.id.to_i % 6) + 1   # 1..6 days
end

JobProposal.where(pipeline_stage: "in_campaign").includes(:scenario).find_each do |proposal|
  scenario = proposal.scenario
  next unless scenario

  campaign = Campaign.find_by(attributed_to_type: "Scenario", attributed_to_id: scenario.id)
  next unless campaign

  instance = CampaignInstance.find_or_initialize_by(
    host_type: "JobProposal", host_id: proposal.id, campaign: campaign
  )
  instance.status = OVERLAY_TO_INSTANCE_STATUS.fetch(proposal.status_overlay, :active)
  instance.save!

  # Anchor the instance timeline to (now - days_into_campaign) so steps with
  # offset <= that have plausibly already been sent and later steps are still
  # pending in the future.
  started_at = days_into_campaign_for(proposal).days.ago

  campaign.steps.order(:sequence_number).each do |step|
    si = CampaignStepInstance.find_or_initialize_by(
      campaign_instance_id: instance.id, campaign_step_id: step.id
    )
    si.planned_delivery_at = started_at + step.offset_min.minutes
    # Mirror what CampaignSweepJob does at real send time: render the
    # template through MailGenerator and store the substituted strings,
    # so demo "sent" rows look like they would on a live send (and the
    # proposal show page doesn't display literal {placeholder} text).
    # render_safely keeps unresolved placeholders in place rather than
    # crashing the seed if a demo proposal lacks a field.
    rendered = MailGenerator.render_safely(campaign_step: step, job_proposal: proposal)
    si.final_subject = rendered.subject
    si.final_body    = rendered.body
    si.gmail_thread_id ||= "DEMO-thread-#{instance.id}"

    past_due = si.planned_delivery_at <= Time.current
    si.email_delivery_status =
      if past_due
        case instance.status
        when "stopped_on_delivery_issue" then (step.sequence_number == 1 ? :failed : :pending)
        when "paused"                    then (step.sequence_number == 1 ? :sent : :pending)
        when "stopped_on_reply"          then :sent
        else                                  :sent
        end
      else
        :pending
      end
    si.save!
  end
end
