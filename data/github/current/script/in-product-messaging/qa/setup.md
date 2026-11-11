# In-Product Messaging — Shared Test Setup

> This file is read first by the browse skill before any per-nudge test file.

---

## Pre-flight (ALWAYS run this first)

**Every IPM `/qa` run must start from a known-good codespace state.** The qa
skill has historically just *printed* a "Local Setup Reminder" and left the
human to remember to re-seed; that has caused false-positive passes (stale code
on the codespace) and false-negative failures (notice-dismissal state leaking
between runs).

**The qa skill MUST execute the following command before any test run when
`TARGET_URL` contains `github.localhost`** (whether the user passed
`--domain http://github.localhost` directly or the codespace pool resolved to
that URL). This is not a reminder — it is the first concrete action of the
batch:

```bash
bash script/in-product-messaging/qa/prep-codespace.sh
```

The script:

1. Auto-detects the unique `Available` `github/github` codespace
   (override with `--codespace NAME` or `IPM_CODESPACE=NAME`).
2. Refuses to proceed if the codespace working tree is dirty.
3. `git fetch` + `git pull --ff-only` on the codespace's currently checked-out
   branch — so the codespace runs the same commit you've pushed locally.
4. Re-runs `script/in-product-messaging/setup` so notice dismissals,
   welcome-modal eligibility, backdated CB seats, etc. are freshly applied.

If the script exits non-zero, **stop and report the failure** — do not try to
run any tests against a codespace in an unknown state.

> **Local Setup Reminder:** Before and after this run, also remind the user to
> ensure `http://github.localhost` is reachable on their machine and that the
> codespace's port forwarding is healthy. The pre-flight script above handles
> the codespace's git + seed state, but not the dev's local hosts file or
> SSH tunnel.

---

## Directory structure

All test files live directly in the `qa/` directory:

```
qa/
  setup.md              ← this file (shared across all tests)
  run-parallel.sh       ← local parallel test runner (auto-discovers .md test files)
  nudge-test.mjs        ← shared Playwright script for visual nudge tests
  indicator-test.mjs    ← shared Playwright script for JSON API indicator tests
  notification-test.mjs ← shared Playwright script for notification settings toggle tests
  modal-test.mjs        ← shared Playwright script for the CCA onboarding modal (tabs + dropdown + CTAs + close)
  01-dfd-enable-cb.md   ← visual nudge test (uses nudge-test.mjs)
  ...
  17-nav-ent-new-tasks.md  ← API indicator test (uses indicator-test.mjs)
  18-nav-org-new-tasks.md  ← API indicator test (uses indicator-test.mjs)
  ...
  26-notification-settings.md     ← notification toggle test (uses notification-test.mjs)
  27-notification-org-opt-out.md  ← notification toggle test (uses notification-test.mjs)
  28-notification-ent-opt-out.md  ← notification toggle test (uses notification-test.mjs)
  ...
  31-cca-modal-cta-copilot.md  ← CCA onboarding modal test (uses modal-test.mjs)
  32-cca-modal-cta-agents.md   ← CCA onboarding modal test (uses modal-test.mjs)
  33-cca-modal-features.md     ← CCA onboarding modal test (uses modal-test.mjs)
  34-cca-modal-dismiss.md      ← CCA onboarding modal test (uses modal-test.mjs)
```

### How to run

#### Local (direct mode)

Use `run-parallel.sh` to run all tests locally with headless Chromium:

```bash
bash script/in-product-messaging/qa/run-parallel.sh [--parallel 8] [--domain http://github.localhost] [--test name1,name2]
```

The script dynamically parses all `[0-9][0-9]-*.md` test files in this directory to build the test list — adding or removing a test `.md` file is all that's needed, no script changes required.

Pass `--test` with a comma-separated list of test filenames (with or without `.md`) to run only a subset — useful for retrying specific failures without re-executing the full suite.

**Prerequisites:**
- `http://github.localhost` must be accessible (or pass `--domain` to override)
- Run `script/in-product-messaging/setup` on the dev instance first
- Node.js must be installed (Playwright is auto-installed on first run)

#### Codespace / CI mode

