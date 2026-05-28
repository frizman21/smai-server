# 0. Production Setup (Heroku)

> Audience: **infrastructure / system admin**.
>
> Run this checklist once, before any of the operator-facing instructions in §1–§4. It assumes a fresh Heroku app and a clean GitHub remote.

This is not a step-by-step Heroku tutorial — it is the list of resources, config vars, and verifications specific to SMAI. If you are new to Heroku, the [Getting Started with Ruby on Rails](https://devcenter.heroku.com/articles/getting-started-with-rails7) article covers the underlying mechanics.

---

## 0.1 External services to provision

Before touching Heroku, get accounts and credentials for the four external services SMAI talks to:

| Service | Why we need it | What you'll grab |
|---|---|---|
| **Google Cloud Storage** *(preferred)* or **AWS S3** | Active Storage for uploaded job-proposal files in production. | GCS: project id, bucket name, service-account JSON keyfile. S3: access key id, secret access key, region, bucket name. See §0.1a for GCS setup. |
| **Google Cloud OAuth client** | Application mailbox uses Gmail send-on-behalf-of. Required for outbound invitation emails and campaign sends. | Client id, client secret, plus an OAuth callback URL registered for your Heroku domain. |
| **Google AI Studio (Gemini)** | PDF extraction for uploaded estimates by `JobProposalProcessor`. | API key. |
| **Sentry** | Error monitoring in production / staging. | DSN. (A default DSN is hard-coded as a fallback; override in production.) |

Notes on Google OAuth:

1. Create an OAuth 2.0 client of type **Web application** in Google Cloud Console.
2. Add the scope `https://www.googleapis.com/auth/gmail.send` (the app uses `email profile gmail.send` per `config/initializers/omniauth.rb`).
3. Add the authorized redirect URI: `https://<your-heroku-domain>/auth/google_oauth2/callback`. Register a custom domain redirect too if you set one up in §0.6.
4. **Add every tester to the OAuth test-user list, one at a time.** While the OAuth consent screen is in **Testing** mode, only Google accounts on this allowlist can complete the consent flow — anyone else gets blocked with `Error 403: access_denied`. Open the project's [APIs & Services → OAuth consent screen → **Audience**](https://console.cloud.google.com/auth/audience) page (make sure your project is selected in the top-left picker), scroll to **Test users**, and click **+ Add users**. Google's UI does not support bulk paste; expect to add each address on its own. Plan accordingly during onboarding — tester sign-ins will fail until their address is on the list, and there's a Google-imposed cap of 100 test users while in Testing mode. The list can be removed in one shot by publishing the OAuth consent screen to **Production**, which requires Google's verification review.

## 0.1a Provision Google Cloud Storage (preferred)

GCS is the recommended Active Storage backend. The app supports S3 too — leave this section and skip ahead to §0.4 if you'd rather use AWS — but GCS keeps everything inside the same vendor as the OAuth client and Gemini API key, which simplifies billing and IAM.

You'll need a Google Cloud project with billing attached. If you don't have one yet, create it at the [Google Cloud Console](https://console.cloud.google.com/) (top-left project picker → **New Project**).

**Step 1 — Create the bucket.** Walkthrough: [Cloud Storage: Create buckets](https://cloud.google.com/storage/docs/creating-buckets).

```bash
# From your machine, with the gcloud CLI signed in:
gcloud storage buckets create gs://<your-bucket-name> \
  --project=<your-project-id> \
  --location=us-central1 \
  --uniform-bucket-level-access
```

Notes:

- Pick the location closest to your Heroku region (Heroku Common Runtime is `us` by default → use `us-central1` or `us-east1`).
- `--uniform-bucket-level-access` simplifies IAM: permissions are managed at the bucket level, not per-object.
- Do **not** make the bucket public. Active Storage signs short-lived URLs for any browser-facing reads.

**Step 2 — Create a service account.** Walkthrough: [IAM: Create service accounts](https://cloud.google.com/iam/docs/service-accounts-create).

```bash
gcloud iam service-accounts create smai-storage \
  --project=<your-project-id> \
  --display-name="SMAI Active Storage"
```

**Step 3 — Grant the service account access to the bucket.** Use `roles/storage.objectAdmin` (read + write objects within the bucket) — narrower than the project-wide `roles/storage.admin`.

```bash
gcloud storage buckets add-iam-policy-binding gs://<your-bucket-name> \
  --member="serviceAccount:smai-storage@<your-project-id>.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

**Step 4 — Create and download a JSON keyfile.** Walkthrough: [IAM: Create and delete service-account keys](https://cloud.google.com/iam/docs/keys-create-delete).

```bash
gcloud iam service-accounts keys create ./gcs-keyfile.json \
  --iam-account=smai-storage@<your-project-id>.iam.gserviceaccount.com
```

This keyfile is the credential. Treat it like a password — do not commit it. You will paste its contents into the `GCS_CREDENTIALS` Heroku config var in §0.4 and then delete the local copy.

**Local development (optional).** If you'd rather not keep `GCS_CREDENTIALS` in your local `.env`, run `gcloud auth application-default login` once. The app's GCS initializer leaves Application Default Credentials alone when `GCS_CREDENTIALS` is unset, so the gcloud CLI's stored credential takes over for development.

## 0.2 Create the Heroku app and pick a stack

```bash
heroku create <app-name>                                    # ruby buildpack auto-detected
heroku stack:set heroku-24 -a <app-name>                    # current LTS as of writing
heroku labs:enable runtime-dyno-metadata -a <app-name>      # exposes HEROKU_APP_NAME etc.
```

The repo already ships:

- `Procfile` — defines `web`, `worker`, and a `release: bundle exec rails db:migrate` line that runs migrations on every deploy.
- `Dockerfile` — production image, ignored by Heroku's default buildpack flow.

## 0.3 Provision add-ons

```bash
# Postgres — sets DATABASE_URL automatically.
heroku addons:create heroku-postgresql:essential-0 -a <app-name>

# Redis (Heroku Key-Value Store) — sets REDIS_URL automatically; required by Sidekiq.
heroku addons:create heroku-redis:mini -a <app-name>
```

Sidekiq reads `REDIS_URL` directly from the environment; no extra wiring needed beyond the add-on. The Sidekiq cron schedule lives in `config/sidekiq_cron.yml` and is loaded by `config/initializers/sidekiq.rb` on worker boot — `CampaignSweepJob` runs every five minutes and is the heartbeat for outbound sends.

> **Heroku Key-Value Store TLS.** The add-on sets `REDIS_URL=rediss://...` with a self-signed certificate. The Ruby Redis client rejects this by default with `RedisClient::CannotConnectError: certificate verify failed (self-signed certificate in certificate chain)`, which surfaces from `/sidekiq` and from any job enqueue. `config/initializers/sidekiq.rb` and `config/cable.yml` both apply `ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }` when the URL is `rediss://` — this is the documented Heroku workaround. Local `redis://localhost` connections stay strict.

## 0.4 Set required config vars

The app's `ApplicationHelper::REQUIRED_ENV_VARS` is the authoritative list — missing values are surfaced as a banner inside the app on every admin screen. Mirror it to Heroku:

```bash
# GCS variant (preferred). GCS_CREDENTIALS is the entire JSON keyfile content
# from §0.1a Step 4 — paste the file's contents inline.
heroku config:set \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  APP_HOST=<your-heroku-domain> \
  GEMINI_API_KEY=… \
  GCS_PROJECT=<your-project-id> \
  GCS_BUCKET=<your-bucket-name> \
  GCS_CREDENTIALS="$(cat ./gcs-keyfile.json)" \
  GOOGLE_CLIENT_ID=… \
  GOOGLE_CLIENT_SECRET=… \
  SENTRY_DSN=… \
  -a <app-name>

# AWS variant (alternative). Use this block instead of the GCS lines if you
# went with S3. Do not set both; GCS_BUCKET takes precedence.
# heroku config:set \
#   AWS_ACCESS_KEY_ID=… \
#   AWS_SECRET_ACCESS_KEY=… \
#   AWS_REGION=us-east-1 \
#   AWS_BUCKET=… \
#   -a <app-name>
```

After setting `GCS_CREDENTIALS`, **delete the local `./gcs-keyfile.json`**. Heroku has the only copy now.

Notes:

- `RAILS_MASTER_KEY` decrypts `config/credentials.yml.enc`. If it's missing, the app boots but cannot read encrypted credentials.
- `DATABASE_URL` and `REDIS_URL` are set by their add-ons — do not set them manually.
- `RAILS_ENV=production`, `RACK_ENV=production`, `SECRET_KEY_BASE` are managed by the buildpack — do not override.
- `WEB_CONCURRENCY` defaults to a sensible value based on dyno size; tune later if needed.
- The storage backend is selected at boot from these env vars: GCS when `GCS_BUCKET` is set, S3 when `AWS_BUCKET` is set, local disk otherwise. Setting both makes GCS win — easier to migrate later by removing the AWS values once the GCS bucket is verified.
- **Optional: `TEST_TO_EMAIL`.** Outbound mail safety gate read by `app/jobs/campaign_sweep_job.rb`. When set, every campaign email is redirected to that address instead of the customer's. Leave it unset in real production. Set it temporarily (e.g. `TEST_TO_EMAIL=qa@yourcompany.com`) for staging, smoke-testing a deploy, or training. Devise mailers (password reset, account confirmations) are not affected by this gate.

## 0.5 Production URL host

Outbound invitation and password-reset emails embed absolute URLs that come from `config.action_mailer.default_url_options[:host]` in `config/environments/production.rb`. The host is read from the `APP_HOST` env var:

```ruby
# config/environments/production.rb
config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost"), protocol: "https" }
```

If `APP_HOST` is unset, the app boots with a `localhost` fallback so a deploy isn't blocked, but the resulting mailer links would be broken. The in-app missing-env banner surfaces `APP_HOST` as missing on every admin screen in non-development environments, so a fresh deploy gets flagged loudly before any mail goes out. Set `APP_HOST` to your Heroku domain (or your custom domain from §0.6) — it's already in the §0.4 `heroku config:set` block. Staging and production each carry their own value, no code edits required. Development doesn't need `APP_HOST` at all; the dev mailer host comes from Rails' default URL options, not this var.

## 0.5a (Optional) Twilio text-message notifications

When a customer replies to a campaign email, the proposal owner gets a text message with the customer's name, address, phone, DASH number, and a tap-through link into the Gmail conversation. The send is gated by env vars — if these are unset, the feature is quietly off and nothing else in the app changes.

Set up a Twilio account, pick a from-number, and set:

```bash
heroku config:set \
  TWILIO_ACCOUNT_SID=AC… \
  TWILIO_AUTH_TOKEN=… \
  TWILIO_FROM_NUMBER=+15555550123 \
  -a <app-name>
```

Notes:

- The app uses a provider-agnostic `SmsSender` that picks the first configured provider by env-var presence. Twilio is the only provider today; the abstraction is in place so a swap won't require touching the reply path.
- `TEST_TO_PHONE` (optional) is the SMS counterpart of `TEST_TO_EMAIL`. When set in any environment, every outbound SMS is redirected to that number instead of the real recipient — use this in staging or for a smoke test before pointing real Twilio sends at teammates' phones.
- For SMS to reach a given user, that user's profile must have a `phone number` filled in. The job no-ops silently for owners without one.
- The deep-link to Gmail in the SMS body goes through the app's own short-link redirect (`/r/<code>`), so the message stays well under the 160-character SMS limit.

The Integrations admin page shows a **Text messaging (Twilio)** row with three states: **OK** when all three vars are set; **Warning** when the config is partial; **Missing** when none are set.

## 0.6 (Optional) Custom domain and SSL

```bash
heroku domains:add app.example.com -a <app-name>
# Follow the DNS_TARGET output to add a CNAME at your registrar.
```

Heroku provisions ACM certificates automatically once the DNS resolves. Update Google's OAuth redirect URI (§0.1) so the custom domain works at sign-in time.

## 0.7 First deploy

```bash
git push heroku main
```

The release phase runs `bundle exec rails db:migrate` automatically.

## 0.7a Load the catalog (job types and scenarios)

Tenants can't activate anything until the system-wide catalog of job types and scenarios is loaded. Run the catalog rake task once after the first deploy:

```bash
heroku run rails catalog:load -a <app-name>
```

Expected output:

```
[catalog:load] Loading restoration job types...
[catalog:load]   created job type: general_cleaning
[catalog:load]   created job type: mold_remediation
[catalog:load]   created job type: structural_cleaning
[catalog:load]   created job type: trauma_biohazard
[catalog:load]   created job type: water_mitigation
[catalog:load] Loading scenarios from docs/campaigns/v1-output...
[catalog:load]   created scenario: general_cleaning/commercial_deep_clean
…
[catalog:load] Done. 5 job types (5 new, 0 existing); 17 scenarios (17 new, 0 existing).
```

The task is idempotent — re-running it after the first load reports everything as `existing` and changes nothing. It also preserves any hand-edits an admin has made to a scenario's `short_name` or `description` from inside the app.

> **Do not run `rails db:seed` in production.** The dev seed file creates a demo tenant, demo users with shared default passwords, and demo job proposals on top of the catalog data — none of which belong in a real install. `catalog:load` is the production-safe subset.

## 0.7b Create the first admin user

The seed file creates `admin@example.com` (password `Password1`) for development convenience. Production should not use those credentials. Create a real admin user from the Rails console:

```bash
heroku run rails console -a <app-name>
> User.create!(email: "you@example.com", password: "<long random>", password_confirmation: "<long random>", is_admin: true, is_pending: false)
```

If the seed-style admin somehow exists in production (e.g. someone ran `db:seed` by mistake), rotate or destroy it:

```ruby
> User.find_by(email: "admin@example.com")&.update!(password: "<long random>", password_confirmation: "<long random>")
```

## 0.8 Scale dynos

```bash
heroku ps:scale web=1 worker=1 -a <app-name>
```

The `worker` dyno runs Sidekiq, including the `CampaignSweepJob` cron entry. If `worker` is at zero, no campaign emails will go out — verify with `heroku ps -a <app-name>` after the first deploy.

## 0.9 Connect the application mailbox

The application mailbox is the Google account SMAI uses to send all outbound mail (invitations, campaign step emails). Connect it from inside the app, not from Heroku:

1. Sign in as `admin@example.com` (or the rotated admin account from §0.7).
2. Navigate to **Admin → Mailbox**.
3. Click **Connect a Gmail account**.
4. Complete the OAuth consent flow with the Google account that should be the system sender.

The OAuth tokens are stored on the singleton `ApplicationMailbox` row; the Connect button is disabled until `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` are set (§0.4).

## 0.10 Verification

After the deploy is up, **Admin → Integrations** is the one-page health check you can lean on. It lists every external dependency with two columns:

- **Configured** — fast, derived from env vars and DB rows. Tells you whether the keys / connections are present.
- **Last live check** — populated by clicking **Re-check now** at the top of the page. Runs a real call against the service (Gmail token refresh, Gemini `models.list`, storage bucket reachability, Redis `PING`) and stores the result. The connectivity probe does **not** run on a schedule — refresh manually whenever you want a current answer.

States in either column:

- **OK** — fully configured / connected.
- **Warning** — works but not optimal (e.g. Sentry is falling back to the bundled default DSN, or storage is partially configured).
- **Missing** — not configured or unreachable; the feature it gates won't work until you fix it.

Walk through this short checklist before letting tenant users in:

1. `https://<host>/up` returns 200.
2. `https://<host>/users/sign_in` loads and you can sign in as the admin.
3. **Admin → Integrations** shows zero **Missing** rows. Address any **Warning** rows you care about.
4. **Admin → Mailbox** shows the connected account email (also visible on the Integrations page).
5. `heroku logs --tail -a <app-name>` shows the campaign sweep firing every five minutes from the worker dyno.
6. Upload a small PDF on a test tenant and confirm the customer fields populate after a few seconds.

When all six pass, hand the URL off and start with [§1](01-job-types-and-campaigns.md) for the catalog, [§2](02-tenant-onboarding.md) for the first tenant, and [§3](03-user-onboarding-and-account.md) for the first invited user.
