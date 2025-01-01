# Azure Emissions

Emissions for usage in billing platform to Azure are performed once a day at 8am UTC, emitting the prior days usage.

Usage is emitted for customers and cost centers that have a billing target of Azure. Cost centers that are created with an Azure subscription ID will be billed to their own Azure subscription ID where as cost centers created without one are billed to their parent enterprise's.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [Dispatch emissions from Stafftools](#dispatch-emissions-from-stafftools)
  - [Azure emission flow](#azure-emission-flow)
  - [Emission states](#emission-states)
- [Troubleshooting](#troubleshooting)
  - [Query Azure emission rollups for a particular customer](#query-azure-emission-rollups-for-a-particular-customer)
  - [Query records in the PAv2 table](#query-records-in-the-pav2-table)
- [References](#references)

## Terminology

- **Common term**: definition

## Details

### Dispatch emissions from Stafftools

We can dispatch azure emissions directly via Stafftools given a date for any failed emissions in [this page](https://admin.github.com/stafftools/billing/trigger_azure_emission) which will allow you to specify a date for emission starting from a day ago in UTC between and up to 9 days ago. If it is the first or second day of a new month the emission date will be limited up to 48 hours ago. Customer (Enterprise) specific emissions can be dispatched from [this page](https://admin.github.com/stafftools/enterprises/avocado-corp/billing/trigger_azure_emissions).

### Azure emission flow

- Actions relay processor sends a usage event to billing platform usage ingestion queue
- Usage ingestion worker consumes item from queue and item gets rolled up into various partitions, including an Azure emission partition for the day (`<year>:<month>:<day>:byAzureEmission`)
- At 8AM UTC, we trigger Azure emission via a fan out job that sends a job for each record in **yesterdays** Azure emission partition to our Azure emission queue
  - Note we fan out jobs from yesterdays partition instead of todays as todays partition might still have new line items coming in
  - E.g. Azure emission is triggered on July 14th, 2023 at 8AM UTC. This emission will target all records from July 13th, 2023 (`2023:7:13:byAzureEmission`)
- The Azure emission worker processes jobs off the queue and attempts to emit to Azure table and queue service (PAv2)
  - If errors happen, they are added to the DLQ. Error can be viewed in [this graph](https://app.datadoghq.com/dashboard/aa7-aid-znj?fullscreen_end_ts=1689358654026&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1689185854026&fullscreen_widget=2730944712239194&utc_override=true&from_ts=1689184379124&to_ts=1689357179124&live=true)
- Emissions are stored in billing platform partition for the customer (`<customerID>:<SKU>:azureEmission:<year>:<month>`)

### Emission states

Azure emission records are recorded in billing platform to keep a record of emissions for customers and various metadata such as the azure partition key which is useful for future investigations.

Emission records can have [4 states](https://github.com/github/billing-platform/blob/0364a28268891ab24dc95be1b2cbbee3fb375c61/lib/models/azureEmission.go#L12-L18):

- Completed
  - E.g. successful emission
- Failed
  - E.g. failed to send usage to PAv2 table or queue service
- Ignored
  - E.g. quantity to emit is 0, we skip such instances
- Recorded (Deprecated)

## Troubleshooting

### Query Azure emission rollups for a particular customer

- Get all items for a specific customer in the Azure emission rollup for specific day in the example below we are searching for usage from July, 27th 2023. Be sure to replace `<customerId>` with the customer you are looking into.

```sql
SELECT
    c.partitionKey,
    c.id,
    (c.BilledAmount /1000000000 ) as BilledAmount,
    (c.Quantity / 1000000000) as Quantity,
    c.Pricing.Sku,
    c.Pricing.Product,
    c.EntityDetail.OrganizationId,
    c.EntityDetail.RepositoryId,
    c.EntityDetail.CustomerId
FROM c
WHERE c.partitionKey = "2023:6:27:byAzureEmission" AND c.id LIKE "<customerId>:%:2023:6:27"
```

- Get all Azure emissions for all SKUs for a customer in a month. In this query the month is July 2023.

```sql
SELECT c.partitionKey, c.id, c.AzurePartitionKey, c.MeterId, c.SubscriptionId, c.Quantity, c.Status, c.ErrorMEssage, c.GrossQuantity
FROM c
WHERE c.partitionKey LIKE "<customerId>:%:azureEmission:2023:6"
```

- Get Azure emissions for a customer for a specific day across all SKUs

```sql
SELECT c.partitionKey, c.id, c.AzurePartitionKey, c.MeterId, c.SubscriptionId, c.Quantity, c.Status, c.ErrorMEssage, c.GrossQuantity
FROM c
WHERE c.partitionKey LIKE "<customerId>:%:azureEmission:2023:6" AND c.id LIKE "<customerId>:%:azureEmission:2023:6:27"
```

### Query records in the PAv2 table

If you want to query records in the PAv2 table (Azure), you can query the billing platform emission record you want to investigate via:

```sql
SELECT c.AzurePartitionKey
FROM c
WHERE c.partitionKey = "<customerId>:<sku>:azureEmission:2023:6" AND c.id = "<customer_id>:<sku>:azureEmission:2023:6:27"
```

and then use the `AzurePartitionKey` to query the PAv2 usages table.

 ℹ️ If you don't have access to PAv2 data, follow [this guide](https://github.com/github/gitcoin/blob/main/docs/technical/azure/request-access-to-pav2-data.md) to request access.

1. Sign in to [Microsoft Azure portal](https://ms.portal.azure.com/#@microsoft.onmicrosoft.com/resource/subscriptions/c97a5a11-05c8-4607-90a8-6d8c6a5cb8c9/resourceGroups/billing-prod152pas/providers/Microsoft.Storage/storageAccounts/billingprod152pas/storagebrowser) with your Microsoft email and view the `billingprod152pas` resource
3. Navigate to "Storage Browser" -> "Tables" -> "usages"
4. Add a filter to the usages table with column "PartitionKey", type "String" and the value should be the value that was queried in billing platform

## References

- [Rewatch video on Azure emission](https://github.rewatch.com/video/x90o3aeyc8dvzg5x-billing-platform-azure-emission-e2e-walkthrough)
- [Azure integration info](https://github.com/github/gitcoin/tree/main/docs/technical/azure)
- [Azure Emission Dashboard](https://app.datadoghq.com/dashboard/aa7-aid-znj?from_ts=1686148502349&to_ts=1686162902349&live=true)
- [Admin DLQ Page to Process Failed Emissions](https://admin.github.com/stafftools/billing/dead_letter_queue)
- [Azure Production Storage Table](https://ms.portal.azure.com/?armendpointprefix=edge&bundlingKind=DefaultPartitioner&configHash=myFe3J0WAQBF&env=ms&helppanenewdesign=true&l=en.en-us&pageVersion=12.24.1.112.24.0.13502741.230707-2207#@microsoft.onmicrosoft.com/resource/subscriptions/c97a5a11-05c8-4607-90a8-6d8c6a5cb8c9/resourceGroups/billing-prod152pas/providers/Microsoft.Storage/storageAccounts/billingprod152pas/overview)
- [Request Access to PAv2 Data](https://github.com/github/gitcoin/blob/main/docs/technical/azure/request-access-to-pav2-data.md)
- [Trigger Azure Emission Stafftools Page](https://admin.github.com/stafftools/billing/trigger_azure_emission)
  - [User specific trigger emission page](https://admin.github.com/stafftools/enterprises/avocado-corp/billing/trigger_azure_emissions)
