# 12. Bulk syncing using cloned dotcom tables

Date: 2020-12-09

## Status

Superceded by [19. Replication Bootstrap](0019-replication-bootstrapping.md)

## Context

This ADR covers the process of bulk syncing data from dotcom into authnd.
There are three main scenarios in which this process is used:

1. During initial migration of data in to authnd
2. As an occasional replication/monitoring process
3. During Disaster Recovery (DR), when authnd has been offline for a prolonged period of time

For scenarios 1 and 3 (where we have a known gap of data to be recovered), we will run reconciliation **after** replication is restored and has been running for a period of time.

In [ADR #11](0011-consistency-guarantees-in-replication.md), a `version` column will be added to both dotcom and authnd's databases.
This column is sourced from the same data (incremented by dotcom each time the row is changed) and can be treated as a "consistent" version number for a row across both databases.

The bulk sync process needs to:

* Have minimal impact on running dotcom production services
* Provide us with a complete set of data from dotcom to use for replication
* Track appropriate metrics and diagnostics so we can identify reconciliation issues

Each row we are replicating from dotcom has an auto-increment integer primary key value `id`.
We use the ["consecutive" auto incrementing lock mode](https://dev.mysql.com/doc/refman/5.7/en/innodb-auto-increment-handling.html#innodb-auto-increment-lock-modes) in mysql1 which ensures that there are no gaps in IDs that might end up being reused later.
Once MySQL "allocates" a new ID by incrementing the internal storage for the counter, it will either be used on a row or **never used again**.
This was verified by running `SHOW VARIABLES LIKE 'innodb_autoinc_lock_mode';` in a DB console on `mysql1`.
As a result, when a row we previously saw during replication is no longer present in dotcom, we can be assured it was deleted and no further replication events can ever occur on the same ID.


## Decision

In order to have a minimal impact on production dotcom, we will sync from an "offline snapshot" of dotcom.
Prior to bulk syncing, we will make a clone of the dotcom table.
Currently, we know how to do that in a manual way (`.mysql clone [table-name]` chatop),
we may need to investigate how to do this in an automated way if we determine we need automated reconciliation.
We could also use live production credentials for occasional reconciliation if we use batching and ensure our queries have a low enough impact on dotcom.
This wouldn't be ideal for migration or recovery scenarios, but for occasional reconcilation it may be sufficient.

To conduct a bulk sync, the workflow will generally be as follows:

* Clone the dotcom table from production
* Run the "reconciler" tool (which may just be a different entry point in to the replicator), providing:
  * Credentials to the cloned table
  * Credentials to authnd's database

To help detect deletions, we will store a "highest seen ID" value in authnd for each table.
We will add a table named `table_stats` to authnd.
This table has three columns:

* `id` - An autoincrementing integer primary key (just out of prudence)
* `table_name` - A "string" (exact type is an implementation detail) representing the name of the table
* `highest_dotcom_id` - An `int` representing the highest ID value seen by the reconciler for the table identified in `table_name`.

Other columns could be added in the future as needed.

The `highest_dotcom_id` value will be updated during reconciliation using the following query:

```sql
UPDATE  table_stats
SET     highest_dotcom_id = :new_id
WHERE   table_name = :table_name
AND     highest_dotcom_id < :new_id
```

Where `:new_id` is the largest primary key ID value in the batch being reconciled, and `:table_name` is the name of the table.
This query will ensure that no matter the order that these queries are executed in, we will only ever increase this value.

The reconciliation will be idempotent, making it safe to run multiple times or retry in the event of failure.

The reconciler will use the algorithm below to generate "synthetic" replication events.
These synthetic events can be run through the replicator logic as though they were received from Hydro.
Synthetic events will have timestamps matching the `created_at` or `updated_at` value in the dotcom snapshot.

1. Fetch a batch of rows from dotcom in Primary Key order.
2. Attempt to fetch the same range from authnd.
3. Fetch the `highest_dotcom_id` and `highest_authnd_id` for this table from authnd's `table_stats` table.
4. Compare each row by the following algorithm:
   1. If the row is *present* in authnd and dotcom:
      1. If the row is marked as deleted in authnd: **Take no action**
         * (Could log if the timestamp of the row in dotcom is significantly higher than the deletion timestamp in authnd)
      2. If the Version in dotcom is higher than in authnd: **Generate an "update" replication event for the row**
      3. If the Version in dotcom is equal to authnd, and the row contents are different: **Log an error**
         * This indicates there was a conflict writing the version and we ended up with two different rows having the same version. This is a bad problem!
      4. If the Version in dotcom is lower than in authnd: **Take no action**
   2. If the row is *present* in dotcom and *not present* in authnd:
      2. If the row ID is lower than `highest_dotcom_id`: **Log an error**
         * The fact that the row is below `highest_dotcom_id` means it was previously present in authnd
         * The missing deletion record means the row was hard-deleted inappropriately
      3. Otherwise (not known to be deleted): **Generate a "create" replication event for the row**
   3. If the row is *not present* in dotcom and *present* in authnd:
      1. If the row is marked as deleted in authnd: **Take no action**
      2. If the row ID is lower than `highest_dotcom_id`: **Generate a "delete" replication event for the row**
         * The fact that the row is below `highest_dotcom_id` means it was created in authnd *before* this reconciliation
         * The fact that it is now deleted in dotcom means we missed a delete event
      3. Otherwise: **Take no action**
         * The row hasn't been reconciled before and isn't known to be deleted
         * So the fact that it's present in authnd likely means it was created after the snapshot was taken
         * We could check the timestamp of the create against the timestamp at which the snapshot was taken to double-check
5. Update `highest_dotcom_id` to the `MAX(id)` in the batch from dotcom
6. Hard-delete any rows in authnd with `id < highest_dotcom_id AND is_deleted` - We don't need them
   * Should probably metric the number of remaining "soft-deleted" rows
7. Repeat from 1 until all rows from dotcom are checked

When a synthetic event is processed, we may determine (just as we would in the replication process) that the event has been superceded and should be ignored.
Any synthetic event that causes an update means one of the following scenarios occurred:

* The row was modified right before the snapshot was made, and due to replication lag, we end up processing it in the bulk sync before the normal replication process. This is benign, and we can detect it by looking at the timestamps. Given how long the snapshot process takes (at least several minutes even for small tables) it seems **very unlikely** that this would happen.
* The row was **not** properly replicated. This can be detected if the timestamp of the change is outside of our reasonable SLO for expecting changes to be applied to authnd. In this case, we should update metrics tracking the number of rows for which we discover replication is failing.

The main gap in this pattern is that we don't have a clear way to identify "trailing" deletes.
A "trailing" delete is any scenario where in authnd we have a row with ID `X`
but there is no row in dotcom with ID `X` **and** there are no existing rows in dotcom with an ID larger than `X`.
Essentially, because there are no rows higher than `X`, we don't know if the row was actually deleted.
It may have been created *after* the snapshot was created (since these tables can have quite high traffic).

There's a lot of logic here, but in general, we expect inconsistencies between dotcom and authnd to be quite *rare*.
We also have time to evaluate these processes "in production" as we dial up the science experiments we will create.

## Consequences

This pattern, along with [ADR #11](0011-consistency-guarantees-in-replication.md), allows us to treat reconciliation as just another process that generates replication events.
Given that [ADR #11](0011-consistency-guarantees-in-replication.md) provides guarantees about the idempotency of replication events,
we can have an idempotent reconciliation process that can work on offline snapshots of dotcom data.
It also provides a means to identify replication failures using purely *offline* resources (i.e. using database clusters not required for servicing production requests).

The primary risk here is that if the snapshotting process is heavy or complicated, we may not be able to run the reconciliation sufficiently frequently.
For example, a brief search of Slack history shows that cloning `oauth_accesses` can take several hours, or even a day.
If the reconciliation is running too slowly, it will take a long time to detect failed replication states, since the reconciler is the primary way to detect most failed replications.
We previously implemented a "fallback" model in authnd where queries will go to dotcom if the row doesn't exist in authnd,
but this can only catch cases where a **create** event is lost.
Only a full comparison of the rows between dotcom and authnd can identify **all** failed replication cases (with the exception of "trailing deletes" as noted above, where there exist no non-deleted rows with IDs higher than the deleted row).

The currently-existing "clone" operation is a chatop, which may be difficult to automate.
However, it calls some API somewhere so we might be able to work with the DB team to find a strategy for automating this.
Also, the cloned table ends up in the `mysql4` cluster, which may not always have sufficient space for the table.
