# Actions Usage Metrics Time Range Queries

> :warning: This has been [superseded](./0479-kusto-data-warehouse-followers.md) and is no longer relevant except for historical context.

## Status

Proposed - 2023-11-29  
[Superseded](./0479-kusto-data-warehouse-followers.md) - May 2024

## Context

Actions Usage Metrics needs to support time range queries for the customer such as last 30 days, last 90 days, etc. so they can see their usage data aggregated in various time periods. This means we need to store the usage data in a way that supports these queries or we need to produce aggregates at query time.

Cosmos does not support having both a `GROUP BY` and `ORDER BY` in the same query, sorting by calculated fields, or ARRAY_AGG/make_list functions. Even if it did, the query would likely be too slow to be acceptable for the customer.

This document describes the options we considered for how to support these queries.

## Decision - Rollup Jobs

Implement periodic rollup jobs that aggregate usage data into time periods (e.g. last 30 days, last 90 days) and store the aggregated data in Cosmos. This will give us the performance, flexibility and SLA we need for the customer, with an impact on development time needed to support new time range queries.

### Pros - Rollup Jobs

1. Aggregated data is stored in a way that supports the queries the customer needs
1. We will likely need this optimization for large customers anyway

### Cons - Rollup Jobs

1. Supporting new time range queries requires code changes
1. Requires a scheduler and a job handler which adds complexity and another point of failure
1. Will need to figure out how to handle historical data if we encounter failures or need to change the rollup logic

## Alternatives

### Alternative 1 - Produce aggregated counts at query time in the API

We could potentially produce the aggregated counts at query time in the moda app. However, due to the size of the data the performance would be unacceptable.

#### Pros - API

1. This would be more flexible to support different queries in the future
2. Low level of effort to implement

#### Cons - API

1. The user experience would be poor because the query could take several seconds to group and sort the data
2. We will likely still need to implement rollup jobs for large customers, and most of the logic would be duplicated so might as well use the rollup job

### Alternative 2 - Produce aggregated counts at query time via Cosmos stored procedures

Cosmos provides the ability to write stored procedures in JavaScript. We could potentially write a stored procedure that groups and sorts the data and returns the aggregated counts. However, stored procedures have a [5 second timeout](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/stored-procedures-triggers-udfs#bounded-execution) and we would likely hit that timeout for large customers. JavaScript functions are also subject to [provisioned throughput capacity](https://learn.microsoft.com/en-us/azure/cosmos-db/request-units), which means they could potentially end up using a large number of request units within a short time and may be rate-limited if the provisioned throughput capacity limit is reached.

Due to these limiting factors, we decided not to pursue this option.

### Alternative 3 - Use a different data store for querying

Data stores we considered for querying (see [related ADR](/docs/adrs/0001-data-store.md)):

- Cosmos Analytical Store (CAS) - setup an Azure Link to the Cosmos Analytical Store and query the data in the Cosmos Analytical Store
- Elastic Search (ES) - send the projection data to Elastic Search and query the data in Elastic Search
- Kusto - send the projection data to Kusto and query the data in Kusto

Due to the pros and cons listed below, we decided not to pursue this option. We may revisit this option in the future if we find that the rollup jobs are not performant enough.

#### Pros - Different Data Store

1. These data stores would likely support the queries we need with better performance

#### Cons - Different Data Store

1. We would need to maintain a separate data store
2. We would need to implement a data sync process to keep the data in sync between the different data stores
3. We would incur additional costs for the different data store
4. Some queries will liklely still be slow due to the size of the data
5. Some of the data stores have no paved path for GHES (CAS, Kusto)
6. Kusto has a 99.9% SLA, Cosmos has a 99.999% SLA
