# Watermark

Watermark products are products that are billed over a unit of time. Examples of current watermark products include Actions storage and LFS (Large File Service) storage.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [How watermark products are billed](#how-watermark-products-are-billed)
- [Troubleshooting](#troubleshooting)
  - [Query customer events](#query-customer-events)
  - [Query customer daily event rollups](#query-customer-daily-event-rollups)
  - [Query hourly partition with line items created by the scheduled hourly job](#query-hourly-partition-with-line-items-created-by-the-scheduled-hourly-job)
  - [Query daily partition with line items created by the scheduled hourly job](#query-daily-partition-with-line-items-created-by-the-scheduled-hourly-job)
- [References](#references)

## Terminology

- **Delta event**: An event informing Billing Platform about a change (+/-) in the amount of usage used for a particular product.

## Details

### How watermark products are billed

Watermark products are billed for the amount of usage used per hour, such as the amount of Actions usage used at each hour of the day. Delta events are received from partner teams letting Billing Platform know about changes to the amount of usage and then Billing Platform emits usage each hour.

When reviewing watermark usage, it is important to note that billing platform calculates usage in GB/hours, but [Azure emission is tracked in GB/months](https://github.com/github/billing-platform/blob/main/lib/messaging/handlers/azureEmissionHandler.go#L109).

To do the conversion, divide the value found in the rollups and divide by 24*[days in the month]. 

#### Example
```
SELECT * FROM c WHERE c.partitionKey = "2024:6:18:byAzureEmission" AND c.id LIKE "%:%:2024:6:18"
=> c.FullQuantity = 7291067235240

SELECT * FROM c WHERE c.partitionKey LIKE "%:packages_storage:azureEmission:2024:6" AND c.id = "%:packages_storage:azureEmission:2024:6:18"
=> c.Quantity = 10.126482271
```

7291067235240/[days in month]/[hours in day] = 7291067235240/30/24 = 10126482271.2/(10^9) = 10.126482271 (The 10^9 division is to convert the value out of nano units). 

## Troubleshooting

### Query customer events

`SELECT * FROM c WHERE c.partitionKey = {customerId}:{productSku}:events:{year}:{month}`

This will show a list of all delta (+/-) events received by billing platform.

### Query customer daily event rollups

`SELECT * FROM c WHERE c.partitionKey = {customerId}:{productSku}:events:rollups`

This query will return all the daily rollups corresponding to a customer. When delta events are received, the quantity and fractional quantity is patched to the daily rollup.

### Query hourly partition with line items created by the scheduled hourly job

`SELECT * FROM where c.partitionKey = "{customerId}:{orgId}:{repoId}:{year}:{month}:{day}:{hour}"`

`SELECT * FROM where c.partitionKey = "9420649:137835442:658957877:2023:7:5:20"`

This partition will contain the line item(s) created by the hourly scheduled job. A separate line item should be created for each entity within an enterprise (i.e. separate orgs and repos).

> [!NOTE]
> If specifically looking at the org and repo information, it's important to use hourly rollups because the daily rollups won’t show individual repo/org line items.

### Query daily partition with line items created by the scheduled hourly job

`SELECT * FROM c WHERE c.partitionKey = 9420649:actions_storage:2023:6:29`

Same as above but will aggregate the information for separate orgs and repos within an enterprise.

## References

- [Hourly watermark job diagram](https://github.com/github/gitcoin/issues/11664)
- [Watermark meters in billing platform overview](https://docs.google.com/document/d/1Caj8J8i7Px2GBUrzepJrTbE-YIKrxNHArH4vCxvEIzE/edit)
- [PR](https://github.com/github/billing-platform/pull/595) with a diagram explaining watermark billing math
