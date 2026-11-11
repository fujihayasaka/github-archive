# 16 — Transactional Banner: Enterprise

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-transactional-ent` |
| **Dismiss Login** | `ipm-transactional-ent-dismiss` |
| **Test Page** | `/businesses/ipm-transactional-ent-biz` |
| **Expected CTA** | "Learn more" |
| **Expected Destination** | `https://github.com/features` |
| **Dismiss Type** | Standard — close icon on the banner |
| **Role** | Enterprise owner |
| **Setup** | GHEC enterprise owner — the nudge has no eligibility check beyond the feature flag. |

## Notes

- **Location:** Page-specific banner on the enterprise overview page (not global — does NOT appear on other pages)
- **Banner style:** Inline banner rendered via `render_react_partial` (React component)
- **Banner text:** "This is a test transactional banner on the enterprise page. Learn more."
- **Feature flags required:** `ipm_test_transactional_banner_enterprise` + `ipm_global_transactional_message_enterprise` + `in_product_messaging_transactional_message_engine`
- This tests the ERB-to-React migration of the TransactionalMessageBanner component on the enterprise overview surface
- **CTA account** (`ipm-transactional-ent`): Use for Checks 1–4
- **Dismiss account** (`ipm-transactional-ent-dismiss`): Use for Checks 5–6. Identical setup — separate enterprise owner.
