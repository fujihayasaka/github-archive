# 27 — Notification Settings: Organization Opt-Out

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-notification-org-opt-out` |
| **Test Page** | `/organizations/ipm-notification-org-opt-out-org/settings/profile` |
| **Section Text** | `In-product messages` |
| **Toggle Type** | `primer-switch` — Primer `<toggle-switch>` web components (Promotions + Tips) |
| **Script** | `notification-test.mjs` |
| **Role** | Organization admin |
| **Setup** | Team org admin — requires feature flag to show the toggle UI. |

## Notes

- **Location:** "In-product messages" section on the organization profile settings page
- **Test URL:** `github.com/organizations/{org_slug}/settings/profile`
- **Feature flag required:** `in_product_messaging_organization_opt_out`
- **Two toggles are present:**
  - **Promotions** — controls promotional content for the organization
  - **Tips** — controls helpful tips about products/features the organization has enabled
- **What to verify:**
  1. Navigate to `/organizations/ipm-notification-org-opt-out-org/settings/profile`
  2. Locate the "In-product messages" section (requires feature flag to be enabled)
  3. Verify both Promotions and Tips toggles are visible and default to ON (opted-in)
  4. Toggle Promotions OFF — verify the toggle switches to OFF state
  5. Toggle Tips OFF — verify the toggle switches to OFF state
  6. Reload the page — verify both toggles persist as OFF
  7. Toggle both back ON — verify they switch to ON state
- **Test account** (`ipm-notification-org-opt-out`): Use for all checks
