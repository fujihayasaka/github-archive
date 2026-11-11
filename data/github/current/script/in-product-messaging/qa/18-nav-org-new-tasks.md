# 18 — Nav: Organization New Tasks Indicator

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-nav-org-new-tasks` |
| **Indicator Endpoint** | `/in-product-messaging/organization-new-tasks-indicator` |
| **Expected Fields** | `enableOrganizationNewTasksExperiment,showNewTasksButton` |
| **Script** | `indicator-test.mjs` |

## Notes

- **Type:** JSON API indicator test (not a visual nudge test — uses `indicator-test.mjs`, not `nudge-test.mjs`)
- **What it tests:** The organization new tasks indicator endpoint returns `showNewTasksButton: true` when an org admin has a pending nudge. This drives the "New tasks" badge in the global navigation drawer next to the Organizations link.
- **Dedicated account:** Uses `ipm-nav-org-new-tasks` — a dedicated org admin of `ipm-nav-org-new-tasks-org` (Team plan) with CB enabled and CLI not enabled (pending organization nudge).
- **Nav page:** After validating the JSON response, opens the profile nav drawer and verifies "New" badge appears next to "Organizations".
