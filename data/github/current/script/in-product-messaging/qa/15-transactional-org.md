# 15 — Transactional Banner: Organization

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-transactional-org` |
| **Dismiss Login** | `ipm-transactional-org-dismiss` |
| **Test Page** | `/ipm-transactional-org-org` |
| **Expected CTA** | "Learn more" |
| **Expected Destination** | `https://github.com/features` |
| **Dismiss Type** | Standard — close icon on the banner |
| **Role** | Organization admin |
| **Setup** | Team org admin — the nudge has no eligibility check beyond the feature flag. |

## Notes

- **Location:** Page-specific banner on the org overview page (not global — does NOT appear on other pages)
- **Banner style:** Inline banner rendered via `render_react_partial` (React component)
- **Banner text:** "This is a test transactional banner on the org page. Learn more."
- **Feature flags required:** `ipm_test_transactional_banner_org` + `ipm_global_transactional_message_org` + `in_product_messaging_transactional_message_engine`
- This tests the ERB-to-React migration of the TransactionalMessageBanner component on the org overview surface
- **CTA account** (`ipm-transactional-org`): Use for Checks 1–4
- **Dismiss account** (`ipm-transactional-org-dismiss`): Use for Checks 5–6. Identical setup — separate org admin.
