# 32 — CCA Onboarding Modal: Tab 2 "Start with agents" CTA

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-team-welcome-modal-cta-agents` |
| **Modal Login** | `ipm-team-welcome-modal-cta-agents` |
| **Test Page** | `/copilot` |
| **Modal Mode** | `cta_tab2` |
| **Expected Destination** | `/copilot/agents` |
| **Script** | `modal-test.mjs` |
| **Role** | Org member of `ipm-team-welcome-modal-cta-agents-org` (Team plan with CB seat) |
| **Setup** | Dedicated CB seat-holder. A separate account is required (vs. the main-CTA test) because the CTA dismisses the modal, and tests run in parallel against the same codespace. |

## Notes

- **Location:** Modal tab 2 — "Plan, delegate, or manage work".
- **CTA tested:** Tab-2 CTA "Start with agents".
- **What to verify:**
  1. Modal is visible on `/copilot`.
  2. Click the tab-2 button (`button[data-tab]` matching "Plan, delegate, or manage work").
  3. The "Start with agents" anchor inside the modal has the dismiss-and-redirect href with `destination_key=accelerate_ipm_copilot_business_onboarding_modal_agents`.
  4. Clicking it lands on `/copilot/agents` (not 404).
  5. Modal is gone on the destination page.
  6. Reload — modal stays gone.
