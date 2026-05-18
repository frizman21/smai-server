# 5. Originator Training Checklist

> Audience: **trainer** — the account admin or experienced operator running a hands-on session with a new originator.
>
> An originator is an operator tied to a single location. Their day is: upload a job, confirm what the system pulled out of the estimate, let the campaign run, watch the Jobs board, and step in when a customer replies or a deal closes. This is a run-sheet for walking a new originator through all of that in one sitting — roughly 45 minutes.
>
> Sections [§3](03-user-onboarding-and-account.md) and [§4](04-campaign-maintenance.md) are the originator's own reference once training is over. This page is the script *you* follow during the session, with a sign-off list at the end.

How to use this page: each step is **demo it** (you drive, narrating), **hand it over** (the trainee does it on their own screen), then **verify** (you confirm they can). Don't move on until the verify line is true.

---

## 5.1 Before the session — trainer prep

Do all of this *before* the trainee sits down. A session stalls fast if the invite hasn't arrived or there's nothing to upload.

- [ ] **Invitation sent** to the trainee's email address, with the correct **location** chosen and **Is Account Admin** left unchecked (see [§3.6](03-user-onboarding-and-account.md#36-inviting-teammates)). The link is good for seven days — send it close to the session.
- [ ] **Application mailbox is connected and healthy.** Open **Platform Admin → Integrations** and confirm the mailbox row is not red. If it is, no email goes out and the upload demo will look broken — fix it first ([§3.5](03-user-onboarding-and-account.md#35-connected-email-accounts)).
- [ ] **At least one job type and scenario are activated** for the trainee's tenant, and the scenario has an approved campaign wired to it ([§2.5](02-tenant-onboarding.md#25-activate-job-types-and-scenarios), [§1.6](01-job-types-and-campaigns.md#16-wire-the-campaign-back-to-its-scenario)). Without this, an upload files the job but never starts a campaign — fine to *mention* as an edge case, bad as the main demo.
- [ ] **A sample PDF estimate** ready to upload during the session. Use a realistic but disposable file — the customer on it will receive real campaign email unless you mark the job lost afterward.
- [ ] Decide whether you'll **mark the demo job lost** at the end so the sample customer stops receiving email. Plan to.

---

## 5.2 First sign-in and account setup — ~10 min

- [ ] **Demo / hand over: accept the invitation.** Have the trainee open the invite email and click the link. They land on a sign-up page with their email pre-filled; they pick a password and submit. Their company and location are set for them.
- [ ] **Point out where they land.** Originators skip the home page and go straight to **Needs Attention** — explain that this is their daily starting point: the jobs that need a human today.
- [ ] **Hand over: fill in the profile.** Top-right menu → **Profile** → **Edit**. They set first name, last name, title, and phone.
  - Stress the *why*: their **name and title appear on the From line and signature of every campaign email** the system sends for their jobs. A blank name means customers see an email address instead.
- [ ] **Show the password tools.** Point out **Change password** in the top-right menu, and the **Forgot your password?** link on the sign-in page, so they know both exist before they need them.
- [ ] **Mention, don't dwell:** the **Email sending** card on the profile lets them connect a personal Google account, but it isn't used for sending today — they can ignore it.
- [ ] **Verify:** the trainee is signed in, their profile shows a real name and title, and they can describe what Needs Attention is for.

---

## 5.3 Orientation: the Jobs board — ~5 min

- [ ] **Demo: Sidebar → Jobs.** Explain this is their operating board. An originator sees only jobs at their own location.
- [ ] **Walk one card top to bottom:** customer name and proposal value in bold, address as the subtitle, a footer line with job type, and the **action button** on the right that tells them what to do next.
- [ ] **Walk the filter bar:** search (customer name, address, reference), status (new / open / closed), and the owner / created-by filters.
- [ ] **Preview the action buttons** so they aren't surprised later — *View job*, *Open in Gmail*, *Fix delivery issue*, *Resume campaign*, *Review*. You'll trigger some of these for real in §5.5.
- [ ] **Verify:** the trainee can find the Jobs board and explain what the action button on a card is telling them.

---

## 5.4 The core workflow: upload a job — ~15 min

This is the heart of the role. Have the trainee do it for real with the sample PDF.

- [ ] **Hand over: start a new job.** **Sidebar → Jobs → New Job** (or the **+** in the top navbar). Drop the sample PDF on the zone, click **Upload**, and wait — AI extraction takes a few seconds, so don't click twice.
- [ ] **Walk the Confirm page together.** The system previews everything it pulled from the PDF — customer title, name, email, address; job type and scenario; proposal value; internal reference; DASH number if the tenant uses it. Have the trainee read every field and correct anything wrong.
- [ ] **Teach the rule that matters most:** *confirm before you approve.* This is the only chance to fix the data before the first email goes out, and approving locks the job for editing.
- [ ] **Show the Owner field.** If they upload on behalf of a teammate, they reassign ownership here — the owner's name is what customers see on the From line.
- [ ] **Note the Location field** is read-only for originators (it's whatever location they belong to); account admins can change it.
- [ ] **If the tenant uses DASH numbers,** point out that the DASH job number is required before approving and gets prefixed onto every email subject.
- [ ] **Hand over: approve.** Click **Approve Proposal Content**. The job is filed, the campaign for the chosen scenario starts, and the first email goes out on the admin's cadence.
- [ ] **Mention the edge cases** without demoing each: no scenario picked means the job is filed but no campaign starts; a job type not activated for the tenant means the job sits idle until an admin activates it; an upload error shows a red banner explaining the fix.
- [ ] **Verify:** the trainee has uploaded, confirmed, and approved a job end to end on their own, and can explain why the Confirm page is the last chance to fix data.

---

## 5.5 Monitoring and stepping in — ~10 min

Use the job the trainee just created to walk these.

- [ ] **Pausing a single job.** Open the job's detail page and show the **Pause** button in the top action bar. Explain *when*: the customer asked for a delay, or something (vacation, escrow, family emergency) means email should stop. The Jobs board row flips to **Resume campaign**.
- [ ] **Resuming.** Click **Resume campaign**. Warn them about the catch-up behavior — steps whose scheduled time fell *inside* a long pause will fire on the next sweep, not be skipped. After a long pause, resume only when the gap is small.
- [ ] **Customer replies.** Explain that when a customer replies, the system stops sending follow-ups and flags the job as **waiting on the customer**. The card's action button reads **Open in Gmail** — they click it, read the thread, and reply from their normal inbox.
- [ ] **Delivery problem.** If an email couldn't be delivered, the button reads **Fix delivery issue** — it opens the job's edit page to correct the customer's email. Tell them restarting a campaign from a delivery problem isn't built yet; for now they ask an admin.
- [ ] **Closing a job.** On the detail page, **Mark Won** is a single click. **Mark Lost** opens a dialog needing a loss reason (from a fixed list) and loss notes. Both can be undone with **Revert to in campaign**.
- [ ] **Verify:** the trainee can pause and resume a campaign, knows what to do when a customer replies, and can mark a job won or lost.

---

## 5.6 When something looks wrong

Cover these briefly so the trainee knows the difference between "I made a mistake" and "tell an admin."

- [ ] **Email has gone quiet across many jobs** — likely the application mailbox connection broke. This is an admin fix; the originator's job is to flag it ([§3.5](03-user-onboarding-and-account.md#35-connected-email-accounts)).
- [ ] **A job sits idle with no campaign** — the job type or scenario isn't activated for the tenant. Also an admin fix.
- [ ] **One job's data is wrong after approval** — the job is locked; they should tell whoever can correct it rather than re-uploading.

---

## 5.7 Wrap-up and sign-off

Close the session by confirming each line below. If any is not true, go back to the matching section before ending.

- [ ] The trainee **uploaded, confirmed, and approved at least one job** entirely on their own.
- [ ] Their **profile has a real name and title** that will appear on outbound email.
- [ ] They can **find the Jobs board, read a card, and explain the action buttons.**
- [ ] They can **pause and resume** a campaign and know the catch-up caveat.
- [ ] They know **what to do when a customer replies** and when to **mark a job won or lost.**
- [ ] They know **which problems are theirs to fix and which to escalate** to an admin.
- [ ] Point them at [§3](03-user-onboarding-and-account.md) and [§4](04-campaign-maintenance.md) as their reference after today.
- [ ] Show them the **"Suggesting changes"** link in the [guide README](README.md) so they can file an issue if a screen doesn't match the docs.
- [ ] **Clean up:** mark the demo job **lost** (or otherwise close it) so the sample customer stops receiving campaign email.
