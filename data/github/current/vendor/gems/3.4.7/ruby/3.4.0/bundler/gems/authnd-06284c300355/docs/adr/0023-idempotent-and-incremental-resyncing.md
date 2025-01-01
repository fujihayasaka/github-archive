# 23. Idempotent and incremental resyncing

Date: 2021-02-02

## Status

Accepted

Supercedes [19. Replication Bootstrapping](0019-replication-bootstrapping.md)

## Context

The bootstrapping process described in [19. Replication Bootstrapping](https://github.com/github/authnd/blob/main/docs/adr/0019-replication-bootstrapping.md) involves bootstrapping in to a new table and then swapping the new table in.
This is done primarily because we expect the old table (if any) to be corrupt and in need of repair.
Using a new table ensure that "deletes" are handled, since the new table starts empty and only receives new rows based on the bootstrapping.
However it also adds significant complexity.
We have to shut down replication to the old table, or at least double-write replication to the new table.
Also, multiple deployments are needed to "coordinate" this process and ensure the integrity of the bootstrapping.

As a result, bootstrapping can be a complicated and heavy-weight process.
Because of the high complexity and duration, it is only intended for "rebuilding" a table.

As a reminder, because of how auto incrementing primary keys work in our system, once a row has been deleted, it's ID will **never** be re-used.
Thus, once a row is removed from the source database in `mysql1`, **and** the `DELETE` has been either processed by our consumer, **or** we have moved past it in the binlog, it is safe to delete it from our database at any time.

## Decision

Instead of replicating to a new table, we build the "bootstrapping" process as a "resynchronization" process that can be safely run at any time, on any range of rows, with only positive impact on the target database.

We can resync any range from `start` (inclusive) to `end` (inclusive), and it will repair those rows and resume replication.
We do this by starting a Maxwell bootstrap with a where clause (`WHERE id >= start AND id <= end`), and in the consumer, process `bootstrap-insert` events mostly the same.
The consumer will, however, "mark" any rows processed by a `bootstrap-insert` event, so we know the row existed in the source data set.
When resyncing is completed, any unmarked row within the range `id >= start AND id <= end` can be safely deleted.

The resyncing for that range is now complete and the rows in that range are corrected.
New events for that table will continue to come in and the data will continue to stay up-to-date and correct.

### Resyncing

We will introduce the following new column to all tables being replicated:

* `sync_state int(11) DEFAULT(0) NOT NULL` - An enumerated column tracking the "state" of a row, as relates to resyncing

This column can have the following values:

* `0` - `ACTIVE` - The row is active and not currently being resynced.
* `1` - `RESYNCING` - The row is currently being resynced.
* `2` - `SWEPT` - The row has been "swept" (soft-deleted) because it wasn't present in the range brought back from the source database.

All our queries to retrieve credentials will be augmented with an additional `WHERE sync_state != 2` check, to ensure `SWEPT` rows are not returned.
Only the `SWEPT` state affects retrieval, rows in any other state are considered visible during an authentication request.

A resync is started by a chatop: `.authnd resync source_table --destination target_table --from start --to end --batch_size batch_size --batch_timeout timeout_in_seconds`.
The options/args to that command mean:

* `source_table` - The source table to resync from
* `--destination target_table` - **OPTIONAL**. The name of the target table in authnd's database to update. Defaults to the same name as `source_table`.
* `--from start` - **OPTIONAL**. The starting ID of the resync range. Defaults to `1`.
* `--to end` - **OPTIONAL**. The ending ID of the resync range. Defaults to `MAX(id)` (the last ID in the table).
* `--batch_size batch_size` - **OPTIONAL**. The size of the resync batches to run. Has a defined default value.
* `--batch_timeout batch_timeout` - **OPTIONAL**. The max amount of time the resync process will wait while polling for a bootstrap batch to finish. Has a defined default value.

On recieving a chatop request, the handler will:

1. Set `range_start = start` and `range_end = range_start + batch_size`
2. While `range_start < end`:
    1. Increment a metric of active resync processes.
    2. Set all the rows to be resynced to the `RESYNCING` state, by running the following query on `authnd`: 
        * `UPDATE target_table SET sync_state = 1 WHERE id >= start AND id <= end AND sync_state != 2`
    3. Start a Maxwell bootstrap of the range by inserting into `maxwell.bootstrap`:
        * `INSERT INTO maxwell.bootstrap(database_name, table_name, where_clause) VALUES('github_production', 'source_table', 'id >= :range_start AND id <= :range_end')`
    4. Poll `maxwell.bootstrap` for that bootstrap to complete
    5. If a timeout (`timeout_in_seconds`) elapses waiting for the bootstrap to complete, emit an error to Slack and halt the process.
        * In theory, we can *continue* to bootstrap other ranges, as long as we track the ranges that failed and emit the error.
        * This is an enhancement we can add as we decide we need it.
    6. When it finishes, mark any rows that are still marked `RESYNCING` as `SWEPT`:
        * `UPDATE target_table SET sync_state 2 WHERE id >= start AND id <= end AND sync_state = 1`
    7. Set `range_start = end + 1` and `range_end = range_start + batch_size - 1`
    8. Decrement the metric of active resync processes.
    9. Emit a metric for the duration of the batch process
3. Post status back to Slack ("Resync completed" or "Resync failed at batch [range_start]...[range_end]", etc.)
4. Emit a metric for the duration of the entire resync operation

Example Output (Success):

```
> Resync of public_keys from ID 1000 to 2000 has started.
... some time passes ...
> Resync of public_keys from ID 1000 to 2000 has finished!
```

Example Output (Failure):

```
> Resync of public_keys from ID 1000 to 2000 has started.
... some time passes ...
> Timed out waiting for resync of public_keys from ID 1000 to 2000 to complete!
```

The insert into the `maxwell.bootstrap` table (Step 2.2 in the Resyncing section above) will trigger Maxwell to begin emitting `bootstrap-start`, `bootstrap-insert` and `bootstrap-complete` events.
The consumer will process these events in the following ways:

* On a `bootstrap-start` or `bootstrap-complete` event, metrics are updated (i.e. count of messages processed by type) but no additional action is taken.
* On a `bootstrap-insert` event for a given row, the following actions are taken in a single DB transaction (likely just a single SQL statement):
  * The row is updated/inserted with the appropriate values
  * The state of the row is set to `0` (`ACTIVE`)

### Garbage Collection

With some rows being marked `SWEPT`, we need a process to clean them out of the database to avoid garbage piling up.
We will add a chatop: `.authnd gc table_name`.
This chatop handles "garbage collection" of `SWEPT` rows.
It is executed manually by an operator, to give us a safety mechanism to ensure the mark/sweep pattern is working.

On receiving this chatop request, the handler will:

1. Execute the following SQL to delete `SWEPT` rows: `DELETE FROM table_name WHERE sync_state = 2`
2. Report the number of deleted rows to Slack, and any errors.

Example Output:

```
Cleaned public_keys table.
453 SWEPT rows deleted.
```

### Stats Reporting

In order to monitor resynchronization and check if garbage collection is needed, an operator may need to get status on the "state" of rows in a table.
To do this, we'll add a third chatop: `.authnd stats table_name`.
This chatop will fetch stats about the state of rows in the provided table.

On receiving this chatop request, the handler will:

1. Execute the following SQL to compute counts-by-state: `SELECT sync_state, COUNT(id) FROM table_name GROUP BY sync_state`
2. Report the results to Slack (converting state numbers to symbolic names), and any errors.

Example Output:

```
Stats for public_keys:
* ACTIVE rows: 5603
* RESYNCING rows: 948
* SWEPT rows: 2043
```

## Consequences

Resynchronization is a safe idempotent operation that can be executed at any time.
If the existing data is corrupt, there's no need to create a new table just to repair it, we can repair it in batches in-place.
Whole-table bootstrapping can be done in batches of any size and at any pace, while continuing to replicate "new" changes in between bootstrap segments.
We gain the ability to pause bootstrapping if we are causing too much load on the source cluster, and resume later and at a different batch size if necessary.
Partial-table repair operations are possible (though the utility of that may be pretty limited).
Bootstrapping **can** still be done into a separate table, but isn't necessary for the integrity of the process.
Large bootstrapping operations can be split into smaller batches that can be safely retried without restarting the entire process.
