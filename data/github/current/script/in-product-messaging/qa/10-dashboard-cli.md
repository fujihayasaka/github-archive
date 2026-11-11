# 10 — Dashboard: Copilot CLI Enabled

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-dashboard-cli` |
| **Dismiss Login** | `ipm-dashboard-cli-dismiss` |
| **Test Page** | `/` |
| **Expected CTA** | "Get started with Copilot CLI" |
| **Expected Destination** | `https://github.com/github/copilot-cli?tab=readme-ov-file#-getting-started` |
| **Dismiss Type** | **Dismiss-and-redirect** — the CTA both dismisses the nudge AND redirects. Also has an X dismiss button. |
| **Role** | Org member of `ipm-dashboard-cli-org` (Team plan) |
| **Setup** | CB enabled, CCR enabled, CLI enabled within 14 days. NUCBS nudge may also appear since CB seat is new. |

## Notes

- **Location:** Banner or card near the top of the dashboard feed
- **Dismiss-and-redirect behavior:** Same as nudge #9 but for the CLI nudge.
- **Important:** This account may ALSO show the NUCBS nudge (#9) since the CB seat is new. Match on the **exact** CTA text "Get started with Copilot CLI" — not "Get started with Copilot".
- Run Check 4 (Dismiss-and-Redirect) for this nudge
- **CTA account** (`ipm-dashboard-cli`): Use for Checks 1–4 (including Check 4: Dismiss-and-Redirect)
- **Dismiss account** (`ipm-dashboard-cli-dismiss`): Use for Checks 5–6 (X button, persistence). Identical setup — separate org `ipm-dashboard-cli-dismiss-org`.
