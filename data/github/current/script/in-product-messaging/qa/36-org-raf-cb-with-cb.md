# 36 — Org Settings: RAF → CB Nudge (With Copilot Business / Manual Only)

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-org-raf-cb-with-cb` |
| **Test Page** | `/organizations/ipm-org-raf-cb-with-cb-org/settings/organizations` |
| **Expected CTA** | "Add seats" / "Review requests" |
| **Expected Destination** | `/organizations/{org_slug}/settings/copilot/seat_management` |
| **Role** | Org admin of a Team org **with** Copilot Business in `selected_teams_and_users` mode |
| **Setup** | Team org, CB enabled in `selected_teams_and_users` seat-management mode. Two seeded org members (`<org>-mem1`, `<org>-mem2`) have submitted RAF requests for Copilot Business and do **not** have seats. |
| **Skip** | true |

## Notes

- **Why `Skip: true`:** the visual nudge test framework (`nudge-test.mjs`) unconditionally exercises a global Dismiss button. The with-CB variant of the `organization_new_tasks_raf_cb_nudge` does **not** render a global dismiss control — admins resolve each pending request individually via `growth/member_feature_request_dismissals_controller.rb`. This test is manual-only.
- **Location:** Organizations settings page (`/settings/organizations`).
- **Card title:** "Your team is asking for Copilot Business" (same nudge ID as #35).
- **Issue:** [github/in-product-messaging#262](https://github.com/github/in-product-messaging/issues/262).
- **Nudge ID:** `organization_new_tasks_raf_cb_nudge`
- **Manual QA steps:**
  1. Sign in as `ipm-org-raf-cb-with-cb`.
  2. Visit `/organizations/ipm-org-raf-cb-with-cb-org/settings/organizations`.
  3. Verify the nudge renders with the "Add seats" / review-requests CTA.
  4. Verify there is **no** global X / Dismiss control on the card.
  5. Click through to seat management and verify it lists the two pending member requests (`ipm-org-raf-cb-with-cb-org-mem1`, `ipm-org-raf-cb-with-cb-org-mem2`).
  6. Use the per-request dismissal control from `member_feature_request_dismissals_controller.rb` and verify the request count drops by one.
- **Eligibility nuance:** the org must be in `seat_management_selected_teams_and_users!` mode (NOT `seat_management_allow_all!`) for `MemberFeatureRequest` records to be valid (`packages/growth/app/models/member_feature_request.rb:355-364` — `copilot_seat_enabled_for_member`). The setup script enforces this via `enable_copilot_business_in_selected_mode_for_standalone_org`, which intentionally bypasses the default helper that would call `seat_management_allow_all!`.