When `--execute` points to the `qa/` directory:

1. Read this `setup.md` first.
2. **Run all `.md` test files in parallel** via `browse-remote-run-parallel.sh`.
3. Combine results into a single report.

---

## How to use nudge-test.mjs

**DO NOT write a new Playwright script for visual nudge tests.** Use `nudge-test.mjs` in the `qa/` root directory. It implements all 6 checks and is driven entirely by environment variables.

### For each visual nudge test `.md` file:

1. Parse the table at the top of the file to extract these fields:
   - **CTA Login** → env var `CTA_LOGIN`
   - **Dismiss Login** → env var `DISMISS_LOGIN`
   - **Test Page** → env var `TEST_PAGE`
   - **Test Page (Dismiss)** → env var `DISMISS_TEST_PAGE` (if present; defaults to `TEST_PAGE`)
   - **Expected CTA** → env var `EXPECTED_CTA` (replace spaces with underscores: `Enable_Copilot_Business`)
   - **Dismiss Type** → env var `DISMISS_TYPE`: use `dismiss-and-redirect` if the notes mention dismiss-and-redirect, otherwise use `standard`
   - The test name from the filename (e.g. `01-dfd-enable-cb`) → env var `NUDGE_NAME`

2. Run `nudge-test.mjs` via `browse-remote-run.sh` (or `browse-remote-run-parallel.sh` for directory mode) with those env vars.

### Example for a single nudge test:

```bash
bash browse-remote-run.sh \
  "script/in-product-messaging/qa/nudge-test.mjs" \
  "$CODESPACE_NAME" \
  "$REMOTE_WORK_DIR" \
  "$WORK_DIR" \
  "CTA_LOGIN=ipm-dfd-enable-cb DISMISS_LOGIN=ipm-dfd-enable-cb-dismiss TEST_PAGE=/settings/enterprises EXPECTED_CTA=Enable_Copilot_Business DISMISS_TYPE=standard NUDGE_NAME=01-dfd-enable-cb"
```

---

## How to use indicator-test.mjs

Use `indicator-test.mjs` for tests that validate **JSON API indicator endpoints** (e.g., the new tasks indicator that drives nav badges). These tests do NOT test visual nudge cards — they fetch a JSON endpoint and validate the response fields.

### For each indicator test `.md` file:

1. Parse the table at the top of the file to extract these fields:
   - **CTA Login** → env var `CTA_LOGIN`
   - **Indicator Endpoint** → env var `INDICATOR_ENDPOINT` (e.g. `/in-product-messaging/enterprise-new-tasks-indicator`)
   - **Expected Fields** → env var `EXPECTED_FIELDS` (comma-separated field names that should be `true`)
   - **Script** → confirms this test uses `indicator-test.mjs`
   - The test name from the filename → env var `NUDGE_NAME`

2. Run `indicator-test.mjs` via `browse-remote-run.sh` with those env vars.

### Example for an indicator test:

```bash
bash browse-remote-run.sh \
  "script/in-product-messaging/qa/indicator-test.mjs" \
  "$CODESPACE_NAME" \
  "$REMOTE_WORK_DIR" \
  "$WORK_DIR" \
  "CTA_LOGIN=ipm-nav-ent-new-tasks INDICATOR_ENDPOINT=/in-product-messaging/enterprise-new-tasks-indicator EXPECTED_FIELDS=enableEnterpriseNewTasksExperiment,showNewTasksButton NUDGE_NAME=17-nav-ent-new-tasks"
```

### For directory mode (parallel):

The parallel runner expects lines in `test-name::script-path::ENV_VARS` format. Build lines like:

```
01-dfd-enable-cb::script/in-product-messaging/qa/nudge-test.mjs::CTA_LOGIN=ipm-dfd-enable-cb DISMISS_LOGIN=ipm-dfd-enable-cb-dismiss TEST_PAGE=/settings/enterprises EXPECTED_CTA=Enable_Copilot_Business DISMISS_TYPE=standard NUDGE_NAME=01-dfd-enable-cb
17-nav-ent-new-tasks::script/in-product-messaging/qa/indicator-test.mjs::CTA_LOGIN=ipm-nav-ent-new-tasks INDICATOR_ENDPOINT=/in-product-messaging/enterprise-new-tasks-indicator EXPECTED_FIELDS=enableEnterpriseNewTasksExperiment,showNewTasksButton NUDGE_NAME=17-nav-ent-new-tasks
```

