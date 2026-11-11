# 31 — CCA Onboarding Modal: Main "Get started" CTA

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-team-welcome-modal` |
| **Modal Login** | `ipm-team-welcome-modal` |
| **Test Page** | `/copilot` |
| **Modal Mode** | `cta_main` |
| **Expected Destination** | `/copilot` |
| **Script** | `modal-test.mjs` |
| **Role** | Org member of `ipm-team-welcome-modal-org` (Team plan with CB seat) |
| **Setup** | Team org with Copilot Business enabled. Member has a `Copilot::Seat`; setup re-runs refresh `seat.created_at` and clear the dismissed-notice KV so the modal is eligible on every run. |

## Notes

- **Location:** `[data-testid="product-announcement-modal"]` — full-page Portal modal rendered on `/copilot` and `/copilot/agents` for CB/CE seat-holders within 7 days of seat creation.
- **CTA tested:** Persistent main button "Get started" (visible on every tab).
- **What to verify:**
  1. Modal is visible on `/copilot` for the CB seat-holder.
  2. Main "Get started" CTA href is the dismiss-and-redirect endpoint with `destination_key=accelerate_ipm_copilot_business_onboarding_modal_copilot`.
  3. Clicking it lands on `/copilot` (not 404).
  4. Modal is NOT visible on the destination — verifies PR #430548 + #19862 fix the read-after-write race that previously left the modal up.
  5. Reload the destination — modal stays gone (KV-backed `dismissed_notice` persistence).
- **Account reuse:** `ipm-team-welcome-modal` is also used by other checks; setup refreshes its dismissal state on every run.
