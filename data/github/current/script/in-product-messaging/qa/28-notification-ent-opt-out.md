# 28 — Notification Settings: Enterprise Opt-Out

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-notification-ent-opt-out` |
| **Test Page** | `/enterprises/ipm-notification-ent-opt-out-biz/settings/profile` |
| **Section Text** | `In-product messages` |
| **Toggle Type** | `primer-switch` — Primer `<toggle-switch>` web components (Promotions + Tips) |
| **Script** | `notification-test.mjs` |
| **Role** | Enterprise owner |
| **Setup** | GHEC enterprise owner — requires feature flag to show the toggle UI. |

## Notes

- **Location:** "In-product messages" section on the enterprise profile settings page
- **Test URL:** `github.com/enterprises/{business_slug}/settings/profile`
- **Feature flag required:** `in_product_messaging_business_opt_out`
- **Two toggles are present:**
  - **Promotions** — controls promotional content for the enterprise
  - **Tips** — controls helpful tips about products/features the enterprise has enabled
- **What to verify:**
  1. Navigate to `/enterprises/ipm-notification-ent-opt-out-biz/settings/profile`
  2. Locate the "In-product messages" section (requires feature flag to be enabled)
  3. Verify both Promotions and Tips toggles are visible and default to ON (opted-in)
  4. Toggle Promotions OFF — verify the toggle switches to OFF state
  5. Toggle Tips OFF — verify the toggle switches to OFF state
  6. Reload the page — verify both toggles persist as OFF
  7. Toggle both back ON — verify they switch to ON state
- **Test account** (`ipm-notification-ent-opt-out`): Use for all checks