---

## How to use notification-test.mjs

Use `notification-test.mjs` for tests that validate **notification settings toggle switches** (e.g., the individual user opt-out toggle on `/settings/notifications`, or the org/enterprise Promotions + Tips toggles on profile settings pages). These tests do NOT test visual nudge cards — they toggle switches on/off and verify persistence.

### Environment variables

1. Parse the table at the top of the file to extract these fields:
   - **CTA Login** → env var `CTA_LOGIN`
   - **Test Page** → env var `TEST_PAGE`
   - **Section Text** → env var `SECTION_TEXT` (replace spaces with underscores: `In-product_messages`)
   - **Toggle Type** → env var `TOGGLE_TYPE`: use `primer-react` for the Primer React ToggleSwitch button (test 26 — `/settings/notifications`), or `primer-switch` for Primer `<toggle-switch>` web components (tests 27-28)
   - **Script** → confirms this test uses `notification-test.mjs`
   - The test name from the filename → env var `NUDGE_NAME`

### Implementation notes

- **Primer React ToggleSwitch** (user notifications page, test 26): A `<button>` with `aria-pressed` and class `prc-ToggleSwitch-SwitchButton-*` inside a `<div class="prc-ToggleSwitch-ToggleSwitch-*">`. Checked state is determined by `aria-pressed="true"`.
- **Primer toggle-switch components** (org/enterprise pages, tests 27-28): Web components detected via `data-test-selector="in-product-messaging-promotions-toggle"` and `data-test-selector="in-product-messaging-tips-toggle"`. Checked state is determined by the `ToggleSwitch--checked` CSS class.
- **Checkbox toggles** (legacy fallback, not currently used): Detected via `input[type="checkbox"]` inside a container matching the section heading text.

### What notification-test.mjs checks

**For `primer-switch` (dual toggles — 7 checks):**
1. Section heading visible
2. Promotions toggle defaults to ON
3. Tips toggle defaults to ON
4. Both toggles switch to OFF when clicked
5. Both toggles persist as OFF after page reload
6. Both toggles switch back to ON when clicked again

**For `primer-react` (single toggle — 5 checks):**
1. Section heading visible
2. Toggle defaults to ON
3. Toggle switches to OFF when clicked
4. Toggle persists as OFF after page reload
5. Toggle switches back to ON

**For `checkbox` (single toggle — 4 checks):**
1. Section heading visible
2. Toggle defaults to ON
3. Toggle persists as OFF after page reload
4. Toggle switches back to ON

### Example for a single notification test:

```bash
bash browse-remote-run.sh \
  "script/in-product-messaging/qa/notification-test.mjs" \
  "$CODESPACE_NAME" \
  "$REMOTE_WORK_DIR" \
  "$WORK_DIR" \
  "CTA_LOGIN=ipm-notification-org-opt-out TEST_PAGE=/organizations/ipm-notification-org-opt-out-org/settings/profile SECTION_TEXT=In-product_messages TOGGLE_TYPE=primer-switch NUDGE_NAME=27-notification-org-opt-out"
```

### For directory mode (parallel):

```
26-notification-settings::script/in-product-messaging/qa/notification-test.mjs::CTA_LOGIN=ipm-notification-settings TEST_PAGE=/settings/notifications SECTION_TEXT=In-product_messages TOGGLE_TYPE=primer-react NUDGE_NAME=26-notification-settings
27-notification-org-opt-out::script/in-product-messaging/qa/notification-test.mjs::CTA_LOGIN=ipm-notification-org-opt-out TEST_PAGE=/organizations/ipm-notification-org-opt-out-org/settings/profile SECTION_TEXT=In-product_messages TOGGLE_TYPE=primer-switch NUDGE_NAME=27-notification-org-opt-out
28-notification-ent-opt-out::script/in-product-messaging/qa/notification-test.mjs::CTA_LOGIN=ipm-notification-ent-opt-out TEST_PAGE=/enterprises/ipm-notification-ent-opt-out-biz/settings/profile SECTION_TEXT=In-product_messages TOGGLE_TYPE=primer-switch NUDGE_NAME=28-notification-ent-opt-out
```

