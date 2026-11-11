# 03 — DFD: Create Repository

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-dfd-create-repo` |
| **Dismiss Login** | `ipm-dfd-create-repo-dismiss` |
| **Test Page** | `/settings/enterprises` |
| **Expected CTA** | "Create repository" |
| **Expected Destination** | `/organizations/{org_slug}/repositories/new` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Enterprise owner of `ipm-dfd-create-repo-ent` |
| **Setup** | Trial enterprise, 21 days old, has org (`ipm-dfd-create-repo-org`), no repo. CB card pre-dismissed — only this card shows. |

## Notes

- **Location:** "Getting started" DFD task card section in the enterprise list
- The "Enable Copilot Business" card is pre-dismissed in seed data so this is the only card visible
- **CTA account** (`ipm-dfd-create-repo`): Use for Checks 1–4
- **Dismiss account** (`ipm-dfd-create-repo-dismiss`): Use for Checks 5–6. Identical setup — separate enterprise `ipm-dfd-create-repo-dismiss-ent` with org `ipm-dfd-create-repo-dismiss-org`.
