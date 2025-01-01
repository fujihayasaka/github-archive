# Actions Usage Metrics Data Store

> :warning: This has been [superseded](./0479-kusto-data-warehouse-followers.md) and is no longer relevant except for historical context.

## Status
Proposed - 2023-09-11  
[Superseded](./0479-kusto-data-warehouse-followers.md) - May 2024

## Context

Actions Usage Metrics is being developed as the replacement for Actions Insights. Actions Insights was built on the now deprecated insights-dataplatform, which was built on VSSF + MSSQL Column Store.

We plan to rebuild Actions Usage Metrics with standard GitHub paved paths such as Golang based Moda services, React Primer frontend, and recommended datastores and message brokers. The experiences we intend to deliver are described at https://github.com/github/c2c-actions/discussions/7581. 

This ADR describes the data store we plan to use for the backend, replacing insights-dataplatform. This data store will be used to store raw usage events as needed as well as to store materialized views/projections/aggregations to support efficient querying. This ADR does NOT intend to describe the particular data model / partitioning schemes / etc which should be covered in later ADRs.

## Decision

Use **Cosmos DB** as the data store for Actions Usage Metrics.

This decision was reached from multiple dimensions.

### GitHub Data Store Guidelines
The Data Patterns team has [recommendations](https://thehub.github.com/epd/engineering/dev-practicals/data-services-guidelines) and stresses that in general teams "should only consider the following supported options". Out of those options, only MySQL, MySQL + Vitess, and CosmosDB are reasonable considerations for our scenarios. We reached out to them as well to confirm this and the general sentiment was agreement that we should use MySQL or CosmosDB based on data size.

### Insights Data Platform successors / other use at GitHub
Following the above, we looked into what other teams are using - including the following teams working on Insights related scenarios who were also affected by the deprecation of insights-dataplatform:
* Billing Platform (which also consumes usage-related events) is using `CosmosDB`. Their data size/shape/query patterns are relatively similar to ours although potentially more constrained to specific time periods / "rollups".
* Security Products / GHAS Analytics is using `MySQL` as they have a strong need to immediately be on GHES (and Cosmos support in GHES is coming but not yet available) 
* OSPO is using `MySQL` as they want to build their feature entirely in the monolith rather than a separate Moda app
* Data Warehouse (internal use only) stores raw hydro events in `Kusto` for arbitrary queriability
* Hosted Compute Insights (e.g. runner network logs) is using `CosmosDB`

Cosmos is also used by various other teams at GitHub.

### Data Size

#### Raw Events
Looking just at the raw events that currently exist (especially `compute_usage` currently used for job-level usage), we can get a rough estimate of the total and per-customer data sizes:

<details>
<summary>Kusto Query</summary>

```
cluster("ghdwprod.eastus").database("hydro").github_actions_v0_compute_usage
| where timestamp > ago(30d)
| summarize DataSizeMonthlyBytes = sum(estimate_data_size(runner_runtime, external_job_id, workflow_job_id, workflow_file_path, started_at, usage_mins, repository_id, repository_visibility, completed_at, invoking_user_id, runner_type, runner_properties, queued_at, check_run_conclusion, invoking_event_type, repository_owner_id, check_run_id, usage_ms, check_suite_id, workflow_name, job_name, workflow_run_id, job_user_identifier, workflow_run_attempt))
| project DataSizeMonthlyGB = DataSizeMonthlyBytes / 1024 / 1024 / 1024
| project DataSizeYearlyGB = DataSizeMonthlyGB * 12;
```
</details>

`DataSizeYearlyGB` = `2424GB`

While it's unlikely that we enable Usage Metrics by default with yearly retention for all customers, it shows that storing raw job-level data - not even including any materialized views of the data or any other future events we may consume - could potentially exceed 2T. Based on this and the data service guidelines, MySQL (without Vitess) is probably not the best choice for scalability.

Evaluating Cosmos, a key limitation is that a partition must be at most 20GB. Based on data warehouse estimates, our largest customer produces ~24GB or ~65 million of this specific event per year. This means that to store raw data, our partitioning scheme will need to subdivide events (e.g. by time or other dimension). This is not a significant problem.

#### `ActionsWorkflowUsage` rows

We won't end up querying on the raw event data, but will need to materialize it into different view(s) to satisfy our desired queries.

Using (an approximation of) the existing insights-dataplatform model for Actions Insights and summarizing events by `(Workflow, Repository, Runner Type)`, we can get some estimates for the number of rows/items to expect.

<details>
<summary>Kusto Query</summary>

```
cluster("ghdwprod.eastus").database("hydro").github_actions_v0_compute_usage
| where timestamp > ago(30d)
| summarize by workflow_file_path, repository_id, runner_runtime, runner_type, repository_owner_id
| summarize ActionsWorkflowUsageRows=count() by repository_owner_id
| summarize count() by bin(ActionsWorkflowUsageRows, 10000)
| project NumRows=strcat(ActionsWorkflowUsageRows, " - ", ActionsWorkflowUsageRows + 10000), count_
| order by count_ desc
```

</details>

| NumRows        | count_   |
| -------------- | -------- |
| 0 - 10000      | 1369525 (and looking further, almost all are < 1000) |
| 10000 - 20000	 | 11       |
| 20000 - 30000	 | 1        |
| 30000 - 40000	 | 3        |
| 40000 - 50000  | 1        |
| 90000 - 100000 | 1        |

The overwhelming majority of our customers will have < 1000 `workflow-repo-runner` items per time unit presented, as only a few customers have their usage spread across a huge number of different repos/workflows/runner types. Even for the largest customer, if we look at how their actual usage is spread out, daily summarization would still be < 300k rows per month:

<details>
<summary>Kusto Query</summary>

```
cluster("ghdwprod.eastus").database("hydro").github_actions_v0_compute_usage
| where timestamp > ago(30d)
| summarize by workflow_file_path, repository_id, runner_runtime, runner_type, repository_owner_id, ts=bin(timestamp, 1d)
| summarize ActionsWorkflowUsageRows=count() by repository_owner_id, ts
| where repository_owner_id == 94558578
| summarize sum(ActionsWorkflowUsageRows)
```

</details>

`295797` (and weekly summarization at ~170k)

Some quick prototyping on Cosmos shows that range queries are still very performant w/ extremely low RU charge, although aggregation/summations across all of the data may be prohibitive and require materializing data in different shapes. Querying across 2 partitions (i.e. across month boundaries) may be necessary in some cases and is described later in this document.

In short, storing raw events (individual job executions) is not appropriate in MySQL, but works fine in Cosmos with appropriate partitioning. We want to be able to store raw events to be able to materialize new views as needed while controlling data retention ourselves. The size of processed data ("materialized views") is not a significant consideration with reasonable data modeling, although for a few of our largest customers may require special partitioning / data modeling.

### Predictable performance and cost

One of the major benefits of Cosmos is (at least compared to SQL) the predictability of operations and queries. Every operation and query has a deterministic, observable metric called a [RU / Request Unit](https://learn.microsoft.com/en-us/azure/cosmos-db/faq#how-does-azure-cosmos-db-offer-predictable-performance-). This (along with [guidance](https://learn.microsoft.com/en-us/azure/cosmos-db/index-overview#index-usage) on what determines RU charge) allows optimizing for performance and cost without requiring our engineers to become experts in MySQL performance tuning.

### SQL syntax, aggregation functions, and pagination

Cosmos NoSQL offers a familiar SQL syntax for queries. Of note for our scenarios is that it supports aggregate functions such as `SUM`/`AVG`/`MAX` and `GROUP BY` and `DISTINCT` clauses.

For most queries (excluding `GROUP BY`), Cosmos DB offers a robust continuation-token based [pagination](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/query/pagination) mechanism. RUs are not charged unless the additional data is actually retrieved (e.g. user goes to next page in table).

### Event Storage and Configurable Retention

As already noted, we likely want to not just store views intended for querying, but also duplicate the raw events from Hydro into Cosmos to retain (and be able to reprocess) them for a longer time.

Hydro's kafka retention is generally limited to a short period (e.g. 14 days) and importantly is not configurable at a customer level, as kafka isn't partitioned by customer.

Cosmos allows defining TTLs at multiple levels, allowing us to retain raw usage events as needed, and potentially differentiate based on customer, feature enablement status, etc.

### Materializing new views

Data modeling in Cosmos (and NoSQL in general) often requires denormalization/duplication of data to efficiently support desired queries. While this can be uncomfortable coming from a relational database background, in combination with easily measurable and predictable query performance, the above SQL aggregation functions, and the [change feed](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/change-feed-design-patterns), relying on denormalization can be useful to develop new efficient views of existing data.

Insights-dataplatform relied on daily jobs to merge/materialize new views from raw events, and thus the UX was often frustratingly days out of date. Instead, by processing raw events via the change feed (effectively treating it as an event queue), we can continuously materialize/merge views and compute aggregations such as usage minute and user counts.

Additionally, the change feed allows replaying items/events from the start of time or arbitrary time. All of this is quite similar to Hydro/Kafka (where the events are originally coming from!) but storing raw events would give us the flexibility to control the retention and partitioning of the events, and rebuild existing or new views as needed.

As an example of how we could use the change feed to materialize the existing `ActionsWorkflowUsage` view for efficient querying:
- The existing and initial experience we plan to deliver shows a table, with usage minutes and users summarized by the grouping `(Workflow, Repository, Runner Type)`, e.g. "Ubuntu-based jobs from the build.yaml workflow in FooRepo used 1000 minutes this month". 
- We receive compute usage Hydro events and persist them in Cosmos for long term retention
- We react to the new events via the change feed, and update a `(Workflow, Repository, Runner Type)` specific item to include updated usage minutes (and job id).

If we ever introduced a data inconsistency bug, it's trivial to rebuild a new version of the view by resetting the change feed back to the start and reprocessing the events.

Now, consider that we later want a `(Workflow, Repository, Runner Type, CheckSuiteResult)` view, and the existing view doesn't have the data or perhaps offer sufficient query performance. We can easily add a new change processor to produce the new data shape that supports our queries.

The change feed can be used as part of future features such as notifications (e.g. triggering when a particular usage goes over a value).

### Future advanced analytics 

While Cosmos regular transaction store should be sufficient for our planned use cases, we might imagine that in the future we want to do advanced anomaly detection, custom queries, or just have larger amounts of data and want to use an analytics engine. Cosmos integrates well with Azure's portfolio of Azure Synapse and other tools, so we could continue using Cosmos as the primary data store, running analysis jobs via e.g. Apache Spark, Cosmos Analytical store + SQL, Kusto, etc and persist the results back to Cosmos.

## Key Limitations / Challenges

While Cosmos will work well for our use cases, there are some challenges we expect compared to alternatives.

### Time-series data and Partitioning

Unlike Kusto, Cosmos is not primarily intended for time-series data. Cosmos requires careful partitioning both to stay under limits as well as for performance and COGS as provision throughput (RUs) are allocated equally across partitions.

In order to fit our largest customers, we likely need to partition not just by customer but by something like `(Customer+Month)`. This means that it's easy to run queries like `sum of usage for the first week of the month`, but a common query `sum of usage for the last 7 days (which happens to span two months)` would need to query 2 partitions and perform client-side summation.

As an alternative, we could consider using different partitioning schemes for different customer sizes (e.g. small customers have a single partition for all time).

As a reminder, this ADR does not intend to design the exact partitioning scheme / data model. But the complexity of designing and operating it is a consideration here, and Cosmos certainly adds complexity.

### Library support and limitations

The page https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/quickstart-go states:
> The Go SDK for Azure Cosmos DB is currently in beta. This beta is provided without a service-level agreement, and we don't recommend it for production workloads. Certain features might not be supported or might have constrained capabilities.

[According to the GitHub Data Patterns team](https://github.slack.com/archives/C0454035N9Z/p1693940467746109?thread_ts=1693937253.943449&cid=C0454035N9Z), even with the above it's still recommended to use Golang for development.

The Golang SDK also lacks some features that may be useful for us:
* Change feed processing: To use the change feed, we'll need a small C# app to do so. Thankfully, the C# app won't need to know anything about our data model, and since other teams at GitHub are doing the same thing eventually there may even be a shared library.
* Cross-partition queries: While they should generally be avoided, per the above sections we may end up wanting to query across 2 partitions if we need to partition by time (e.g. by customer+month). While other language SDKs have support for cross-partition queries and built in client-side aggregation operators, we would have to perform that result aggregation ourselves in Go (or switch to .NET). Our planned use cases are simple enough this isn't a big problem, but adds complexity.

### Potential future GHES support

Cosmos / NoSQL support is not yet available on GHES. This was a key reason why other analytics products at GitHub are using MySQL instead. However, we don't have an immediate need to be on GHES, and expect that a shim layer like https://github.com/github/project-chaos or similar will be available if we eventually do.

So this is both a positive and negative of Cosmos.

## Alternatives Considered

There are *many* possible alternatives. We evaluated a number of alternatives based on GitHub data service guidelines as well as [Azure's Analytical Data Store Recommendations](https://learn.microsoft.com/en-us/azure/architecture/data-guide/technology-choices/analytical-data-stores)

### 1a: MySQL

MySQL is the "default" option at GitHub. However, based on current event data in the Data Warehouse (see Data Size section above) and potential desire to store year(s) of workflow usage information, we would exceed 2T data size recommendations for MySQL within years especially storing raw events. We would likely need to greatly increase Hydro's kafka retention to not store raw events.

Further, our team does not have production experience with MySQL (we already have enough MSSQL on our plate) and at some point GitHub intends to make MySQL more self-service rather than centrally maintained, presumably requiring teams to have even more knowledge of MySQL administration.

### 1b: MySQL + Vitess

Vitess would solve the horizontal scaling problems of MySQL, but new uses are currently stopped / require Eng LT approval. Given our desire to stay on GitHub paved paths and other reasons against MySQL, this does not seem like an option worth fighting for.

### 2a: Azure Data Explorer / Kusto (new cluster)

Kusto is in many ways the ideal data store for our scenarios:
* Out of the alternatives, it's the only solution actually designed specifically for time series data
  * Greatly reduces implementation complexity as there's no need for careful partitioning/data modeling/etc as in Cosmos.
* It's designed for complex analytics, anomaly detection, etc, whereas Cosmos is very much not (but has basic aggregation functions)
* Our team already operates Kusto clusters and is highly experienced with Kusto
* It has documented patterns for supporting [multi-tenancy](https://learn.microsoft.com/en-us/azure/data-explorer/multi-tenant)

However, as well as Kusto matches our scenarios, it has some negative considerations:
* It isn't used for any other customer facing scenarios at GitHub
  * It isn't a GitHub data patterns paved path - we would be on our own and going against recommendations.
* Kusto has a 99.9% SLA, Cosmos has a 99.999% SLA. Even for a non-critical feature like Usage Metrics, taking a dependency on a three-nines service is arguably inappropriate and will receive pushback.
* Much of the logic would not be in code but would be state within the database/cluster, e.g. [update policies](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/updatepolicy) and [materialized views](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/materialized-views/materialized-view-overview). Would need to build up tooling and expertise managing those resources at scale.
* Supporting GHES would take significant effort to adapt/rewrite as we'd be responsible alone for doing so.
* The Golang library is in beta (like Cosmos)

### 2b: Azure Data Explorer / Kusto (Data Warehouse)

The Data Warehouse stores hydro events. Specifically, it stores 2 years worth of Actions `compute_usage` events.

However, it's not appropriate to use as a backing data store:
* It's [not to be used to power customer-facing insights features](https://github.com/github/engineering/discussions/3387)
* Since it only stores raw events, it would still require creating custom views (in kusto, or another data store) for efficient querying.

While it won't be used to directly power customer-facing services, we will make use of data in Data Warehouse for our own internal analysis to help us drive new Usage Metrics features. It's also possible that we could discuss using Data Warehouse for backfilling usage data prior to the existence of Usage Metrics, although we may (depending on product decisions) not need to do so or be able to use other sources anyways. 

### 3: Various Azure Synapse and Analytics Products

Azure has a wide portfolio of other data analytics products, including:
* Cosmos Analytical (column) store + SQL Serverless
* Apache Spark
* SQL Server w/ columnstore indexes (as used in insights-dataplatform)
* SQL Server Analysis Services (SSAS)
* Azure Data Factory / SSIS
* Azure Stream Analytics

While (like Kusto) some of these options may be appealing as they're specifically intended for data analysis, none are currently used at GitHub. Also, while our overall amount of data is large, individual customer data quantity is still small enough and desired queries are still constrained enough to use non-analytics focused databases.