# 08 — Org: Enable Copilot CLI

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-org-cli` |
| **Dismiss Login** | `ipm-org-cli-dismiss` |
| **Test Page** | `/settings/organizations` |
| **Expected CTA** | "Enable Copilot CLI" |
| **Expected Destination** | `/organizations/{org_slug}/settings/copilot/policies` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Org admin of `ipm-org-cli-org` (Team plan) |
| **Setup** | CB enabled, CLI not enabled. |

## Notes

- **Location:** Nudge card next to the org name in the organization settings list
- Similar card style to enterprise list nudges but on `/settings/organizations`
- **CTA account** (`ipm-org-cli`): Use for Checks 1–4
- **Dismiss account** (`ipm-org-cli-dismiss`): Use for Checks 5–6. Identical setup — separate org `ipm-org-cli-dismiss-org`.
