# 04 — DFD: Add Code

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-dfd-add-code` |
| **Dismiss Login** | `ipm-dfd-add-code-dismiss` |
| **Test Page** | `/settings/enterprises` |
| **Expected CTA** | "Add code" |
| **Expected Destination** | `/{org_slug}/{repo_slug}` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Enterprise owner of `ipm-dfd-add-code-ent` |
| **Setup** | Trial enterprise, 21 days old, has org + empty repo (no commits). CB card pre-dismissed — only this card shows. |

## Notes

- **Location:** "Getting started" DFD task card section in the enterprise list
- The "Enable Copilot Business" card is pre-dismissed in seed data so this is the only card visible
- **CTA account** (`ipm-dfd-add-code`): Use for Checks 1–4
- **Dismiss account** (`ipm-dfd-add-code-dismiss`): Use for Checks 5–6. Identical setup — separate enterprise `ipm-dfd-add-code-dismiss-ent` with org `ipm-dfd-add-code-dismiss-org`.
