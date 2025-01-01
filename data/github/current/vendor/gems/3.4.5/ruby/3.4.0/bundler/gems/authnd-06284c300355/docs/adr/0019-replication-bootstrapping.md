# 19. Replication Bootstrapping

Date: 2021-01-07

## Status

Superceded by [23. Idempotent and incremental reconiliation](0023-idempotent-and-incremental-reconciliation.md)

Supercedes:

- [11. Replication and reconciliation strategies](0011-consistency-guarantees-in-replication.md)
- [12. Bulk syncing using cloned dotcom tables](0012-bulk-syncing-using-cloned-dotcom-tables.md)

## Context

In order to replicate a table for authnd, the first step is building a fresh "copy" of the table. This is referred to as "bootstrapping" by Maxwell, and that's the term we will use. Another that may be used is "snapshot".

There are two scenarios where bootstrapping is necessary:

**Scenario 1.** Building a new table we wish to replicate with all data backfilled

**Scenario 2.** A disaster scenario where we exceeded our retention period(s) or where we are unsure if we can rewind/replay from a log position (see the [Replication Disaster Recovery ADR](./0020-replication-disaster-recovery.md) for more information on disaster scenarios)

This ADR walks through solutions and decisions made to solve bootstrapping for the scenarios above.

## Decision

We will leverage Maxwell's built in "bootstrap" process. Maxwell pauses it's binlog reading / event producing until it's finished bootstrapping and then it picks back up at the location in the binlog before the bootstrapping started. Maxwell bootstraps are triggered by writing to a Maxwell table or using the `maxwell-bootstrap` utility script. Exactly how we trigger a Maxwell bootstrap is an implementation detail. A reasonable option could be to implement a chatops command.

We will use Maxwell's `async` bootstrap mode. This means that during a bootstrap for a table, it will behave as described above. But unlike `sync` mode, when events are read from the binlog regarding other tables during a bootstrap, they will continue to be processed and events will be produced. Only the binlog events belonging to the table that is being bootstrapped will be queued until after the bootstrap is over.

For both scenarios requiring a bootstrap described above, we've decided to implement an approach that utilizes a temporary table that will be swapped out with the active table once the temporary table is bootstrapped and reconciled with the table we are replicating or repairing (similar to the `gh-ost` migration approach). These temporary tables will live in the authnd cluster.

To ensure we are SELECT-ing batches, we will leverage Maxwell's `where_clause` option and `is_complete` column for bootstrapping. An example query for triggering a bootstrap for a table looks like:

```sql
insert into maxwell.bootstrap (database_name, table_name, where_clause) values ('github_development', 'public_keys', 'id > 1000 AND id <= 2000');
```

An outline of the solution follows:

1. Stop the replicator consumers (if we define deployments of consumers on a per-table and per-topic basis, we only need to stop the consumers for the table we are bootstrapping/repairing)
2. Start a single consumer (using the same consumer group ID) that is configured to write to a temporary table
3. Trigger a Maxwell bootstrap via chatops for a particular table (e.g. `.authnd bootstrap public_keys`)
4. The chatops process will receive the request and handle it like so:
   1. Receives request for bootstrap of table `x`
   2. Queries table `x` to get the size using `MAX(id)` (for this example, pretend it's 2,500)
   3. Writes to `maxwell.bootstrap` table with `WHERE` clause `id <= 1000`
   4. This bootstrap will trigger a `bootstrap-start` event where the temporary table will be created in the consumer
   5. Polls `maxwell.bootstrap` table until the bootstrap row that was just written is marked as `is_complete`
   6. Writes to `maxwell.bootstrap` table with `WHERE` clause `id > 1000 AND id <= 2000`
   7. This bootstrap will trigger another `bootstrap-start` event that will be ignored since the table already exists and we are already mid-bootstrap
   8. Polls the `maxwell.bootstrap` table until the bootstrap row that was just written is marked as `is_complete`
   9. Writes to the `maxwell.bootstrap` table with `WHERE` clause `id > 2000`
   10. This bootstrap will trigger another `bootstrap-start` event that will be ignored since the table already exists and we are already mid-bootstrap
   11. Polls the `maxwell.bootstrap` table until the bootstrap row that was just written is marked as `is_complete`
   12. Send back to Slack that the bootstrap for the entire table is complete
5. When the consumer receives a `bootstrap-start` event, it creates a new temporary table based on the table it's reconciling (e.g. `CREATE TABLE _public_keys_bootstrap_123 LIKE public_keys`) _if_ it doesn't already exist 
6. The consumer will begin processing all of the INSERTs that are received from the `bootstrap-insert` events
7. When we are confident the bootstrap is finished, stop the new consumer(s) (remember when these are stopped, the consumer group holds the state of where to pick back up)
8. At this point, we have no consumers running, but we have a temporary table that is reconciled and a consumer group ready to pick back up where it needs to based on the temporary tables replicated state. And this whole time we are still serving authnd requests which are being served by the original table
9. Swap the tables (this could also be implemented via a chatops command if we think it's worth it -- otherwise, it could be done via a manual database query)
10. Start the original consumers so they pick back up where the "temp consumers" left off but now we are writing to the original table name again and the consumers will catch back up with "live" replication events
11. Manually remove the temporary table that was created

## Consequences

- By choosing to use Maxwell's built in bootstrap process, we lose flexibility and insight into what exactly the code is doing when speaking to the tables we are replicating. Since Maxwell will be hooked up to a replica, it is less of a concern, but we may want to do some testing to ensure there isn't significant locking or negative impacts on the replica while a bootstrap is occurring.
- The options above do not provide a "bootstrapping" solution where we can bootstrap while continuing to process replication data for that table. A solution like this is possible, but since one of the scenarios is applicable to "development" of a new replicated table and the other scenario is a last-resort disaster case scenario, we have opted to keep the bootstrapping solutions as simple as possible while we learn more.
- Using Maxwell's `async` mode allows consumers to continue receiving and processing change events for existing tables (excluding the table that is being bootstrapped) while a new table is being initialized or repaired.
- All and all these decisions don't require much code, and the concepts can be built upon in the future if need-be.
- There are some different approaches that could be applied in an "initial bootstrap" scenario, but for the sake of simplicity and applying the same code path/processes to both scenarios, we've decided to narrow the focus of decisions made in this ADR down to one bootstrapping solution.
- This solution leaves the tables as-is so they can continue to serve traffic while a repaired/reconciled table is constructed. This will keep our service mostly available while the bootstrap process is running.
- Compared to other solutions considered, this solution does not require any dropping or truncating of tables. When the bootstrap process is finished, a manual cleanup of the temporary table can be executed.
