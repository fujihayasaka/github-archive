# 14 — Transactional Banner: Dashboard

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-transactional-dashboard` |
| **Dismiss Login** | `ipm-transactional-dashboard-dismiss` |
| **Test Page** | `/` |
| **Expected CTA** | "Learn more" |
| **Expected Destination** | `https://github.com/features` |
| **Dismiss Type** | Standard — close icon on the banner |
| **Role** | Individual user (no org/enterprise needed) |
| **Setup** | Simple Copilot Pro user — the nudge has no eligibility check beyond the feature flag. |

## Notes

- **Location:** Page-specific banner on the dashboard (not global — does NOT appear on other pages)
- **Banner style:** Inline banner rendered via `render_react_partial` (React component)
- **Banner text:** "This is a test transactional banner on the dashboard. Learn more."
- **Feature flags required:** `ipm_test_transactional_banner_dashboard` + `ipm_global_transactional_message_dashboard` + `in_product_messaging_transactional_message_engine`
- This tests the ERB-to-React migration of the TransactionalMessageBanner component on the dashboard surface
- **CTA account** (`ipm-transactional-dashboard`): Use for Checks 1–4
- **Dismiss account** (`ipm-transactional-dashboard-dismiss`): Use for Checks 5–6. Identical setup — separate user.
