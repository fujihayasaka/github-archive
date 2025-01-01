# 11. Replication and reconciliation strategies

Date: 2020-12-04

## Status

Superceded by [18. Use Maxwell to replicate data to authnd](0018-use-maxwell-to-replicate-data-to-authnd.md), [19. Replication Bootstrap](0019-replication-bootstrapping.md) and [20. Replication Disaster Recovery](0020-replication-disaster-recovery.md)

## Context

Authnd is serving authentication requests by using a replica of the dotcom "source of truth" (mysql1 and friends).
In order to ensure we are achieving our goals, we need to establish a clear policy on consistency guarantees for that replication.
In addition, we need to establish how we will ensure that the replicated authnd data is *reconciled* with dotcom.
In the event that they drift apart (due to an outage, a bug, etc.), we need a way to asychronously reconcile the data by comparing authnd to dotcom and applying any changes.

We also need to consider **all** the possible events and how we detect them.
In almost all cases, we will be reconciling data using an "offline" version of the source data (from dotcom).
Details will come in a future ADR, but in general we must assume we are reconciling authnd against a snapshot of dotcom data which may no longer be up-to-date.
In some cases, authnd may be *more* up-to-date than the snapshot we are comparing with.

Consider these scenarios:

* A row was created in a dotcom but not replicated:
  * This will appear as a missing row in authnd, when the row exists in dotcom.
* A row was updated in dotcom but not replicated:
  * This is *hard* to detect at the moment.
  * The two rows will have different data but we don't know which is more up-to-date!
  * What if authnd was updated via replication *after* we started comparing with dotcom?
* A row was deleted in dotcom but not replicated:
  * This will appear as a missing row in dotcom, when the row exists in authnd.

Consider the following sequence of events.
They are listed in "true order" (the order the user actually applied them),
but take note of the timestamps and the order that they actually arrive on Hydro.

1. On web server `A`: A user creates a PAT with no scopes.
   * The time on the server is `01:00:00UTC`, which is recorded as the `created_at`
   * This message makes it on to Hydro at offset `1`
2. On web server `B`: The user adds the `repo` scope to that PAT (an update).
   * The time on the server is `01:00:10UTC`, which is recorded as the `updated_at`
   * Due to delays in processing on that server, this message makes it on to Hydro at offset `3`
3. On web server `A`: The user removes the `repo` scope from the PAT (an update).
   * The time on the server is `01:00:20UTC`, which is recorded as the `updated_at`
   * Due to the above delays on server `B`, this message makes it on to Hydro at offset `2`

Now, despite the "true" ordering, we have the following order of events in Hydro:

1. Create PAT
2. Update PAT to **not** have the `repo` scope
3. Update PAT to **add** the `repo` scope

The net result would be that the PAT *still has the `repo` scope* despite the user's intent from these actions.

We need to consider what attribute we use to represent the most accurate ordering of events in order to resolve this.
We also need to ensure that as much as possible, authnd is consistent with dotcom's data store.

We need to answer the following questions:
* What attribute do we use to establish the "order" of operations?
* Under what circumstances can that attribute become inconsistent with the user's perception?
   * Clock drift (for timestamps)
   * Data races (currently updates to dotcom aren't transactional)
* How likely are those circumstances and can we live with them?

Once we establish a means of ordering events in dotcom, we can ensure that authnd replication honors that order by:

* Tracking the same order values in it's own database.
* Disregarding replication events with an **earlier** ordering than the current state of the row.
* When reconciling data from a bulk sync from dotcom, ignore rows which were modified **earlier** than the one in authnd  

## Decision

We will introduce a version number to the relevant tables in dotcom.
On each modification of the relevant models, we will increment the "version" column (to the best of our ability).
That version number will allow reconciliation processes like bulk syncing to work smoothly.
The replication event, and authnd's database will all include the version number of any replicated rows.

We will use the existing timestamp columns (`created_at` and `updated_at`, both of which are replicated to authnd) as a secondary check on consistency.
If we discard a change because the version column indicates it is "older" but the timestamp columns indicate it is "newer", then we will log/metric that scenario so that we can follow up.

When replicating data we will capture metrics indicating when edits/changes are discarded.

We will implement the "incrementing version" column via Rails callbacks (`before_update`).
We will evaluate the accuracy of the replication and identify issues of replication drift while experimenting.

Any time we are considering an update to authnd (either via a replication event or a bulk sync),
we will compare the versions of the incoming row to the current row and only apply a change if the incoming row is newer.

Further ADRs will cover the specifics of reconciliation and bulk syncing.

We will start this process with the `public_keys` table, which we own.

## Consequences

In general, when updating credentials in dotcom, the read and update are **not** contained within a single transaction.
This means it is feasible that two writes that occur simultaneously could attempt to write the same version number.

As the experiment progresses, we can determine if more strict mechanisms are needed.

In the future, we may change our replication strategy from an asynchronous one based on Hydro to a synchronous one.
This version number pattern will allow us to continue reconciling the two databases regardless of the means of replication.

Adding a new column will require a database migration in dotcom and a data transition to set the initial version (we may be able to leverage MySQL default values here).
We must complete that work before we start reconciling.

## Alternatives Considered

Below are the alternatives considered (including the chosen option). The above decision reflects choosing Option 2.

### Option 1: Timestamp-based ordering

Every row we are replicating comes with two timestamps: `created_at` and `updated_at`.
These are timestamps at the *second* granularity and are generated on the web server on which the modification occurs.

The proposal here is to use those timestamp to serve as the intended order.
When processing replication messages from Hydro, this means:

* A `create` event would not be accepted if the row already exists in authnd (this is actually true in all cases :)).
* An `update` event will only be accepted if the `updated_at` in the new row is **later** than the current `updated_at` in authnd
* A `create`/`updated` event would not be accepted if the row had previously been deleted

