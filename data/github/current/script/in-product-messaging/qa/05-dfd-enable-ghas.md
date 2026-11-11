# 05 — DFD: Enable Advanced Security

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-dfd-enable-ghas` |
| **Dismiss Login** | `ipm-dfd-enable-ghas-dismiss` |
| **Test Page** | `/settings/enterprises` |
| **Expected CTA** | "Enable Advanced Security" |
| **Expected Destination** | `/{org_slug}/{repo_slug}/security` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Enterprise owner of `ipm-dfd-enable-ghas-ent` |
| **Setup** | Trial enterprise, 21 days old, has org + repo with code, no GHAS. CB card pre-dismissed — only this card shows. |

## Notes

- **Location:** "Getting started" DFD task card section in the enterprise list
- The "Enable Copilot Business" card is pre-dismissed in seed data so this is the only card visible
- **CTA account** (`ipm-dfd-enable-ghas`): Use for Checks 1–4
- **Dismiss account** (`ipm-dfd-enable-ghas-dismiss`): Use for Checks 5–6. Identical setup — separate enterprise `ipm-dfd-enable-ghas-dismiss-ent` with org `ipm-dfd-enable-ghas-dismiss-org`.
