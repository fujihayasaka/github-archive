# 02 — DFD: Create Organization

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-dfd-create-org` |
| **Dismiss Login** | `ipm-dfd-create-org-dismiss` |
| **Test Page** | `/settings/enterprises` |
| **Expected CTA** | "Create organization" |
| **Expected Destination** | `/enterprises/{enterprise_slug}/organizations/new` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Enterprise owner of `ipm-dfd-create-org-ent` |
| **Setup** | Trial enterprise, 21 days old, no org. CB card pre-dismissed — only this card shows. |

## Notes

- **Location:** "Getting started" DFD task card section in the enterprise list
- The "Enable Copilot Business" card is pre-dismissed in seed data so this is the only card visible
- **CTA account** (`ipm-dfd-create-org`): Use for Checks 1–4
- **Dismiss account** (`ipm-dfd-create-org-dismiss`): Use for Checks 5–6. Identical setup — separate enterprise `ipm-dfd-create-org-dismiss-ent`.
