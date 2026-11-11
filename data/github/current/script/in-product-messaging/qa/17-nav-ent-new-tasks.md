# 17 — Nav: Enterprise New Tasks Indicator

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-nav-ent-new-tasks` |
| **Indicator Endpoint** | `/in-product-messaging/enterprise-new-tasks-indicator` |
| **Expected Fields** | `enableEnterpriseNewTasksExperiment,showNewTasksButton` |
| **Script** | `indicator-test.mjs` |

## Notes

- **Type:** JSON API indicator test (not a visual nudge test — uses `indicator-test.mjs`, not `nudge-test.mjs`)
- **What it tests:** The enterprise new tasks indicator endpoint returns `showNewTasksButton: true` when an enterprise owner has a pending nudge. This drives the "New tasks" badge in the global navigation drawer next to the Enterprises link.
- **Dedicated account:** Uses `ipm-nav-ent-new-tasks` — a dedicated enterprise owner of `ipm-nav-ent-new-tasks-biz` with CB enabled and CLI not enabled (pending enterprise nudge).
- **Nav page:** After validating the JSON response, opens the profile nav drawer and verifies "New" badge appears next to "Enterprises".
