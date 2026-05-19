# ADR 0004: The Cucumber feature suite mirrors the operator user guide

- **Status:** Accepted
- **Date:** 2026-05-18
- **Deciders:** Mike (engineering)
- **Applies to:** `features/`, `docs/user-guide/`

## Context

The repo has three test layers: minitest (`test/` — unit, controller, integration), system tests (`test/system/`), and a Cucumber feature suite (`features/`). Minitest carries the bulk of the coverage and is actively maintained. The Cucumber suite is a different kind of artifact, and its purpose had never been written down.

Without a stated purpose, it rotted. By May 2026 the feature suite had drifted off the app: `features/support/world.rb` still built records through the long-removed `Organization` / `OrganizationalMember` models, so every tenant-user scenario crashed in setup, and 61 of 108 steps were undefined stubs. It was not in CI, so nothing caught the drift. A suite with no stated job, and no gate, decays to noise.

At the same time, the operator-facing user guide in `docs/user-guide/` is treated as a deliverable (see `CLAUDE.md` → *User guide maintenance*). §1–§4 describe, in plain language, the exact workflows an operator performs: setting up the catalog, onboarding a tenant, onboarding a user, and running campaigns. That prose has no automated check that it still matches the app — a button can be renamed, a flow can change, and the guide silently goes stale.

These two problems have one answer. The guide needs an executable check; the Cucumber suite needs a job. Pointing them at each other solves both.

## Decision

**The Cucumber feature suite is the executable mirror of the operator user guide. Its job is to verify that the workflows documented in `docs/user-guide/` §1–§4 still work as written — nothing more, nothing less.**

### 1. One feature file per user-guide section

`features/*.feature` map one-to-one onto the guide's operator sections:

| Feature file | User guide section |
|---|---|
| `job_types_and_campaigns.feature` | §1 — Set up job types and campaigns |
| `tenant_onboarding.feature` | §2 — Onboarding a tenant |
| `user_onboarding_and_account.feature` | §3 — User onboarding & account |
| `campaign_maintenance.feature` | §4 — Campaign maintenance |

Each feature file's header comment names the guide file it mirrors. Each scenario name is prefixed with the guide subsection it covers (e.g. `§4c Pausing and resuming a campaign`).

### 2. Scenarios test documented operator workflows, not exhaustive branches

A scenario exists because the guide tells an operator to do something. Edge cases, error branches, unauthenticated access, scoping rules, and internal-state invariants are **minitest's** job — keep writing controller tests for every branch (`CLAUDE.md` → *Testing policy*). Cucumber covers the happy-path workflow a human is told to follow. Scenario count is not a coverage metric; do not pad it.

### 3. The guide, the feature file, and the step definitions move together

When a feature ships, changes, or is removed, the same change updates: the user-guide section, the matching `.feature` file, and its step definitions. A workflow change that lands without touching `features/` is incomplete. This is the same lockstep rule the guide already carries for the guide itself — extended one layer out.

The **user guide is the source of truth for operator behavior**; the feature file is the executable assertion of it. When they disagree, the guide wins and the feature file is corrected — exactly as ADR 0001 makes the PRD win over its tracking issues.

### 4. The suite runs `rack_test`, and never touches external services

The application container ships no browser, and the app's own system tests are `driven_by :rack_test`. The feature suite follows suit: no JavaScript driver, no Selenium. Flows that only work through JavaScript (e.g. a drag-and-drop upload) are exercised through their non-JS form fallback.

The support layer (`features/support/`) guarantees no scenario reaches a real external API — `GmailSender` is stubbed inert, and `ApplicationMailbox` / `APP_HOST` are set up locally so the app considers itself send-ready without credentials.

### 5. The feature suite is part of the full test suite and runs in CI

The "full test suite" is three runs — minitest, system tests, and Cucumber — and all three must pass before a task is done. A `cucumber` job in `.github/workflows/ci.yml` enforces the suite on every push and pull request, so drift is caught the next time it happens.

## Consequences

**Positive:**

- The user guide gets an automated gate. A workflow that no longer matches the guide fails CI, instead of silently rotting until an operator hits it.
- A new contributor can read a guide section and the matching `.feature` file side by side — the prose and its executable form reinforce each other.
- The Cucumber suite has a clear, bounded job, so it stays small and fast and doesn't compete with minitest.
- Drift like the May 2026 breakage can't recur unnoticed: CI runs the suite, and the lockstep rule keeps the feature files current.

**Negative:**

- A workflow change now touches up to three places — the guide section, the `.feature` file, and the step definitions. We accept this for the same reason ADR 0001 accepts PRD/issue dual-maintenance: the alternative (a guide with no executable check) is worse.
- `rack_test` means a genuinely JavaScript-only workflow can't be covered end-to-end through the browser. Scenarios fall back to the non-JS path; a truly JS-gated flow is left to a system test or a deliberately parked `@pending` scenario.

**Neutral:**

- Scenario count is not a coverage number and should not be reported as one. Deep internal-state assertions (campaign-instance lifecycle, merge-field rendering, sweep behavior) belong in minitest; the absence of such a scenario in `features/` is by design.
- Adopting a JavaScript driver (headless Chrome via Selenium or cuprite) would let the suite cover JS-only flows directly. Not done — it needs a browser in the container. Flagged as a possible follow-up if a JS-only operator workflow ever becomes load-bearing.

## Alternatives considered

1. **Exhaustive Cucumber coverage — a scenario per controller branch.** Rejected: that is minitest's job, where it is faster and cheaper. Mirroring branch coverage in Gherkin produces a slow, bloated suite and two maintenance surfaces for the same assertion.
2. **Delete the Cucumber suite; rely on minitest plus system tests.** Rejected: the user guide is a deliverable, and a deliverable with no automated check goes stale. The feature suite is that check.
3. **Keep Cucumber, but with no stated relationship to the guide.** Rejected: this is the state that produced the May 2026 rot. An unscoped suite with no job decays.
4. **A JavaScript driver from day one.** Rejected for now: no browser in the container, and the app's own system tests are `rack_test`. Revisit only when a JS-only operator workflow must be covered.
