# User Guide

This guide walks through the day-to-day operation of the product from two perspectives:

- **System admin** — owns the job types, scenarios, and campaigns, and onboards tenants.
- **Tenant user** — runs jobs, monitors the proposal status board, and handles customer replies.

The sections below are written in the order you would touch them when standing the system up for the first time. If you are joining an established install, jump to whichever section matches your role.

> [§0 Production Setup](00-production-setup.md) is a one-time prerequisite for all subsequent sections. Sections §1–§4 assume the app is already running on Heroku with all required config vars set and the application mailbox connected.

## Sections

| # | Section | Audience |
|---|---|---|
| 0 | [Production Setup (Heroku)](00-production-setup.md) | Infrastructure / system admin |
| 1 | [Set Up Job Types and Campaigns](01-job-types-and-campaigns.md) | System admin |
| 2 | [Onboarding a Tenant](02-tenant-onboarding.md) | System admin |
| 3 | [User Onboarding & Account Maintenance](03-user-onboarding-and-account.md) | Tenant user |
| 4 | [Campaign Maintenance](04-campaign-maintenance.md) | Tenant user |
| | &nbsp;&nbsp;4a. [Upload a job to start a campaign](04-campaign-maintenance.md#4a-upload-a-job-to-start-a-campaign) | |
| | &nbsp;&nbsp;4b. [The Jobs board](04-campaign-maintenance.md#4b-the-jobs-board) | |
| | &nbsp;&nbsp;4c. [Pausing & unpausing a campaign](04-campaign-maintenance.md#4c-pausing--unpausing-a-campaign) | |
| | &nbsp;&nbsp;4d. [Customer responds](04-campaign-maintenance.md#4d-customer-responds) | |
| | &nbsp;&nbsp;4e. [Marking a job as won / lost](04-campaign-maintenance.md#4e-marking-a-job-as-won--lost) | |
| 5 | [Originator Training Checklist](05-originator-training-checklist.md) | Trainer (account admin) |

## Conventions used in this guide

- **Paths** like `/admin/tenants` refer to the URL after your hostname (e.g. `https://app.example.com/admin/tenants`).
- **Admin-only** screens require a user with the system-admin flag set. Tenant users do not see the **Platform Admin** group in the sidebar.
- The seeded restoration job types (Water Mitigation, Mold Remediation, Structural Cleaning, General Cleaning, Trauma / Biohazard) are referenced by their `type_code` in templates and specs.

## Suggesting changes

Spotted something wrong, missing, or out of date? File a GitHub issue rather than editing the docs directly — that way the change can be discussed, scoped, and landed alongside any code adjustments it implies.

> [Open a new issue for the user guide →](https://github.com/frizman21/smai-server/issues/new?title=Docs%3A+user+guide+update&labels=user-guide&body=Section%3A+%28e.g.+%C2%A73.5+Connected+email+accounts%29%0AWhat%27s+wrong+or+missing%3A%0A%0ASuggested+change%3A%0A)

The link above prefills the title, the `user-guide` label, and a short body template (Section, What's wrong or missing, Suggested change).
