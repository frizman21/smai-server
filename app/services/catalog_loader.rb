# Loads the production-safe catalog data: restoration job types, the
# scenarios authored under the smai-specs submodule
# (docs/specs-repo/specs/templates/v1-output/), and a default Campaign
# per scenario with steps populated from the same source markdown.
# Idempotent — safe to run any number of times against an existing
# database. No tenants, users, or demo proposals are touched here; that
# lives in db/seeds.rb for dev.
#
# Used by:
#   - rake task `catalog:load` (production setup, see docs/user-guide/00-production-setup.md)
#   - db/seeds.rb (dev seeding chains through here)
#
# Campaign loading notes:
#   - Default campaigns are created in status :new so an admin reviews
#     and approves them via the UI before any sends happen.
#   - Existing campaigns and steps are NEVER overwritten. If an admin
#     hand-edited a step body or renamed a campaign, re-running
#     catalog:load preserves those edits — only missing rows are added.
class CatalogLoader
  RESTORATION_JOB_TYPES = [
    {
      type_code: "general_cleaning",
      name: "General Cleaning",
      description: "One-time deep cleaning beyond normal janitorial scope: post-construction cleanup, move-in / move-out, odor remediation, and HVAC cleaning."
    },
    {
      type_code: "mold_remediation",
      name: "Mold Remediation",
      description: "Containment, removal, and remediation of mold growth — including mold discovered during or after a water event."
    },
    {
      type_code: "structural_cleaning",
      name: "Structural Cleaning",
      description: "Cleanup of structural surfaces after fire, smoke, or water damage. Soot and odor removal, deodorization, post-water deep cleaning."
    },
    {
      type_code: "trauma_biohazard",
      name: "Trauma / Biohazard",
      description: "Trauma scene cleanup and biohazard exposure work — blood, bodily fluids, regulated materials. Legal review required before any communication ships."
    },
    {
      type_code: "water_mitigation",
      name: "Water Mitigation",
      description: "Water removal, drying, and dehumidification after a water event. Time-sensitive — the first 48 hours determine downstream scope."
    }
  ].freeze

  # Campaign template markdown lives in the smai-specs submodule, mounted
  # at docs/specs-repo. A fresh checkout must init submodules
  # (`git submodule update --init`) for this path to be populated.
  CAMPAIGNS_ROOT = Rails.root.join("docs", "specs-repo", "specs", "templates", "v1-output")

  # The Gemini model + extraction prompt JobProposalProcessor reads at
  # upload time. PdfProcessingRevision rows are versioned by content —
  # find_or_create_by(instructions:) means a prompt edit becomes a new
  # revision automatically (the is_current scope picks the highest
  # revision_number). Production needs at least one revision present
  # before AI extraction will fire; without it the processor silently
  # falls back to stub data.
  PDF_EXTRACTION_MODEL = {
    model_id: "gemini-2.5-flash",
    name:     "Gemini 2.5 Flash",
    provider: "gemini"
  }.freeze

  PDF_EXTRACTION_PROMPT = <<~PROMPT
    You are an expert data extraction AI. Your task is to meticulously analyze the provided document and extract
      key details into a structured JSON format.

      **Instructions:**

      1.  **Analyze the Document:** Carefully read the entire document.
      2.  **Extract Key Information:** Identify and extract the following fields.
      3.  **Format as JSON:** Return **ONLY** the raw JSON object. Absolutely DO NOT include markdown code blocks,
      backticks (```), or explanatory text.
      4.  **Handle Missing Data:** If a field cannot be found, is ambiguous, or is not applicable, the value in the
      JSON output for that key **must be `null`**. Do not invent or guess data.
      5.  **Dates:** Format all dates as `YYYY-MM-DD`.
      6.  **Amounts:** Extract all monetary values as raw JSON numbers without currency symbols or commas (e.g.,
      12345.67). Make sure they are JSON numbers, not strings.

      **Extraction Fields:**

      *   `title`: The customer's formal title (e.g., Mr., Mrs., Ms., Dr.).
      *   `firstName`, `lastName`, `email`
      *   `jobDescription`: Concise one-sentence summary
      *   `internalRef`: Job number / estimate ID
      *   `jobType`: Inferred from `{{jobTypes}}` (templated at runtime)
      *   `estimateDate`, `expirationDate` (YYYY-MM-DD)
      *   `subtotal`, `taxAmount`, `discountAmount`, `depositAmount`, `totalAmount`
      *   `isEmergency`, `estimatedDuration`, `warrantyIncluded`, `optionsProvided`, `paymentTerms`
      *   `houseNumber`, `street`, `city`, `state`, `zip`

      **JSON Output Structure:** { ...all the above keys... }
  PROMPT

  Result = Struct.new(
    :job_types_created, :job_types_existing,
    :scenarios_created, :scenarios_existing,
    :campaigns_created, :campaigns_existing,
    :steps_created, :steps_existing,
    keyword_init: true
  ) do
    def summary
      "#{job_types_created + job_types_existing} job types " \
      "(#{job_types_created} new, #{job_types_existing} existing); " \
      "#{scenarios_created + scenarios_existing} scenarios " \
      "(#{scenarios_created} new, #{scenarios_existing} existing); " \
      "#{campaigns_created + campaigns_existing} campaigns " \
      "(#{campaigns_created} new, #{campaigns_existing} existing); " \
      "#{steps_created + steps_existing} campaign steps " \
      "(#{steps_created} new, #{steps_existing} existing)"
    end
  end

  def self.load!(io: $stdout)
    new(io: io).load!
  end

  def initialize(io: $stdout)
    @io = io
    @result = Result.new(
      job_types_created: 0, job_types_existing: 0,
      scenarios_created: 0, scenarios_existing: 0,
      campaigns_created: 0, campaigns_existing: 0,
      steps_created: 0, steps_existing: 0
    )
  end

  def load!
    log "Loading restoration job types..."
    load_job_types

    log "Loading scenarios from #{CAMPAIGNS_ROOT.relative_path_from(Rails.root)}..."
    load_scenarios

    log "Loading default campaigns + steps from the same files..."
    load_campaigns

    log "Ensuring PDF extraction model + prompt revision..."
    load_pdf_extraction_setup

    log "Done. #{@result.summary}"
    @result
  end

  private

  def load_job_types
    RESTORATION_JOB_TYPES.each do |attrs|
      record = JobType.find_or_initialize_by(type_code: attrs[:type_code])
      if record.new_record?
        record.assign_attributes(name: attrs[:name], description: attrs[:description])
        record.save!
        @result.job_types_created += 1
        log "  created job type: #{attrs[:type_code]}"
      else
        @result.job_types_existing += 1
      end
    end
  end

  def load_scenarios
    return unless Dir.exist?(CAMPAIGNS_ROOT)

    Dir.children(CAMPAIGNS_ROOT).sort.each do |type_dir|
      type_path = CAMPAIGNS_ROOT.join(type_dir)
      next unless File.directory?(type_path)

      job_type = JobType.find_by(type_code: type_dir)
      next unless job_type # skip directories whose name doesn't match a known job type

      Dir.glob(type_path.join("*.md")).sort.each do |md_path|
        code = File.basename(md_path, ".md")
        content = File.read(md_path)

        short_name = content[/^#\s*Variant:\s*(.+?)\s*$/, 1] || code.tr("_", " ").capitalize
        description = content[/\*\*Authoring hypothesis:\*\*\s*(.+?)\s*$/, 1]

        record = Scenario.find_or_initialize_by(job_type: job_type, code: code)
        was_new = record.new_record?
        record.short_name = short_name if record.short_name.blank?
        record.description = description if record.description.blank?
        record.save!

        if was_new
          @result.scenarios_created += 1
          log "  created scenario: #{job_type.type_code}/#{code}"
        else
          @result.scenarios_existing += 1
        end
      end
    end
  end

  def load_pdf_extraction_setup
    model = Model.find_or_create_by!(model_id: PDF_EXTRACTION_MODEL[:model_id]) do |m|
      m.name     = PDF_EXTRACTION_MODEL[:name]
      m.provider = PDF_EXTRACTION_MODEL[:provider]
    end
    PdfProcessingRevision.find_or_create_by!(instructions: PDF_EXTRACTION_PROMPT) do |r|
      r.model = model
    end
  end

  def load_campaigns
    Scenario.includes(:job_type).find_each do |scenario|
      md_path = CAMPAIGNS_ROOT.join(scenario.job_type.type_code, "#{scenario.code}.md")
      next unless File.exist?(md_path)

      content = File.read(md_path)
      campaign = ensure_campaign(scenario)
      ensure_campaign_steps(campaign, content)
    end
  end

  def ensure_campaign(scenario)
    campaign = Campaign.find_or_initialize_by(
      attributed_to_type: "Scenario", attributed_to_id: scenario.id
    )
    if campaign.new_record?
      campaign.assign_attributes(
        name: "#{scenario.job_type.name} — #{scenario.short_name}",
        status: :draft
      )
      campaign.save!
      @result.campaigns_created += 1
      log "  created campaign: #{scenario.job_type.type_code}/#{scenario.code}"
    else
      @result.campaigns_existing += 1
    end

    # Auto-curate the freshly-loaded campaign as the scenario's active
    # choice (Scenario#campaign_id, the belongs_to). Without this,
    # CampaignLauncher can't find a campaign to launch even though one
    # exists attributed to the scenario. Idempotent: only sets when
    # nil, so an admin who has manually picked a different attributed
    # campaign for an A/B test won't get overwritten on re-run.
    scenario.update!(campaign_id: campaign.id) if scenario.campaign_id.nil?

    campaign
  end

  # Each campaign needs an active revision so steps have a place to live
  # and the campaign launcher can pick something up. Creates revision 0
  # active on first load; subsequent runs reuse it. created_by_user falls
  # back to the first admin so the NOT NULL FK is satisfied — this is a
  # programmatic load, no operator is in the loop.
  def ensure_campaign_revision(campaign)
    revision = campaign.active_revision
    return revision if revision

    creator_id = User.where(is_admin: true).order(:id).pick(:id) || User.order(:id).pick(:id)
    raise "catalog:load needs at least one user to attribute the seeded revision to" if creator_id.nil?

    campaign.revisions.create!(
      revision_number:    0,
      status:             :active,
      created_by_user_id: creator_id
    )
  end

  def ensure_campaign_steps(campaign, content)
    revision = ensure_campaign_revision(campaign)
    offsets = parse_cadence_offsets(content)
    parse_step_blocks(content).each do |step_data|
      step = revision.steps.find_or_initialize_by(sequence_number: step_data[:sequence_number])
      if step.new_record?
        step.assign_attributes(
          campaign:         campaign,
          offset_min:       offsets[step_data[:sequence_number]] || 0,
          template_subject: step_data[:template_subject],
          template_body:    step_data[:template_body]
        )
        step.save!
        @result.steps_created += 1
      else
        @result.steps_existing += 1
      end
    end
  end

  # Cadence overview rows look like:
  #   | 1 | Hour 0 | 0 | Deliver the proposal ... |
  #   | 2 | Hour 4 | 4h | Add operational specificity ... |
  #   | 6 | Day 5 | 3d | Soft return ... |
  # Returns { 1 => 0, 2 => 240, ..., 6 => 7200 } in minutes.
  def parse_cadence_offsets(content)
    offsets = {}
    content.scan(/^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|/) do |num, timing|
      offsets[num.to_i] = timing_to_minutes(timing)
    end
    offsets
  end

  def timing_to_minutes(timing)
    case timing
    when /\bHour\s+(\d+)/i then Regexp.last_match(1).to_i * 60
    when /\bDay\s+(\d+)/i  then Regexp.last_match(1).to_i * 24 * 60
    else 0
    end
  end

  # Step blocks look like:
  #   ## Step 1
  #
  #   **Subject (post-prefix; engine prepends `[{job_number}]` at send time):**
  #
  #   `Water cleanup at {property_address_short}`
  #
  #   **Body:**
  #
  #   The proposal for the water cleanup at {property_address_short} ...
  #
  #   ---
  def parse_step_blocks(content)
    blocks = content.split(/^## Step /).drop(1)
    blocks.filter_map do |block|
      num = block[/\A(\d+)/, 1]&.to_i
      next unless num

      subject = extract_subject(block)
      body = extract_body(block)
      next unless subject && body

      { sequence_number: num, template_subject: subject, template_body: body }
    end
  end

  def extract_subject(block)
    # Subject sits on its own line below the **Subject ...** heading,
    # usually backtick-wrapped. Tolerate either form.
    raw = block[/\*\*Subject[^*]*\*\*\s*\n+(.+?)\n/m, 1]
    return nil unless raw
    raw = raw.strip
    raw.start_with?("`") && raw.end_with?("`") ? raw[1..-2] : raw
  end

  def extract_body(block)
    # Body is everything between **Body:** and the next horizontal rule
    # (--- on its own line) or end of block. Some authored files put the
    # body on the same line as the heading (no newline between), others
    # leave a blank line — \s* handles both.
    block[/\*\*Body:\*\*\s*(.+?)(?:^---\s*$|\z)/m, 1]&.strip
  end

  def log(message)
    @io.puts "[catalog:load] #{message}"
  end
end
