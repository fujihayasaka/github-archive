# 35 — Org Settings: Request a Feature → Copilot Business Nudge

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-org-raf-cb-no-cb` |
| **Dismiss Login** | `ipm-org-raf-cb-no-cb-dismiss` |
| **Test Page (CTA)** | `/organizations/ipm-org-raf-cb-no-cb-org/settings/organizations` |
| **Test Page (Dismiss)** | `/organizations/ipm-org-raf-cb-no-cb-dismiss-org/settings/organizations` |
| **Expected CTA** | "Enable Copilot Business" |
| **Expected Destination** | `/organizations/{org_slug}/settings/copilot/copilot_business_signup_new` |
| **Dismiss Type** | Standard — X button on the nudge card |
| **Role** | Org admin of a Free org **without** Copilot Business |
| **Setup** | Free org, no CB. Two seeded org members (`<org>-mem1`, `<org>-mem2`) have submitted RAF requests for Copilot Business. |

## Notes

- **Location:** Organizations settings page (`/settings/organizations`) at the top of the page, rendered via `app/views/settings/organization_nudges/_raf_cb_nudge.html.erb`.
- **Card title:** "Your team is asking for Copilot Business"
- **Issue:** [github/in-product-messaging#262](https://github.com/github/in-product-messaging/issues/262).
- **Nudge ID:** `organization_new_tasks_raf_cb_nudge`
- **Test selector:** `cb_settings_organizations_new_tasks_nudge_1` (verified in `packages/in_product_targeting/test/system/organization_nudges_test.rb`).
- **Variants:**
  - **Without CB** (this test) — admin sees an "Enable Copilot Business" CTA + a global Dismiss control. Dismissal is one-shot and persists until the org buys CB.
  - **With CB** (separate account, `ipm-org-raf-cb-with-cb` — see `36-org-raf-cb-with-cb.md`) — admin sees an "Add seats" / review-requests CTA and **no global dismiss control**; admins resolve requests individually via the request-dismissal controller. Not exercised by this visual test because the framework expects a global dismiss button.
- **CTA account** (`ipm-org-raf-cb-no-cb`): Use for Checks 1–4. The setup script resets the dismissal each run (`reset_organization_notice("organization_new_tasks_raf_cb_nudge", org)`) so the nudge is eligible after every re-seed.
- **Dismiss account** (`ipm-org-raf-cb-no-cb-dismiss`): Use for Checks 5–6. Identical setup — separate org `ipm-org-raf-cb-no-cb-dismiss-org` so the primary account's dismiss state never changes.
- **Eligibility (`organization_nudge_concern.rb:211-253`):**
  1. `:organization_new_tasks_nudges` and `:organization_new_tasks_raf_cb_nudge` flags enabled (setup enables both).
  2. Admin must not have dismissed the notice (resets on every setup run).
  3. `MemberFeatureRequest.total_by_feature(org)[CopilotForBusiness] > 0` — provided by the two seeded members.
  4. `Notifications::Settings.member_feature_requests` returns nil for fresh admins, treated as "subscribed".
