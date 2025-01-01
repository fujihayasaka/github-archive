# vNext Migration
This year (2024) and next, the metered billing team is looking to migrate our metered customers from meuse to vNext. This document is an explanation of the work we have done so far.

### Relevant issues
Migration experience for enterprises migrated from Meuse to BvN [#15302](https://github.com/github/gitcoin/issues/15302) \
Updates to usage reports to be fetched from Data warehouse [#16822](https://github.com/github/gitcoin/issues/16822)

## Migration UX for enterprises

When planning this platform migration for our customers, we wanted to make the UX experience as seamless and friction free as possible. The UX migration experience is summarized by the following diagram:

![vnext migration ux flow](/docs/images/vnext_migration_ux_flow.png)

> [!NOTE]
> Two of the fields that we have introduced as a part of this migration work are `billing_platform_enabled_products.planned_migration_date` and
> `billing_platform_enabled_products.migration_date`. `planned_migration_date` is the expected migration date (populated during transition,
> more details below) whereas `migration_date` is the actual migraiton date (populated during onboarding).

### Transition Process

Today the process of migrating a customer from meuse to vNext is as follows:
1. We assign them `billing_platform_enabled_product.cohort_name` and `billing_platform_enabled_product.planned_migration_date` values via [this transition](https://github.com/github/github/pull/344422) (we update the CSV in this PR for every new cohort we want to start onboarding for). The `billing_platform_enabled_product.planned_migration_date` is used for sending out our migration advisory email and it also drives certain parts of the migration UI (see diagram above). `billing_platform_enabled_product.cohort_name` is just a tag to identify cohorts.
2. On migration day for a given cohort, we migrate the cohort from 1. via [our onboarding vNext migration page](https://admin.github.com/stafftools/billing/onboard_billing_platform_customers/new)

### Spending Limits migration to Budgets
Spending limits are migrated over to vNext as budgets using the following logic:

- For the "Shared Product" spending limit, create 2 separate Enterprise-level budgets on Billing Platform. One for "Actions" product and the other for "Packages" product.

- For "Codespaces" spending limit, create an Enterprise-level "Codespaces" product budget

- Each of the "Actions" and "Packages" budget should have the same target amount as the Meuse shared spending limit

- The "Codespaces" budget should have the same target amount as the Meuse codespaces spending limit

- If the spending limit in Meuse is "Unlimited", don't create a budget in Billing Platform

- If the spending limit in Meuse is the default "$0 limit", create a $0 budget in Billing Platform

- If the customer already has any budgets in Billing Platform, do nothing to avoid overwriting existing budget. This also makes the migration job idempotent and safe to rerun for a customer

## Legacy Reports in vNext
In an effort to continue minimizing our dependence on meuse, we've decided to source legacy reports (reports based on usage that was invoiced from meuse) from vNext. To accomplish this we are replicating relevant meuse SQL usage data in our billing kusto cluster, which is where `billing-platform` will source usage data when our migrated customers request a legacy report. The usage data found in our billing kusto cluster is based on daily snapshots of our meuse data. These snapshots mirror [this query](https://data.githubapp.com/sql/share/c0e5b318) which joins all of the relevant data in our usage report. This is meant to emulate our classic approach of generating usage reports in Dotcom.

> [!NOTE]
> [This query](https://data.githubapp.com/sql/share/c0e5b318) may come in handy if you are ever trying to debug a
> customer support issue around legacy usage reports in vNext.

When a **migrated** customer requests a legacy report, we first queue the request in `billing-platform` which eventually submits an export to Kusto in the same manner as our vNext reports. To learn more about our general flow for our usage reports see [this doc](./usage-reports.md). The major differences between what’s outlined in that doc and what we’ve built with legacy reports is the Kusto tables we use to source the data and the query we use to build the report.

### Report period for vNext legacy usage reports
The time range for the vNext legacy usage report is limited. On the first day of their migration we provide them with a
report that goes back 180 days. As their time on vNext increases, the time range for their legacy report decreases where the
start date is calculated based on a rolling window of 180 days. This is illustrated in the following diagram:

![time range for legacy report](/docs/images/legacy_report_start_end_diagram.png)

This implies that once it’s been 180 days or more since a customer has migrated to vNext, we will no longer offer them the option of generating a legacy report and they will only be able to generate vNext based metered usage reports.
