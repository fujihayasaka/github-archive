# 23 — Transactional Banner: Issues

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-transactional-issues` |
| **Dismiss Login** | `ipm-transactional-issues-dismiss` |
| **Test Page** | `/ipm-transactional-issues-org/test-repo/issues/2` |
| **Test Page (Dismiss)** | `/ipm-transactional-issues-dismiss-org/test-repo/issues/2` |
| **Expected CTA** | "Learn more" |
| **Expected Destination** | `https://github.com/features` |
| **Dismiss Type** | Standard — close icon on the banner |
| **Role** | Organization admin |
| **Setup** | Team org admin — the nudge has no eligibility check beyond the feature flag. |

## Notes

- **Location:** Page-specific banner on the issues page (not global — does NOT appear on other pages)
- **Banner style:** Inline banner rendered via `render_react_partial` (React component)
- **Banner text:** "This is a test transactional banner on the issues page. Learn more."
- **Feature flags required:** `ipm_test_transactional_banner_issues` + `ipm_global_transactional_message_issues` + `in_product_messaging_transactional_message_engine`
- This tests the ERB-to-React migration of the TransactionalMessageBanner component on the issues surface
- **CTA account** (`ipm-transactional-issues`): Use for Checks 1–4
- **Dismiss account** (`ipm-transactional-issues-dismiss`): Use for Checks 5–6. Identical setup — separate org admin.
