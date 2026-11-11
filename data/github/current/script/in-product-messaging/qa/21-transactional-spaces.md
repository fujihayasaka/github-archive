# 21 — Transactional Banner: Spaces

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-transactional-spaces` |
| **Dismiss Login** | `ipm-transactional-spaces-dismiss` |
| **Test Page** | `/copilot` |
| **Expected CTA** | "Learn more" |
| **Expected Destination** | `https://github.com/features` |
| **Dismiss Type** | Standard — close icon on the banner |
| **Role** | Individual user (Copilot Pro) |
| **Setup** | Copilot Pro user — the nudge has no eligibility check beyond the feature flag. |

## Notes

- **Location:** Page-specific banner on Copilot Spaces pages (not global — does NOT appear on other pages)
- **Banner style:** Inline banner rendered via `render_react_partial` (React component)
- **Banner text:** "This is a test transactional banner on the spaces page. Learn more."
- **Feature flags required:** `ipm_test_transactional_banner_spaces` + `ipm_global_transactional_message_spaces` + `in_product_messaging_transactional_message_engine`
- This tests the ERB-to-React migration of the TransactionalMessageBanner component on the Spaces surface
- **CTA account** (`ipm-transactional-spaces`): Use for Checks 1–4
- **Dismiss account** (`ipm-transactional-spaces-dismiss`): Use for Checks 5–6. Identical setup — separate user.
