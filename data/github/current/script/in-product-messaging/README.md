# In-Product Messaging — Local Setup

This script seeds organizations, enterprises, repositories, and users that mirror
the production states the IPM team targets with banners, nudges, and
notifications. Use it to develop and validate IPM surfaces in your local /
codespace dev environment.

## Quick start

In a fresh codespace, run the following in **separate terminal tabs**:

```bash
# Tab 1 — start the monolith
script/server

# Tab 2 — seed IPM data (no billing surfaces)
script/in-product-messaging/setup
```

Then log in as any of the seeded IPM users. The script prints the full list at
the end of its run; passwords are all `passworD1`.

## Setup with billing-related functionality

Surfaces that depend on the billing platform (budget threshold banners, usage
alerts, cost-center spend warnings, etc.) require `github/billing-platform` to
be running locally and a richer set of seeded fixtures. Use the
`--with-billing` flag.

In **three separate tabs**:

```bash
# Tab 1 — start the monolith
script/server

# Tab 2 — clone, configure, and start billing-platform
script/setup-codespaces-billing-platform   # one-time per codespace
cd ../billing-platform
script/server

# Tab 3 — seed IPM data plus budget alert fixtures
script/in-product-messaging/setup --with-billing
```

`--with-billing`:

- Creates the same IPM seed data as the no-flag run.
- Creates 9 additional accounts with active budget alerts, one per
  `(target × threshold)` combination:
  - 3 organizations (75% / 90% / 100%)
  - 3 enterprises (75% / 90% / 100%)
  - 3 cost centers (75% / 90% / 100%)
- Bulk-syncs **every** `Customer` to billing-platform (via
  `Billing::UpdateCustomerInBillingPlatformJob`) so usage events route
  correctly.
- Creates the budgets and seeds enough usage on each one to cross its
  configured threshold so the warning banner actually renders.

When the script finishes, log in as any of the seeded admin accounts. The
budget banner appears on the **billing overview** for the relevant
organization or enterprise. Examples:

| Account                              | Password    | Banner location                                                              |
| ------------------------------------ | ----------- | ---------------------------------------------------------------------------- |
| `ipm-budget-alert-75-organization`   | `passworD1` | `http://github.localhost/organizations/ipm-budget-alert-75-org-org/settings/billing` |
| `ipm-budget-alert-90-organization`   | `passworD1` | `http://github.localhost/organizations/ipm-budget-alert-90-org-org/settings/billing` |
| `ipm-budget-alert-100-organization`  | `passworD1` | `http://github.localhost/organizations/ipm-budget-alert-100-org-org/settings/billing` |
| `ipm-budget-alert-75-enterprise`     | `passworD1` | `http://github.localhost/enterprises/ipm-budget-alert-75-ent-biz/settings/billing`   |
| `ipm-budget-alert-90-enterprise`     | `passworD1` | `http://github.localhost/enterprises/ipm-budget-alert-90-ent-biz/settings/billing`   |
| `ipm-budget-alert-100-enterprise`    | `passworD1` | `http://github.localhost/enterprises/ipm-budget-alert-100-ent-biz/settings/billing`  |

> **Note:** the banner is on the billing **overview** page (`/settings/billing`),
> not the Budgets sub-page (`/settings/billing/budgets`).

The full seeded login list (including non-billing IPM users) is printed by the
script when it finishes — scroll back through the terminal output in tab 3 to
find the user you want.

## Resetting

The script destroys and re-creates seed data on every run, so simply re-running
it is the canonical way to reset to a known state.

To wipe seed data without re-creating it:

```bash
script/in-product-messaging/setup --destroy
```

For QA runs, prefer the [pre-flight wrapper](#qa-pre-flight) below — it
combines a `git pull` and re-seed in one step against a remote codespace.

## QA pre-flight

Before kicking off an IPM `/qa` batch, always re-sync the codespace and re-seed
data in one shot:

```bash
bash script/in-product-messaging/qa/prep-codespace.sh
```

The script auto-detects the unique `Available` `github/github` codespace,
refuses to proceed if the working tree is dirty, fast-forward-pulls the
checked-out branch, and re-runs `script/in-product-messaging/setup`. Override
the codespace with `--codespace NAME` or `IPM_CODESPACE=NAME` if you have more
than one.

The qa skill is configured (via [`qa/setup.md`](./qa/setup.md)) to invoke this
script automatically before every test batch targeting `github.localhost`, so
runs always start from a known state.

## Caveats

- **`PreventFurtherUsage` budgets are not created in dev.** `copilot_enterprise`
  is a high-watermark / user-months SKU and billing-platform only allows
  `PreventFurtherUsage` for GHAS SKUs. All seeded budgets are `AlertingOnly`,
  which produces the `:warning` (yellow) banner variant. The `:critical` (red)
  variant requires `PreventFurtherUsage` and isn't reachable with the
  Copilot-based fixtures.
- **Re-running adds usage on top of existing budgets.** `--with-billing`
  uses `create_or_update_budget`, which is idempotent for the budget config,
  but each run injects another round of usage events. To start fresh, run
  `--destroy` first.
- **`script/setup-codespaces-billing-platform` is one-time.** It clones
  `github/billing-platform` into `/workspaces/billing-platform` and bootstraps
  it; you only need to run it once per codespace. After that, just
  `cd ../billing-platform && script/server`.

## Related

- IPM surfaces tracked in [github/in-product-messaging](https://github.com/github/in-product-messaging)
- billing-platform repo: [github/billing-platform](https://github.com/github/billing-platform)
- The script itself: [`script/in-product-messaging/setup`](./setup)