---

## How to use modal-test.mjs

Use `modal-test.mjs` for tests that validate the **CCA onboarding modal** (a.k.a. Copilot Welcome Modal) that renders on `/copilot` and `/copilot/agents` for CB/CE seat-holders within 7 days of seat creation. The modal is a portal with three tabs, a Primer `ActionMenu` dropdown on tab 1, a persistent main "Get started" CTA, plus per-tab CTAs and an X close button — none of which fit `nudge-test.mjs`'s single-CTA model.

### Environment variables

1. Parse the table at the top of the file to extract these fields:
   - **CTA Login** → env var `CTA_LOGIN` (kept so the runner's `CTA_LOGIN` guard passes; same value as Modal Login)
   - **Modal Login** → env var `MODAL_LOGIN`
   - **Test Page** → env var `TEST_PAGE` (`/copilot` or `/copilot/agents`)
   - **Modal Mode** → env var `MODAL_MODE` (one of `cta_main`, `cta_tab2`, `features`, `close`)
   - **Expected Destination** → env var `EXPECTED_DESTINATION` (only for the CTA modes; supports the same `{slug}` placeholders as `nudge-test.mjs`)
   - **Script** → confirms this test uses `modal-test.mjs`
   - The test name from the filename → env var `NUDGE_NAME`

### What each MODAL_MODE checks

- **`cta_main`** — Modal is visible, the persistent main "Get started" anchor uses the dismiss-and-redirect endpoint with `destination_key=accelerate_ipm_copilot_business_onboarding_modal_copilot`, click lands on `/copilot`, modal is gone on the destination, and stays gone after a reload.
- **`cta_tab2`** — Click tab 2 ("Plan, delegate, or manage work"), assert the "Start with agents" anchor uses the dismiss-and-redirect endpoint with `destination_key=accelerate_ipm_copilot_business_onboarding_modal_agents`, click lands on `/copilot/agents`, modal is gone, stays gone after reload.
- **`features`** — Non-dismissing assertions: all three tab titles render; tab 1 dropdown shows `brew install copilot-cli` and the copy button writes that string to the clipboard; VS Code / JetBrains / More items have correct hrefs and `target="_blank"`; tab 3 "Create a custom agent" anchor points to `https://docs.github.com/...` with `target="_blank"`; modal remains visible at the end.
- **`close`** — Click the modal's X button, assert the modal is removed, reload the page, assert it stays gone (KV-backed `dismissed_notice` persistence).

### Implementation notes

- Selectors are scoped to the modal root `[data-testid="product-announcement-modal"]` to avoid colliding with page chrome or other nudges.
- The Primer `ActionMenu.Overlay` portals out of the modal — the dropdown items and copy button are queried at page scope rather than inside the modal root.
- Clipboard permissions are granted explicitly via `context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin })` so the `features` test can assert the copy button's payload.
- Tab-3 and the IDE links are NOT clicked (they would open new windows / could flake on docs availability) — only `href` and `target` are asserted.
- Each modal can only be exercised once before its CTA dismisses it. Tests 31–34 use four distinct accounts so they can run in parallel; setup re-runs both refresh the seat `created_at` and call `user.reset_notice("accelerate_ipm_copilot_business_onboarding_modal")` to keep eligibility intact across runs.

### For directory mode (parallel):

```
31-cca-modal-cta-copilot::script/in-product-messaging/qa/modal-test.mjs::MODAL_LOGIN=ipm-team-welcome-modal TEST_PAGE=/copilot MODAL_MODE=cta_main EXPECTED_DESTINATION=/copilot NUDGE_NAME=31-cca-modal-cta-copilot
32-cca-modal-cta-agents::script/in-product-messaging/qa/modal-test.mjs::MODAL_LOGIN=ipm-team-welcome-modal-cta-agents TEST_PAGE=/copilot MODAL_MODE=cta_tab2 EXPECTED_DESTINATION=/copilot/agents NUDGE_NAME=32-cca-modal-cta-agents
33-cca-modal-features::script/in-product-messaging/qa/modal-test.mjs::MODAL_LOGIN=ipm-team-welcome-modal-features TEST_PAGE=/copilot/agents MODAL_MODE=features NUDGE_NAME=33-cca-modal-features
34-cca-modal-dismiss::script/in-product-messaging/qa/modal-test.mjs::MODAL_LOGIN=ipm-team-welcome-modal-dismiss TEST_PAGE=/copilot MODAL_MODE=close NUDGE_NAME=34-cca-modal-dismiss
```

---

## QA Skill Integration

These fields are read by the `/qa` skill when running in codespace or direct mode.

**Codespace Setup Command:** `script/in-product-messaging/setup`

**Local Setup Reminder:**
```
⚠️ Remember to run script/in-product-messaging/setup on the dev instance before each run
```

---

## Prerequisites

1. **Seed data must exist:** Run `script/in-product-messaging/setup` on the Codespace or dev instance first.
2. **Server must be running:** `http://github.localhost` must be accessible.

**Base URL:** `http://github.localhost`
**Password for ALL accounts:** `passworD1`

---

## Important: No cropped screenshots

**Never crop or element-screenshot images.** All screenshots embedded in the report MUST be full-page
screenshots (`fullPage: true`). Element-level screenshots crop out surrounding context and often
capture the wrong container. Always use the full-page screenshot that shows the nudge in its
natural page context.

---

## Important: No shared users

Each test file uses **unique** logins. No user is shared across tests.
This prevents session/cookie collisions when running tests in parallel.

## What nudge-test.mjs checks (6 checks per nudge)

Dismiss checks run **first** (using the Dismiss account) to avoid CTA click side-effects
contaminating dismiss state. CTA checks run second (using the CTA account).

**Phase 1 — Dismiss (Dismiss account):**
5. **Dismiss Button** — Finds dismiss button within the nudge's own container (handles stacked nudges). Clicks it and verifies the specific nudge disappears. *(includes automatic retry — if not visible on first load, waits 10s and reloads once before failing)*
6. **Dismiss Persistence** — After reload, is the nudge still gone? *(skipped if dismiss was not confirmed in Check 5 — avoids false positives)*

**Phase 2 — CTA (CTA account):**
1. **Visibility** — Is the nudge CTA visible on the test page? *(includes automatic retry — if not visible on first load, waits 10s and reloads once before failing)*
2. **CTA Clickability & Destination** — Does center-clicking the CTA navigate? Is the destination a 404? *(waits up to 30s for navigation to complete)*
3. **Page Integrity** — Horizontal scroll? Broken visible images?
4. **Dismiss-and-Redirect** (only if `DISMISS_TYPE=dismiss-and-redirect`) — Does CTA click also dismiss?

---

## What indicator-test.mjs checks (3 checks per indicator)

1. **Fetch Indicator Endpoint** — Logs in and fetches the JSON API endpoint, validates HTTP 200
2. **Validate Expected Fields** — Checks that each expected field in the response is `true`
3. **Verify "New" Badge in Profile Nav** — Opens the profile nav drawer (clicks avatar in top-right), takes a full-page screenshot, and verifies a "New" badge appears next to "Your enterprises" or "Your organizations" respectively

---

## Reporting

After all tests complete, compile the results into a combined report with a summary table, screenshots, and videos. Include:
- Total wall-clock duration
- Codespace name used
- Login username for each test (both CTA and Dismiss accounts)
- **Dest column**: For nudge tests, include a "Dest" column showing CTA destination validation status (✅ matched, ❌ mismatch, ⚠️ skipped, — not applicable). This column must always be present in the summary table.

### Embedding videos

Each test produces a `.webm` video recording in its `videos/` directory. Embed videos in the per-test detail sections as markdown links (GitHub strips `<video>` tags):

```markdown
[▶ Watch recording](videos/01-dfd-enable-cb.webm)
```