In order to achieve the third objective, we will likely need to store some form of "tombstone" record indicating that a row was deleted.
That way we can check the tombstone list when a create/update comes in to determine if the event should be discarded.

We also need to consider how to ensure these tombstones do not grow indefinitely.
Since any gap in IDs would represent deletions, we may be able to do this by only tracking the "highest" ID seen.
When we see an ID lower than this "highest" ID and find it is not in the actual authnd database, we know it was previously deleted.

The main advantage to this is that it requires no additional changes to dotcom.
It also takes advantage of data that already exists in the dotcom database (the source of truth).
However, it is still possible for us to drift out of sync with dotcom in the event that two events are written to mysql in a different order than the timestamps indicate.

This is certainly the simplest option, if we are willing to tolerate the risk that the timestamps may not actually reflect the true ordering of events.
It requires no new columns on dotcom and only a small amount of change to authnd.

## Option 2: Row "Version" in dotcom

We can add an additional `row_version` column to the relevant tables in dotcom.
This is a monotonically incrementing value that begins at `1` and is incremented whenever the row is saved back to the database.

To concretely describe this, consider the modification we would make to the `PublicKey` model:

```ruby
class PublicKey
    before_save :update_version
    def update_version
        version += 1
    end
end
```

This would increment the version number in the database any time `.save` is called.
It would not be a perfect transaction, since two simulatneous edits of the same `PublicKey` on different servers could both try to increment the version.
There may be ways to achieve something more atomic in ActiveRecord, but my initial investigation indicates that would be a fairly large change and would require more complicated transactions.
It's notable that there can **already** be races like this in the data that is written to the database.
If a user has two different browser tabs adds two different scopes to the same PAT (one scope in each tab) and clicks save on each "simultaneously", it is undefined which will win.
The main difference here is that the source-of-truth (the database) ends up being consistent.
If we can try to generate replication events off of the true state of the database, then we end up no worse.

This would also mean that we would need to change how we trigger the replication event to EITHER:

1. Perform a `.reload` before sending the message so that the replication event is based on the real DB row, OR
2. The replication event would only indicate *that* the row changed (and include the primary key), and not how, and it would be up to a different process (either the replicator in authnd or a background job in dotcom) to actually fetch the latest row.

This affects replication in much the same way as option 1, just using this row version instead of a timestamp.
We track the row version in authnd as well, and we use "tombstone" entries to track deleted IDs.

This is probably our most reliable and reasonable option.
It does require some changes to the source data in dotcom, which adds risk and complexity, but they are fairly minimal and safe to apply.
It also requires changes to authnd, but no more than Option 1 would require.

## Option 3: Database-level replication

Another way to achieve our goals is to switch to using database-level replication.
MySQL has a rich system in place for replicating data between servers, based on strong consistency and a binary log of transactions.
In effect this means authnd continues to "talk to dotcom" (as we have always been using a replica) but might allow us to take load off of mysql1.

However, this makes it tricky to start adding "write" capabilities to authnd.
If dotcom (or other clients) start calling APIs to save credentials to authnd, where do we store those?
We can't write to the replica table, but we could have our own separate table and do two queries.

This allows us to leave the database to do the replication, which is convenient and likely quite stable.
However, it adds significant challenge to our future implementation and doesn't actually get us the full independence from dotcom that we seek.

## Option 4: Fast-forward to tomorrow - Synchronous API calls

The main reason we need to worry about replication consistency is that it occurs asynchronously.
An error in replication doesn't cause the original write to dotcom to fail, and thus the two databases can easily get out of sync in an outage.
If we think about the long-term plans for authnd though, that provides us with another option.
In that scenario, when a credential is modified, dotcom will be expected to call an API in authnd to do that update.
We could start building that now and use it for replication by having any dotcom modification flow do the following:

1. Write the change to authnd
1. If the above fails (times out, errors, etc.) - Either:
   1. Return a 500 to the user (this is more consistent, but means authnd is in the critical path right away and we can cause outages)
   2. Log the failure somewhere where we can see and fix it (this requires manual replication repair of some kind)
1. Once authnd has the change, write it to mysql1

We can still end up in an inconsitent situation here though, if the write to authnd succeeds but the write to mysql1 fails.
We could reduce this risk using a database transaction that isn't committed unless the write to authnd succeeds (by default all callbacks like `before_update`, etc. run in a database transaction along with the actual update).
However, we could still run in to a problem if the write to authnd succeeds but then the final commit to mysql1 fails.
We could likely log and track this problem, but we don't avoid the reconciliation problem, just reduce it's likelihood.

This option gives us higher confidence in the replication but doesn't actually solve the reconciliation issue.
We can still end up with inconsistent data, the difference here is that we will *know about it more quickly*.
It also allows us to fail user actions when the data would become inconsistent, ensuring the user knows about the error.
However, until authnd takes over all aspects of the data ownership, we still have the risk of reconciliation issues. 
