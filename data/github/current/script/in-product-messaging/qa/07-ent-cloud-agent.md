# 07 — Enterprise: Configure Coding Agent

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-ent-cloud-agent` |
| **Dismiss Login** | `ipm-ent-cloud-agent-dismiss` |
| **Test Page** | `/settings/enterprises` |
| **Expected CTA** | "Configure cloud agent" |
| **Expected Destination** | `/enterprises/{enterprise_slug}/ai-controls/agents/policies` |
| **Dismiss Type** | Standard — `form[action*="dismiss"] button` |
| **Role** | Enterprise owner of `ipm-ent-cloud-agent-biz` |
| **Setup** | Non-trial enterprise, CB enabled, CLI enabled. |

## Notes

- **Location:** Nudge card next to the enterprise name in the enterprise settings list
- This enterprise has both CB and CLI enabled — the next recommended action is cloud agent setup
- **CTA account** (`ipm-ent-cloud-agent`): Use for Checks 1–4
- **Dismiss account** (`ipm-ent-cloud-agent-dismiss`): Use for Checks 5–6. Identical setup — separate enterprise `ipm-ent-cloud-agent-dismiss-biz`.
