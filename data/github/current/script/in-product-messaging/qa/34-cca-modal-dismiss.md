# 34 — CCA Onboarding Modal: X Close (Dismissal Persistence)

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-team-welcome-modal-dismiss` |
| **Modal Login** | `ipm-team-welcome-modal-dismiss` |
| **Test Page** | `/copilot` |
| **Modal Mode** | `close` |
| **Script** | `modal-test.mjs` |
| **Role** | Org member of `ipm-team-welcome-modal-dismiss-org` (Team plan with CB seat) |
| **Setup** | Mirror of the main-CTA account; dedicated to dismissal so its state can be reset independently between runs. |

## Notes

- **Location:** Modal close button (X) inside `[data-testid="product-announcement-modal"]`.
- **What to verify:**
  1. Modal is visible on `/copilot`.
  2. Clicking the X removes the modal from the DOM.
  3. Reload the page — modal stays gone.
- **Persistence mechanism:** the close handler `POST`s to `/track-nudge-dismissal?id=accelerate_ipm_copilot_business_onboarding_modal&group=engage`. The endpoint name is for analytics — its primary server-side action is `InProductTargeting::NudgeMemory#save_a_copy_of_dismissal_analytics_to_dotcom` (which writes IPM subscription metadata, not eligibility state). The reason the reload-persistence assertion succeeds is that the same controller action ALSO calls `current_user.dismiss_notice(id) if UserNotice.find(id)`, and `accelerate_ipm_copilot_business_onboarding_modal` is registered in `config/notices.yml`. That conditional side-effect is what writes the canonical `user.dismissed_notice.<name>` KV that the modal's `eligible?` check reads.
- **State reset:** setup re-runs call `user.reset_notice("accelerate_ipm_copilot_business_onboarding_modal")` for this login so the modal is eligible again on the next test run.
