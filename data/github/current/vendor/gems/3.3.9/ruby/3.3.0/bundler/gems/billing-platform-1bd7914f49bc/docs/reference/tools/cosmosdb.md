# CosmosDB

On the biggest mind/tech shifts we have in billing platform is moving from relational databases to NoSQL using CosmosDB. Keep that in mind while reading the rest of that doc and in general while onboarding to the project, because it’s essential to understand how that shift affects data modeling for our system.

## Table of Contents

- [Details](#details)
  - [CoreSQL API](#coresql-api)
  - [Differences between CosmosDB and a SQL database](#differences-between-cosmosdb-and-a-sql-database)
  - [Visualizing usage in logical partitions](#visualizing-usage-in-logical-partitions)
  - [Connections and Caching](#connections-and-caching)
- [Troubleshooting](#troubleshooting)
  - [Identify hot partitions and high RU consumption](#identify-hot-partitions-and-high-ru-consumption)
- [References](#references)

## Details

### CoreSQL API

We're using the [Core (SQL) API](https://learn.microsoft.com/en-gb/azure/cosmos-db/nosql/) for CosmosDB which is their native solution opposed to the drivers for the third party dbs (e.g. MongoDB, Cassandra or Gremlin) they have.

### Differences between CosmosDB and a SQL database

One of the main differences compared to the usual db structure is that we don't have tables (at least not explicitly). Instead, we're using items which are stored in a container:

https://learn.microsoft.com/en-us/azure/cosmos-db/account-databases-containers-items#azure-cosmos-containers

> Containers are schema-agnostic. Items within a container can have arbitrary schemas or different entities so long as they share the same partition key. For example, an item that represents a customer and one or more items representing all their orders, can be placed in the _same container_. By default, all data added to a container is automatically indexed without requiring explicit indexing.

Instead of tables we have a set of keyspaces which define what data is represented in what keyspace. Those keyspaces are created by defining a partition key during container creation. Read more about partitioning in CosmosDB [from their official docs](https://learn.microsoft.com/en-us/azure/cosmos-db/partitioning-overview).

For example to load the pricing info, one could use a following query:

```sql
SELECT * FROM c WHERE c.partitionKey = "pricing"
```

Which gives you all the items from the current container `c` under partition `pricing`.

Not all of our partition keys are statically defined like `pricing`, most of them are constructed based on a pattern that defines what stored under that partition. For example, partition key with value `<customer-id>:<sku-name>:yyyy:mm:dd:hh` contains billable documents for the customer with `customer-id` and product SKU with `sku-name` for the given hour.

So instead of having a huge table for all the customers, CosmosDB allows us to flatten it out and have a lot of logical partitions for each customer/date. The diagram below shows some of the keyspaces we have at the moment and their relations to each other:

![db diagram](/docs/images/db_diagram.png)

There is no limit to the number of logical partitions in your container. And CosmosDB guarantees access to the logical partitions in constant time regardless of the overall container size.

---

[There is a video walkthrough where we give a general overview of how we use CosmosDB](https://github.rewatch.com/video/ao6dthmk49vz4dms-vnext-happy-path-v0-weekly-sync-walkthrough-of-db-structure?t=855) (_starts at 14:15_).

### Visualizing usage in logical partitions

A mental model to visualize how usage data is grouped based on the partition key is similar
to a calender UI.

Take the MacOS default calendar app. You're able to toggle the timeframe you're viewing
between Day, Week, Month, and Year.

In the view for `Day`, each row represents one hour within the day.

![macos calendar app for a single day](/docs/images/calendar_day.png)

Changing to `Year`, each block represents one month within the year.

![macos calendar app for a full year showing each month of the year](/docs/images/calendar_year.png)

---

Partition keys in our system match the same granularity of data.

Here's a query to get usage for a particular day:

```sql
SELECT * FROM c WHERE c.partitionKey = "customer_id:sku:year:month:day"
```

The result contains 24 documents - one document per hour of the day. From our
calendar example, think of each object as a row in the table. The entire day
is a sum of all hours within the day.

```json
[
 {
  "partitionKey": "1:actions_beta_self_hosted_runner:2023:2:10:1",
  "id": "37f266ee-36d6-4b62-9bd3-407fe9590268",
  ...
 },
 {
  "partitionKey": "1:actions_beta_self_hosted_runner:2023:2:10:2",
  "id": "2cbc50dc-903a-4850-8e71-7e159aca7f5e",
  ...
 },
 {
  "partitionKey": "1:actions_beta_self_hosted_runner:2023:2:10:3",
  "id": "5d50c891-d5f7-4e8a-a408-1d23c446274e",
  ...
 },
 ...
]
```

Now let's query for usage for a particular year:

```sql
SELECT * FROM c WHERE c.partitionKey = "customer_id:sku:year"
```

The result contains 12 documents - one document per month of the year. From our
calendar example, think of each object as a month within the grid. The entire year
is a sum of all months within the year.

```json
[
 {
  "partitionKey": "1:actions_beta_self_hosted_runner:2023:1",
  "id": "31c589f6-304e-448a-8dae-8d89f2359dd1",
  ...
 },
 {
  "partitionKey": "1:actions_beta_self_hosted_runner:2023:2",
  "id": "a20fbdae-2ef1-48ed-a4d0-78e20a5d27a3",
  ...
 },
 {
  "partitionKey": "1:actions_beta_self_hosted_runner:2023:3",
  "id": "23957d36-ea1c-48a9-aa9c-50cbfb99bb42",
  ...
 },
 ...
]
```

### Connections and Caching

There are two [connection modes](https://learn.microsoft.com/en-us/azure/cosmos-db/dedicated-gateway) between an application and Cosmos; **Direct Mode** and **Gateway Mode**. When connecting in Direct mode, the application connects directly to the database. With Gateway Mode, the application connects to a front end node that will then route the request to appropriate backend node.

The Billing Platform makes use of both of these connection modes. We do this to take advantage of the [integrated caching](https://learn.microsoft.com/en-us/azure/cosmos-db/integrated-cache) provided by the Gateway Mode connection.

![diagram of where the cosmos db endpoing sits in relationship to the Azure cloud](https://learn.microsoft.com/en-us/azure/cosmos-db/media/dedicated-gateway/connection-policy.png)

In order to connect via both Direct and Gateway Modes we provide two different connection strings and create two different database connections, as seen in the `Database` struct:

```go
type Database struct {
 connection        *Connection
 gatewayConnection *Connection
 ...
}
```

#### Using the Gateway Connection (and Caching)

The choice to use the Gateway Connection and it's caching is made at the buisness logic level by chosing a `Querier` to make your read request.

To use a Direct Connection (with no caching) use the `Querier` returned by `NewQuerier`:

```go
product, err := db.GatewayQuerier[*models.Product](p.db).ReadItem(ctx, productKey, nil)
```

If you would like to use the Gateway Connection with a cache use `NewGatewayQuerier`:

```go
product, err := db.NewGatewayQuerier[*models.Product](p.db).ReadItem(ctx, productKey, nil)
```

These both return `Querier` objects but the `NewGatewayQuerier` will use the `database.gatewayConnection.ContainerClient` as apposed to the Direct client.

#### Cache Details

The current (default) consistency level for reads and writes is [Session Consistency](https://learn.microsoft.com/en-us/azure/cosmos-db/consistency-levels#session-consistency). However, when using the cache we set the consistency level to [Eventual Consistency](https://learn.microsoft.com/en-us/azure/cosmos-db/consistency-levels#eventual-consistency) since gateway requests with session consistency incur RU charges when no session token is provided. Unfortunately, the Go SDK has no built in mechanism to manage session tokens at the time of writing per https://github.com/Azure/azure-sdk-for-go/issues/18987.

The current (default) `MaxIntegratedCacheStaleness` is 5 minutes. At the time of writing, there is no way to tune this via the Go SDK. The value of `MaxIntegratedCacheStaleness` is the maximum, in practice we see the cache being invalidated much faster than this.

The purpose of the cache isn't really to increase read latency (reads should be pretty fast already) but to decrease read cost:

_Point reads and queries that hit the integrated cache will have an RU charge of 0. Cache hits will have a much lower per-operation cost than reads from the backend database._

## Troubleshooting

### Identify hot partitions and high RU consumption

To get started, log into the Azure portal and find the CosmosDB instance you'll diagnose.

In the side menu, you'll find an entry for logs:

![side menu in the Azure portal with the Logs entry highlighted](/docs/images/cosmos_logs_sidemenu.png)

Upon entering the page, you'll be presented with a Queries modal.

![Azure portal Queries page showing alerts](/docs/images/cosmos_logs_query_modal.png)

This will give you access to query templates you can use. Feel free to leverage these where appropriate, they're a great resource! For now, exit the modal in the top right. Instead we're going to make use of some Azure-provided queries found in this [doc](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/troubleshoot-request-rate-too-large?tabs=resource-specific#how-to-identify-the-hot-partition).

To diagnose RU consumption, find the query labelled `How to get the information about the partition keys RU/s consumption per second?`.

For ease of access, we've included it here:

```kusto
CDBPartitionKeyRUConsumption
| summarize total = sum(todouble(RequestCharge)) by DatabaseName, CollectionName, PartitionKey, TimeGenerated
| order by TimeGenerated asc
```

Paste this into the query editor.

![Query editor screenshot with kusto query above pasted in](/docs/images/cosmos_logs_query_editor.png)

You'll then select a time range above the query editor. This defaults to the past 24 hours.
We'd recommend shortning the time window as we're charged per-query. Instead, opt
for a shorter relative timeframe such as `Last hour`, or select the `Custom` option
if you know a point-in-time of particular interest.

![Dropdown in query editor with `Last hour` highlighted](/docs/images/cosmos_logs_query_time_range.png)

When you're ready, click `Run` to execute your query.

## Diagnose the database

The result set will appear after a few seconds underneath the query editor.

![Results from the query with DatabaseName, CollectionName, PartitionKey and TimeGenerated(UTC)](/docs/images/cosmos_logs_query_results.png)

The fields of interest to diagnose hot partitions & RU consumption will be `PartitionKey` + `total`.

With the according timestamp, you'll be able to clearly see any outlier in terms of
request charge against a particular partition.

---

Here's a more complex query found in the Azure docs linked above
(be sure to change `CollectionName` based on your database):

```kusto
CDBPartitionKeyRUConsumption
 | where TimeGenerated >= ago(1hour)
 | where CollectionName == "CollectionName"
 | where isnotempty(PartitionKey)
 // Sum total request units consumed by logical partition key for each second
 | summarize sum(RequestCharge) by PartitionKey, OperationName, bin(TimeGenerated, 1s)
 | order by sum_RequestCharge desc
```

## References

- [CoreSQL API](https://learn.microsoft.com/en-gb/azure/cosmos-db/nosql/)
- [Azure CosmosDB Containers](https://learn.microsoft.com/en-us/azure/cosmos-db/account-databases-containers-items#azure-cosmos-containers)
- [Partitioning in CosmosDB](https://learn.microsoft.com/en-us/azure/cosmos-db/partitioning-overview)
- [Rewatch video about how we use CosmosDB](https://github.rewatch.com/video/ao6dthmk49vz4dms-vnext-happy-path-v0-weekly-sync-walkthrough-of-db-structure?t=855)
- [CosmosDB Connection Modes](https://learn.microsoft.com/en-us/azure/cosmos-db/dedicated-gateway)
- [CosmosDB Integrated Cache](https://learn.microsoft.com/en-us/azure/cosmos-db/integrated-cache)
- [CosmosDB Session Consistency](https://learn.microsoft.com/en-us/azure/cosmos-db/consistency-levels#session-consistency)
- [Monitor Azure Cosmos DB data by using diagnostic settings in Azure](https://learn.microsoft.com/en-us/azure/cosmos-db/monitor-resource-logs?tabs=azure-portal)
- [Troubleshoot issues with diagnostics queries](https://learn.microsoft.com/en-us/azure/cosmos-db/monitor-logs-basic-queries)
- [Diagnose and troubleshoot Azure Cosmos DB request rate too large (429) exceptions](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/troubleshoot-request-rate-too-large?tabs=resource-specific#how-to-identify-the-hot-partition)
