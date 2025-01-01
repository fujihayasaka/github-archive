# Actions Usage Metrics Event Backfilling Design

> :warning: This has been [superseded](./0479-kusto-data-warehouse-followers.md) and is no longer relevant except for historical context.

## Status
Proposed - 2024-01-24  
[Superseded](./0479-kusto-data-warehouse-followers.md) - May 2024

## Context

This describes design and decisions around backfilling, which is any instance where we need to reprocess historical events in order to calculate new projections or recalculate old ones.

### Scenarios

1. We add a new projection, and need to bring it 'up to date'
2. Some kind of bug affects existing projections, and we need to recalculate it after the bug is fixed
3. We onboard a new org and want to backfill historical data

## Decisions

- For the source of historical data, we will use kafka first, and then if necessary use rawarchiver, which is an archive of all hydro events located in Azure blob.
- For the initial design, we will focus on scenario #1, backfilling a new projection using historical data, and try to implement #2 as well. #3 is low priority.
- We will design our backfilling API based on GitHub's transitions pattern [here](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions).

## Design

### Transitions API

Transitions are the established pattern for performing migrations at GitHub. This pattern mostly works for our case. The actual migrations are performed via chatops, of the form
```
.transitions run <pull-request-url> <environment> <arguments>
```
which for us might look something like
```
.transitions run <pull-request-url> <environment> backfill `
    -projection <projection : *> `
    -organization <organization : *> `
    -start-date <start-date> `
    -end-date <end-date : now> `
    -overwrite <overwrite : false>
```

The `-overwrite` flag indicates that we should ignore existing projections and overwrite them if they exist. Otherwise we will only process data that has not already been subsumed by the existing projections.

The `<pull-request-url>` is really meant for cases where the migration is linked to a particular code change. That is not generally going to be true for us, so we can use a static value. Some examples of transitions we might run:
```
.transitions run https://github.com/github/actions-usage-metrics/pull/1234 * backfill -projection NewProjection -organization * -start-date 2024-01-01 -end-date now

.transitions run https://github.com/github/actions-usage-metrics/pull/1234 production backfill -projection * -organization github -start-date 2024-01-01 -end-date 2024-01-02 -overwrite true
```

### Historical data sourcing

There are two potential sources of historical data
- The rawarchiver kafka event archive stored in Azure blob
- kafka

Both of these have limitations associated with them
- rawarchiver
   - All kafka events are stored in a single Azure blob container, which represents a security risk to access.
   - The data lags behind present by some indeterminate amount (but less than the kafka retention period).
- kafka
   - The retention of the kafka event log is less than we probably need (currently 14 days, but could potentially be increased to 30 or 60).
   - Each backfill requires a new consumer group, or a reset of an existing one. If it's simple to create a consumer group for each transition we can do so. Otherwise we can create a reusable one for backfill operations.

Both sources provide data in the form of kafka events identical to the ones the app is currently consuming. In general we can push these events through existing processing logic. In addition, we can transition seamlessly between these sources during a single backfill operation and the processing logic should be unaffected.

### Backfill processing

When we add a new projection, it will immediately begin to be filled in with new events. Kafka events are assigned ID's, which increase monotonically over time. To support backfilling, we will add to every projection the ID of the first and last events that have been processed.

There are two scenarios to consider
1. If `-overwrite` is true, our job is simple. We just process all data from the specified date range and write the computed projections to cosmos.
1. Otherwise we need to seamlessly merge with current event processing going on in the app.

Parallel projections can be seamlessly merged if their Kafka event spans are contiguous and don't overlap. This operation is mostly just a sum operation, with a few exceptions, like the hyperloglog merge. It is also identical to the batch processing we are planning to implement, so we should find a way to commonize this code.

Therefore, the backfill process is:
1. If `-overwrite` is not specified, get the current projection from cosmos.
   - If it doesn't exist, abort.
1. This projection contains a start ID. We only want to backfill events before this ID.
   - Since events should be received by the app in monotonically increasing order, we should be confident no event before this will be processed. However we may want to confirm this during the final merge.
   - If `-overwrite` is true, we can just backfill all events in the specified date range.
1. Fetch data from the historical data source, filtered to the specified date range and organization(s).
   - If there is data between the `end-date` and the start of the existing projection, this is a user error, but we might want to check for this.
1. Feed this data into the specified projection or projections.
1. This produces projections that should be contiguous with the existing projection but not overlapping.
1. Merge the backfill projection with the one in cosmos.
   - Just like normal event processing, this merge needs to be done atomically.
   - Or, in the case of `-overwrite`, replace it.

Notes:
- Since the backfill process doesn't require intermediate writes to cosmos during the operation, it's likely we can do it cheaply (at the cost of reading Azure blobs / kafka events). However in the case of running a backfill on all orgs and all projections, we do need to be careful of memory.
- With this design, backfill operations don't write to cosmos until they are complete, so they can be safely aborted. However any processing that has been done will be lost.