# 06 — Enterprise: Enable Copilot CLI

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-ent-enable-cli` |
| **Dismiss Login** | `ipm-ent-enable-cli-dismiss` |
| **Test Page** | `/settings/enterprises` |
| **Expected CTA** | "Enable Copilot CLI" |
| **Expected Destination** | `/enterprises/{enterprise_slug}/ai-controls/copilot` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Enterprise owner of `ipm-ent-enable-cli-biz` |
| **Setup** | Non-trial enterprise, CB enabled, CLI not enabled. |

## Notes

- **Location:** Nudge card next to the enterprise name in the enterprise settings list
- This is a non-trial (paid) enterprise — different card style from DFD task cards
- **CTA account** (`ipm-ent-enable-cli`): Use for Checks 1–4
- **Dismiss account** (`ipm-ent-enable-cli-dismiss`): Use for Checks 5–6. Identical setup — separate enterprise `ipm-ent-enable-cli-dismiss-biz`.
