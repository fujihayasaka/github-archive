# 26 — Notification Settings: In-Product Messaging Toggle

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-notification-settings` |
| **Test Page** | `/settings/notifications` |
| **Section Text** | `In-product messages` |
| **Toggle Type** | `primer-react` — single Primer React ToggleSwitch (`<button aria-pressed>`) |
| **Script** | `notification-test.mjs` |
| **Role** | Individual user (Copilot Pro) |
| **Setup** | Simple Copilot Pro user — no org or enterprise needed. |

## Notes

- **Location:** "In-product messaging" subscription toggle on the user notifications settings page
- **Test URL:** `github.com/settings/notifications`
- **No feature flag required** — the individual user toggle is always visible
- **What to verify:**
  1. Navigate to `/settings/notifications`
  2. Locate the "In-product messaging" section
  3. Verify the toggle is visible and defaults to ON (opted-in)
  4. Toggle OFF — verify the toggle switches to OFF state
  5. Reload the page — verify the toggle persists as OFF
  6. Toggle back ON — verify the toggle switches to ON state
- **Test account** (`ipm-notification-settings`): Use for all checks
