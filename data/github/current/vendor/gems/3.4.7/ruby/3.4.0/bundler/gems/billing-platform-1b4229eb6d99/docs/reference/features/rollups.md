# Rollups

To put it simply, rollups in `billing-platform` are persisted usage aggregations grouped by some unit of time and some set of categorical dimension(s) that we designate. The units of time that we use are hourly, daily, and monthly. In addition to "rolling up" by date, we can also choose to group by categorical dimensions such as a customer id, org ids, repo ids, SKU etc. Ultimately, a rollup is defined by its `(partitionKey, id)` pair (this pair also is a globally unique key in a given Cosmos container).

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [What is rolled up](#what-is-rolled-up)
  - [How are rollups performed](#how-are-rollups-performed)
  - [How do we aggregate rollups](#how-do-we-aggregate-rollups)
  - [Billing Platform Rollup Example](#billing-platform-rollup-example)
- [References](#references)

## Terminology

- **Entity**: An enterprise, organization, user, or repository.
- **Rollup**: A CosmosDB document that summarizes the usage by a particular entity at a point in time of a particular product or SKU.

## Details

### What is rolled up

We rollup usage by time periods, repo, repo with sku, etc. to support queries such as:

- Usage for today
- Usage for the current month
- Usage for this particular repository
- Usage for this particular organization with SKU line items

![Diagram of aqueduct to billing platform, where billing platform writes a line item and then rolls up the job](/docs/images/main_diagram.png)

### Where are rollups used

Currently the two use cases where we use rollup data are our new enterprise usage charts ([1](https://github.com/enterprises/avocado-corp/billing), [2](https://github.com/enterprises/avocado-corp/billing/usage)) and when we fetch product, SKU usage totals when billing customers for their metered usage through Zuora and Azure. Both of these use cases relate to metered usage product offerings here at Github.

### How are rollups performed

> [!NOTE]
> Our rollups in `billing-platform` are modeled and persisted in CosmosDB. If you want to imagine what this would mean within the context of a relational database. You can think of rollups as precomputed SQL `GROUP BY` statements. For example something like `SELECT SUM(quantity), SUM(billedAmount) FROM usage_flat GROUP BY customer_id, SKU, YEAR(record_date), MONTH(record_date)` could represent a common rollup partition that we use currently.

As it stands right now we have a stream based system for creating rollups. It all starts with an individual usage item that makes its way from our various partner/product teams to `billing-platform`, which is where we persist, process, and invoice the metered usage of our customers.

#### Raw Line Item Ingestion

When first receiving usage in `billing-platform`, one of the first things that our platform does is persist it as a raw usage line item in our CosmosDB container. The raw line item that we persist looks like this:

```sql
SELECT * FROM c
WHERE c.id = "billable" AND c.partitionKey = "9e080793-de82-4321-a744-112c5e2003ea"
```

```json
//Result
{
  "partitionKey": "9e080793-de82-4321-a744-112c5e2003ea",
  "id": "billable",
  "BilledAmount": 17000000000,
  "Quantity": 34000000000,
  "AppliedCostPerQuantity": 500000000,
  "FractionalQuantity": 0,
  "Pricing": {
    "partitionKey": "pricing",
    "id": "product-1_sku-1",
    "Price": 500000000,
    "Product": "product-1",
    "Sku": "product-1_sku-1",
    "MeterType": 0,
    "FriendlyName": "SKU 1",
    "AzureMeterId": "19248bbc-65b6-4df7-8d9a-3c101d330e98",
    "EffectiveDatePrices": [],
    "FreeForPublicRepos": false,
    "EffectiveAt": 1658933038
  },
  "EntityDetail": {
    "CustomerId": "82138",
    "OrganizationId": 670997,
    "RepositoryId": 691483,
    "ActorId": 931029,
    "CostCenterDetail": {
      "EnterpriseCustomerId": "82138",
      "CostCenterUUID": "",
      "IsCostCenterProxy": false
    }
  },
  "SourceUri": "git://run/id",
  "UsageAt": 1289707200000,
  "_rid": "x1AxALINkowMAAAAAAAAAA==",
  "_self": "dbs/x1AxAA==/colls/x1AxALINkow=/docs/x1AxALINkowMAAAAAAAAAA==/",
  "_etag": "\"95008cba-0000-0700-0000-64c282af0000\"",
  "_attachments": "attachments/",
  "_ts": 1690469039
}
```

> [!NOTE]
> In addition to the item above with `{ ... "id": "billable, ... }` we also store the same exact item multiple times except with a different `partitionKey` and `id`. The reason for this is to simplify our API that we use to fetch `*:<year>:<month>:<day>:<hour>` based usage from.

#### Rollup Processing

Following the ingestion of these native line items, we create various rollup jobs that get queued to be processed by our rollup workers. Most of this happens via Aqueduct. The queues/worker rollup queues are:

| Queue/Worker Type                    |
| ------------------------------------ |
| customer-daily-rollups               |
| customer-monthly-rollups             |
| customer-yearly-rollups              |
| customer-azure-emission-daily-rollup |
| customer-zuora-emission-daily-rollup |

These logical groups are all in charge of handling creating or patching rollup records for various logical partitions. These logical groups could change in the future. The critical thing to know here is that we create rollup records on a basis of the `(partitionKey, id)` pairs that we define which contain a date component and an entity identifier component (customer id, org id, repo id etc).

![partition key (`<otherdimensions>:<year>:<month>:<day>`) and id (`<otherdimensions>:<year>:<month>:<day>:<hour>`)](/docs/images/partition_example.png)

### How do we aggregate rollups

It's important to outline how we bucket individual line items into their respective rollup record to be aggregated. We do this based on the `(partitionKey, id)` pairs we define. The actual values we use to populate an item's `partitionKey` and `id` are based on the content of the raw usage line item. This is best shown by a simple diagram:

![Raw line item and how it maps to the partition keys that we define](/docs/images/aggregation_diagram.png)

When it comes to metered usage and their rollups, the two values that we aggregate in our rollup records are `quantity` and `billedAmount`.

### Billing Platform Rollup Example

The following example will attempt to illustrate what has been explained so far. We will show `billing-platform` ingesting 3 consecutive units of usage, all from the same customer. Let's assume that we are starting with no pre-existing usage in the database and that there are only `customer-*-rollup` based rollups, that only deals creating rollups for two partitions, `<customerId>:<sku>:<usageDate>` and `<customerId>:<product>:<usageDate>`.

> [!NOTE]
>`billing-platform` creates other rollup records with different partitions in addition to the ones mentioned in the example. I've simplified this example to make things more clear.

#### Usage 1

On Dec 21st, we receive our first usage item which is a `actions-linux` usage item whose usage occurred at December 21, 2023, 8am. So we'll process it in `billing-platform` and that will look like so:

![diagram of how product rollups are performed](/docs/images/usage1.png)

To Recap

1. We ingest it and persist that raw line item to our database
2. We create roll up jobs and queue them to be processed by the queue's respective worker
3. Respective workers process the jobs which includes aggregating the line item against a corresponding rollup item. It will either create a rollup record or patch an existing one

After this item has been fully processed, we end up with 6 new rollup records.

> [!NOTE]
> All rollup records are created initially when we first see a record for a given `(partitionKey, id)` pair.

#### Usage 2

Next we'll show what happens when we receive usage for **a different SKU**, same product, same hour.

![diagram of how product rollups are performed](/docs/images/usage2.png)

> `<customerId>:<sku>:<usageDate>`

For this partition we will be create 3 new records rollup records. This is because although this usage happened in the same hour as "Usage 1", it's a brand new SKU therefore, making it unique in terms of `(partitionKey, id)`.

> `<customerId>:<product>:<usageDate>`

For this partition we didn't have to create new rollup records since the `(partitionKey, id)` values stayed the same. The record was an actions record like "Usage 1" and happened in the same hour. So in this case we simply aggregate the values to the pre-existing rollup records.

#### Usage 3

Finally we see our last piece of usage in this example. This usage is made on the next day but is the same SKU from first usage.

![diagram of how product rollups are performed](/docs/images/usage3.png)

> `<customerId>:<product>:<usageDate>`

Here we will see two new records because this is a new day. For the Yearly rollup we will be using the previous record from "Usage 1" because we have not changed month and there for we can roll up the quantity from this usage in that yearly rollup record, `PK:"201:actions:2023"` for the month.

> `<customerId>:<SKU>:<usageDate>`

Here we also create two new records, because despite having create records for `actions_linux` already, the usage is for a different day. Though here we can also lean on our yearly rollup record, `PK:"201:actions_linux:2023"`, that was created for "Usage 1"

## References

- [ADR: Remove Generic Product SKU Rollups](https://github.com/github/gitcoin/tree/main/docs/technical/architecture-decision-record/0045-remove-generic-product-sku-rollups.md)
- [General usage integration tests](https://github.com/github/billing-platform/blob/main/testing/integration-tests/usage_integration_test.go)
- [Repository usage integration tests](https://github.com/github/billing-platform/blob/main/testing/integration-tests/repo_integration_test.go)
- Relevant rollup files:
  - [usageHandler.go](https://github.com/github/billing-platform/blob/main/lib/messaging/handlers/usageHandler.go)
  - [rollupHandler.go](https://github.com/github/billing-platform/blob/main/lib/messaging/handlers/rollupHandler.go)
  - [customerDailyRollup.go](https://github.com/github/billing-platform/blob/main/lib/messaging/handlers/rollups/customerDailyRollup.go)
  - [customerMonthlyRollup.go](https://github.com/github/billing-platform/blob/main/lib/messaging/handlers/rollups/customerMonthlyRollup.go)
  - [customerYearlyRollup.go](https://github.com/github/billing-platform/blob/main/lib/messaging/handlers/rollups/customerYearlyRollup.go)
