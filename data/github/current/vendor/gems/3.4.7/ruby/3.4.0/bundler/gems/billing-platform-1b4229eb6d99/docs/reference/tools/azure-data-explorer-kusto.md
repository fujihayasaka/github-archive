# Azure Data Explorer (Kusto)

Azure Data Explorer, internally called "Kusto", is Microsoft's big data analytics platform.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [Data analytics use of Kusto](#data-analytics-use-of-kusto)
  - [Billing's Kusto cluster](#billings-kusto-cluster)
  - [Tuning Export Capacity](#tuning-export-capacity)
- [Troubleshooting](#troubleshooting)
  - [Group usage line items by day](#group-usage-line-items-by-day)
  - [Group discount line items by type](#group-discount-line-items-by-type-public-plan-etc)
  - [Granular usage report](#granular-usage-report)
- [References](#references)

## Terminology

- **Kusto cluster**: A Kusto cluster is a collection of databases, each of which can hold many tables.

## Details

### Data analytics use of Kusto

Usage data is collected in the billing system and rolled up into various partitions in our Cosmos DB to power our usage charts and carry out invoice generation. However, this data in Cosmos DB is not directly accessible to downstream consumers such as revenue reporting and sales analytics. With this, we distribute our billing data to both Kusto and Trino ([data.githubapp.com](https://data.githubapp.com/)) via [Hydro](hydro.md) messages.

The following diagram illustrates the flow of billing usage data from billing platform to Kusto and Trino:
![billing platform data flow](/docs/images/billing-platform-data-flow.png).

### Billing's Kusto cluster

Billing owns [a Kusto cluster](https://dataexplorer.azure.com/clusters/ghbillingprod.eastus) in which we [follow data from a leader cluster](https://learn.microsoft.com/en-us/azure/data-explorer/follower?tabs=csharp). This gives us read-only access to the tables we follow.

Currently, the tables we follow are:

- `database('hydro').billingplatform_v1_usage_line_item`
- `database('hydro').github_actions_v0_job_execution`
- `database('service_billing").meuse_usage_report_items`
- `database('snapshots').github_mysql1_repositories`
- `database('snapshots').github_mysql1_users`

> [!NOTE]
> `database('service_billing").meuse_usage_report_items` is used for legacy reports while the other are followed to generate vNext reports


### Tuning Export Capacity

Kusto has helper methods to display capacity policies. Capacity policies are used to control compute resources of data management operations in our Kusto cluster. We rely heavily on the `Export` operation so we want to tune our capacity for this.

First, display the cluster's capacity policy.

```kql
.show cluster policy capacity
```

By default a new cluster ships with the following export policy:

```json
{
  "ExportCapacity": {
      "ClusterMaximumConcurrentOperations": 100,
      "CoreUtilizationCoefficient": 0.25
  }
}
```

*The `.show capacity` command returns the cluster's calculated capacities based on each policies formula. Our billing Kusto cluster currently runs on the `Standard_L32s_v3` SKU which results in an export capacity of 16 by default.*

In order to prioritize CPU for usage report exports (since they are the most CPU intensive), we bump the `CoreUtilizationCoefficient` to `0.75` to allow us to run more exports at the same time.

We can update our policy via:

```kql
.alter-merge cluster policy capacity ```
{
  "ExportCapacity": {
    "CoreUtilizationCoefficient": 0.75
  }
}```
```

Doing this bumps our `DataExport` capacity (seen via `.show capacity`) from `16 -> 48`.

Here is the [equation from Azure](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/capacity-policy#export-capacity) for export capacity:

```kql
Minimum(ClusterMaximumConcurrentOperations , Number of nodes in cluster * Maximum(1, Core count per node * CoreUtilizationCoefficient))
```

If the capacity is still not enough after updating the policy, we have the following options:

- Spin up more nodes which would give us more cores, bumping the capacity per [the formula](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/capacity-policy#export-capacity)
- Upgrade our Kusto SKU to a SKU with more cores

## Troubleshooting

> [!NOTE]
> You can query data in Kusto via the following URL using your GitHub Azure account: https://dataexplorer.azure.com/clusters/gh-analytics.eastus/databases/actions_importer.

### Group usage line items by day

```sql
database('hydro').billingplatform_v1_usage_line_item
| where customer_id == {customer_id}
| project Date = format_datetime(todatetime(usage_at), "MM-dd-yyyy"), quantity, gross_amount, discount_amount, net_amount
| summarize
    quantity=sum(quantity),
    gross_amount=sum(gross_amount),
    discount_amount=sum(discount_amount),
    net_amount=sum(net_amount)
    by Date
| sort by Date asc
```

> [!NOTE]
> `{customer_id}` is a placeholder and will need to be updated with the customer ID you are looking to query.

### Group discount line items by type (public, plan, etc.)

```sql
database('hydro').billingplatform_v1_discount_line_item
| where customer_id == {customer_id} and todatetime(discounted_at) between (datetime('2023-08-01') .. datetime('2023-08-31'))
| summarize
    total_discount_amount=sum(discount_amount),
    total_discount_quantity=sum(discount_quantity)
    by sku, discount_type
```

> [!NOTE]
> `{customer_id}` is a placeholder and will need to be updated with the customer ID you are looking to query.

### Granular usage report

This is the query that powers usage reports for billing platform GA as proposed in https://github.com/github/metered-billing/discussions/91.

```sql
database('hydro').billingplatform_v1_usage_line_item
    | where todatetime(usage_at) between(startofday(now(), -8) .. endofday(now(), -1))
    | where customer_id == 1061737
    | extend check_run_id=tolong(replace_string(source_uri, 'gid://git-hub/CheckRun/', ''))
| join kind=leftouter (database('hydro').github_actions_v0_job_execution  | where todatetime(end_time) between (startofday(now(), -8) .. endofday(now(), -1)) | project workflow_name, check_run_id) on check_run_id
| join kind=leftouter (database('snapshots').github_mysql1_repositories_current | project id=tolong(id), repository_name=name) on $left.repo_id==$right.id
| join kind=leftouter (database('snapshots').github_mysql1_users_current | where type=='User' | project id=tolong(id), username=login) on $left.actor_id==$right.id
| join kind=leftouter (database('snapshots').github_mysql1_users_current | where type=='Organization' | project id=tolong(id), organization=login) on $left.org_id==$right.id
| project
    usage_at,
    product,
    sku,
    quantity,
    unit_type,
    applied_cost_per_quantity,
    gross_amount,
    discount_amount,
    net_amount,
    username,
    organization,
    repository_name,
    workflow_name,
    cost_center.name
```

> [!NOTE]
> `{customer_id}` is a placeholder and will need to be updated with the customer ID you are looking to query.
> If copying this query and looking to add a new time range for usage, don't forget to update the time range on the `end_time` in the `github_actions_v0_job_execution` join

## References

- [What is Azure Data Explorer?](https://learn.microsoft.com/en-us/azure/data-explorer/create-cluster-and-database?tabs=free)
- [The Hub: Kusto](https://thehub.github.com/epd/engineering/products-and-services/actions/kusto/)
- [Capacity polices](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/capacity-policy)
- [Billing Kusto cluster](https://dataexplorer.azure.com/clusters/ghbillingprod.eastus)
- [Follower databases](https://learn.microsoft.com/en-us/azure/data-explorer/follower?tabs=csharp)
