# CLAUDE.md

## Conventions

See [CONVENTIONS.md](CONVENTIONS.md) for project-wide rules of thumb (e.g., all controllers require an authenticated user). Follow them unless an exception is documented there.

## Running Rails commands

Docker Compose is always running our environment in the background. To run tests
or any other Rails / bundle command, prefix with:

```bash
docker-compose exec web bundle exec
```

Examples:

```bash
docker-compose exec web bundle exec rails db:test:prepare test test:system
docker-compose exec web bundle exec rails test
docker-compose exec web bundle exec rails test:system
docker-compose exec web bundle exec rails db:migrate
docker-compose exec web bundle exec rails console
```

## Testing policy

- **Always run the full test suite before considering any task complete.** Do not report a task as done if tests are failing.
- **The full suite is three runs — all three must pass:**

  ```bash
  docker-compose exec web bundle exec rails db:test:prepare test   # minitest (unit / controller / integration)
  docker-compose exec web bundle exec rails test:system            # system tests
  docker-compose exec web bundle exec cucumber                     # cucumber feature suite
  ```

- **If tests fail, update the application code to make them pass** — do not weaken assertions, skip tests, or delete tests to make the suite green. Fix the underlying issue.
- **Write unit tests for every controller you add or change, covering each branch of its logic** — unauthenticated access, empty-state, scoped reads/writes, admin paths, error cases. Don't ship a controller without tests.
- **The Cucumber feature suite mirrors the user guide.** `features/*.feature` track [docs/user-guide/](docs/user-guide/) §1–§4 — when a feature ships, changes, or is removed, update the matching `.feature` file and its step definitions in the same change. See [ADR 0004](docs/adr/0004-cucumber-feature-suite-mirrors-the-user-guide.md) for what the feature suite is for and what belongs in it versus minitest.

## Commit policy

- After completing a significant task, stage all changed files, craft a commit message describing the change, and commit to git.

## User guide maintenance

The operator-facing user guide lives in [docs/user-guide/](docs/user-guide/) and is hosted on GitHub. Treat it as a deliverable, not a side artifact.

### Audience

§1, §2, §3, and §4 are written **for the people using the product**, not the people building it. The reader is a restoration-business owner or office manager — they have never read the codebase, do not know what a model or a controller is, and do not care. They came here to do a job and want to know which buttons to press, what to expect to see, and what to do when something goes wrong.

§0 is the only infra-facing section. It is written for whoever deploys the app to Heroku. Technical references (env vars, add-on names, Procfile, source files) belong here.

### What does NOT belong in §1–§4 user prose

Do not write any of the following in user-facing sections, even as parenthetical asides or footnotes — they are signals that the writer slipped into developer-mode:

- **Model class names**: `JobProposal`, `CampaignInstance`, `CampaignStepInstance`, `ApplicationMailbox`, `Scenario`, etc.
- **Controller / job / service names**: `JobProposalProcessor`, `CampaignSweepJob`, `GmailSender`, `EmailDelegationsController`.
- **Column or attribute names**: `scenario_key`, `pipeline_stage`, `status_overlay`, `last_reply`, `gmail_thread_id`, `email_delivery_status`, `is_active`, `parent_id`.
- **Enum values as code**: `:active`, `:paused`, `stopped_on_reply`, `customer_waiting`. Use the operator-facing label instead ("paused", "waiting on the customer", "delivery problem").
- **Env vars and infrastructure terms**: `GEMINI_API_KEY`, `RAILS_ENV`, JSONB, transaction, FK, polymorphic, find_or_create_by.
- **PRD / SPEC document numbers** as authority citations ("per SPEC-09 §6.4"). The user guide is what an operator reads; if a PRD constraint is operator-relevant, restate it in plain English.
- **Rails-console escape hatches**. If the only way to do something is `rails console`, the feature is not yet user-facing — leave the section blank or describe the planned UX as "not yet built" (see §4e).

### What DOES belong in §1–§4

- **The exact sidebar item, page, button, or link the reader clicks** (e.g. *Sidebar → Job Proposals*, *Click + New job*, *Open the Manage activations link at top right*).
- **What the page looks like and where things sit** (e.g. *the Invite a user card on the right*, *a green badge appears next to the row*).
- **What the reader will see happen** (e.g. *the new row appears at the top of the list*, *the email goes out within 5 minutes*).
- **The domain words the product itself uses**: job type, scenario, campaign, proposal, application mailbox, activation, tenant, organization, location.
- **Practical follow-ups for the common failure modes** — phrased as "if X looks wrong, do Y," not as "the foo column is set to bar."

### Pre-merge checklist

Before considering a user-guide change done:

1. **`grep -nE 'JobProposal|CampaignInstance|ApplicationMailbox|scenario_key|pipeline_stage|status_overlay|gmail_thread_id|email_delivery_status|JSONB|find_or_create_by|polymorphic' docs/user-guide/0[1-4]*`** — should return **nothing**. Any hit is technical leakage in operator prose.
2. **Cross-references resolve.** Section anchors follow GitHub's slug rules (period stripped from `1.5` → `15`, ` & ` and ` / ` collapse to `--`). When a section is renumbered or renamed, update every link that pointed at it. Sweep with `grep -nE '§[0-9]' docs/user-guide/`.
3. **Update the user guide in the same change as any feature that ships, changes, or is removed.**
4. **Leave placeholders visible for un-built features** (see §4e). Do not invent UX that isn't built.
