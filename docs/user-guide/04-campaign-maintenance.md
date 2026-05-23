# 4. Campaign Maintenance

> Audience: **tenant user**.
>
> Day-to-day work happens against jobs. Each upload becomes a job (a "proposal" in product language), the system kicks off the right campaign, and you monitor and intervene from the Jobs index.

---

## 4a. Upload a job to start a campaign

1. **Sidebar → Jobs**, then **New Job** (top right). You can also use the **+** button in the top navbar from anywhere in the app. A drag-and-drop zone appears.
2. Drop your PDF estimate or proposal onto the zone, or click it to pick a file from your computer. The **Upload** button enables once a file is selected.
3. Click **Upload**. The button shows a progress message — large files plus AI extraction can take a few seconds, so don't click again.

You land on a **Confirm** page that previews everything the system pulled out of the PDF — the customer's title, name, email, and address; the job type and scenario; the proposal value; the internal reference; and (if your tenant requires it) the DASH job number. Read it over and fix anything that's wrong. When you're satisfied, click **Approve Proposal Content**. The job is filed and the campaign for the chosen scenario starts. The first email goes out on the cadence the admin set up for that campaign.

A few practical notes:

- **Confirm before you approve.** This is the only chance to correct the data before the first email goes out. Once you approve with a scenario picked, the campaign is in flight and the job is locked for editing.
- **Reassigning ownership.** If you're uploading on behalf of a teammate (e.g. an assistant uploading for a project manager), use the **Owner** field on the Confirm page to point the job at the right person before approving. The owner's name appears on the From line of every campaign email.
- **Reassigning location.** Account admins see an editable **Location** field; originators see the location as a read-only summary (whatever location they're assigned to is the one the job belongs to).
- **DASH job number required?** If your tenant has DASH numbering turned on, the **DASH job number** field is required before you can approve. Once set, that number is prefixed onto every campaign email subject so the conversation stays threaded in DASH.
- **No scenario yet?** You can save without one — the job is filed but no campaign starts. Pick a scenario later from the job's edit page when you're ready (note: once a campaign is running, you can't go back and change it).
- **Job type or scenario not activated for your tenant?** No campaign starts. The job is still saved, but it sits idle until your admin activates the matching job type and scenario for your tenant ([§2.5](02-tenant-onboarding.md#25-activate-job-types-and-scenarios)).
- **Upload error?** A red banner at the top of the page explains what went wrong (e.g. unreadable file, missing tenant assignment). Fix the listed issue and try again.

## 4b. The Jobs board

**Sidebar → Jobs** is your operating board. Each job is shown as a card. Originators see only jobs at their location; account admins see every job in the company.

**Filter the board** with the controls along the top:

- **Search** — customer name, address fragment, or internal reference.
- **Location** — narrow to a single office (account admins only).
- **Status** — *new* (just uploaded), *open* (campaign running), or *closed* (won or lost).
- **Owner** / **Created by** — narrow to a specific teammate.

**What each card shows:**

- **Customer name** and **proposal value** along the top of the card, in bold.
- **Address** as the main subtitle. Click anywhere on the card body to open the job's detail page.
- A footer line with the **location** (account admins only), the **job type**, and a status overlay if there's anything noteworthy (e.g. *paused*, *waiting on the customer*, *delivery issue*).
- An **action button** on the right telling you what to do next on this job. The button changes based on the job's state:
  - **View job** — the campaign is running normally, or the job is closed (won/lost). Opens the job's detail page.
  - **Open in Gmail** — the customer has replied. Opens the conversation in a new Gmail tab so you can read the full message and respond from your inbox.
  - **Fix delivery issue** — the campaign couldn't deliver an email (bad address, mailbox bounced). Opens the job's edit page so you can correct the customer's email.
  - **Resume campaign** — the campaign was paused. Click to resume; the next step picks up on the cadence.
  - **Review** — the job was uploaded but the Confirm page is still pending. Opens the Confirm page so you can finalize and approve it.

The job's detail page shows a **Customer** card, a **Job** card with status and pipeline stage, a **Campaign** card with each step's send status, an **Ownership** card (location, owner, who created it), and any uploaded files.

## 4c. Pausing & unpausing a campaign

> Pause a single job's campaign when the customer asks for a delay or you've learned something that should keep emails from going out (vacation, traveling, escrow, family emergency). Pause the campaign *template* — different action, admin-only ([§1.5](01-job-types-and-campaigns.md#15-approve-pause-and-edit-the-campaign)) — when the content itself needs a fix.

**Pausing.** Open the job's detail page and click **Pause** in the top action bar. The button is only there while the campaign is actively running — once you pause, all scheduled steps stop. The job's row on the **Jobs** board flips to a **Resume campaign** action.

**Resuming.** From the **Jobs** board, click **Resume campaign** on the paused row (the same button is also available on the job's detail page when the campaign is paused). The campaign goes back to running on the cadence the admin set up.

> *Note:* today, after a long pause, any campaign steps whose scheduled time fell inside the pause window will fire on the next sweep — not be retroactively skipped. If that's not what you want, hold off on resuming until the gap is small.

## 4d. Customer responds

When a customer replies to a campaign email, the system stops sending — no more follow-ups go out on that thread. The job is flagged as **waiting on the customer** so you can spot it on the board.

What you'll see on the **Jobs** board:

- The card's action button reads **Open in Gmail** — click it to jump straight to the conversation in a new tab and reply from your usual inbox.
- The most recent reply (sender, time, subject, and a short preview) appears on the job's detail page.

What to do:

1. **Click Open in Gmail** on the job's card. Read the full thread and respond.
2. **If the deal is decided**, mark the job won or lost ([§4e](#4e-marking-a-job-as-won--lost)).
3. **If the conversation should keep going** — the customer had a question, you've answered it, and you still want the automated follow-ups — open the job's detail page and click **Resume campaign** in the top action bar. The remaining steps pick back up on their cadence. The reply you just handled won't stop the campaign a second time; only a *new* reply will.

> *Waiting on the customer* is a hand-off, not an ending — the campaign is paused for you, not finished. Resume it whenever the job should go back to chasing a response.

> **Delivery problem instead of a reply?** If the campaign couldn't deliver an email (bad address, the customer's mailbox bounced it), the action button reads **Fix delivery issue**. Click it to open the job's edit page and correct the customer's email address. *Restarting the campaign from a delivery problem is not yet built* ([#117](https://github.com/frizman21/smai-server/issues/117)) — for now, ask an admin.

## 4e. Marking a job as won / lost

Open the job's detail page. Two buttons sit in the top action bar next to the page title:

- **Mark Won** — single click. The job's pipeline stage flips to *Won* and the campaign stops if it was still running.
- **Mark Lost** — opens a small dialog. Both fields are required:
  - **Loss reason** — pick one from a fixed dropdown: *Price too high*, *Went with competitor*, *Insurance issue*, *No response from customer*, *Timing / scheduling conflict*, or *Other*. The fixed list keeps loss data clean enough to slice in Analytics.
  - **Loss notes** — any context worth recording about why the deal didn't move forward.
  Click **Mark Lost** in the dialog to confirm.

Once a job is Won or Lost, those buttons are replaced by **Revert to in campaign** — useful if you clicked the wrong one. Reverting puts the job back into its prior state.
