# 39 — Dashboard: Copilot CLI Install (Pro / Pro+ devs)

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-copilot-cli-dashboard-pro` |
| **Dismiss Login** | `ipm-copilot-cli-dashboard-dismiss` |
| **Test Page** | `/` |
| **Expected CTA** | "Read the docs" |
| **Expected Destination** | `https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-getting-started` |
| **Dismiss Type** | **Dismiss-and-redirect** — the "Read the docs" footer link both dismisses the nudge AND redirects. The card also has an X dismiss button. |
| **Role** | Individual Copilot Pro user (no org/enterprise required) |
| **Setup** | `accelerate_ipm_copilot_cli_dashboard_for_devs` FF enabled (seeded by `setup`), Copilot Pro access, NOT in the `2026_05_copilot_cli_usage_past_60d` recent-usage cohort. |

## Notes

- **Component:** `InProductTargeting::Components::DashboardNudges::CopilotCliForDevsNudgeComponent` (`banner-nudge-card` install-picker variant).
- **Location:** Card near the top of the dashboard feed.
- **Title:** "Get started with Copilot CLI". The card has no big CTA button — instead it renders a `CommandPicker` (Homebrew / npm / WinGet / curl) with per-method **copy** buttons, plus a "Read the docs" footer link.
- **Why "Read the docs" is the CTA:** the install-picker variant suppresses `ctaTitle`/`ctaHref`, so the footer link is the only navigating CTA. It is a dismiss-and-redirect to the Copilot CLI getting-started docs.
- Run Check 4 (Dismiss-and-Redirect) for this nudge.
- **CTA account** (`ipm-copilot-cli-dashboard-pro`): Use for Checks 1–4 (including Check 4: Dismiss-and-Redirect).
- **Dismiss account** (`ipm-copilot-cli-dashboard-dismiss`): Use for Checks 5–6 (X button, persistence). Identical Pro setup.

### Additional accounts (not auto-run by the harness)

- `ipm-copilot-cli-dashboard-pro-plus` (Copilot Pro+): positive case — should ALSO see the nudge (eligibility covers Pro and Pro+).
- `ipm-copilot-cli-dashboard-recent-usage` (Pro, seeded into the `2026_05_copilot_cli_usage_past_60d` cohort): negative case — should **NOT** see the nudge, because recent CLI users are excluded.
