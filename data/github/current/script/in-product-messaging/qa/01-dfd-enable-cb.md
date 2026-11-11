# 01 — DFD: Enable Copilot Business

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-dfd-enable-cb` |
| **Dismiss Login** | `ipm-dfd-enable-cb-dismiss` |
| **Test Page** | `/settings/enterprises` |
| **Expected CTA** | "Enable Copilot Business" |
| **Expected Destination** | `/enterprises/{enterprise_slug}/trial_activations` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Enterprise owner of `ipm-dfd-enable-cb-ent` |
| **Setup** | Trial enterprise, 4 days old, no org. Only this card shows (Create Org needs 5+ days). |

## Notes

- **Location:** "Getting started" DFD task card section in the enterprise list
- This is the only DFD account that shows just one card naturally (enterprise is only 4 days old)
- **CTA account** (`ipm-dfd-enable-cb`): Use for Checks 1–4 (visibility, CTA, page integrity)
- **Dismiss account** (`ipm-dfd-enable-cb-dismiss`): Use for Checks 5–6 (dismiss button, persistence). Identical setup — separate enterprise `ipm-dfd-enable-cb-dismiss-ent`.
