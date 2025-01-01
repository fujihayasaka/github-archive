# 18. Use Maxwell to replicate data to authnd

Date: 2021-01-07

## Status

Accepted

Supercedes:
* [6. Replicating credential data](0006-replicating-credential-data.md)
* [8. Credential Replication Security](0008-credential-replication-security.md)
* [11. Replication and reconciliation strategies](0011-consistency-guarantees-in-replication.md)
* [13. Processing replication events](0013-processing-replication-events.md)

## Context

In working on [ADR 13 (Processing replication events)](0013-processing-replication-events.md) we identified some complex replication issues and discussed solutions.
Most of these complexities arose from the fact that replication was occurring **separate** from the write to the primary data store (dotcom's databases, `mysql1`, `collab`, etc.).
This creates a risk of inconsistent ordering that is "by design".
If two changes to a row occur "simultaneously" and our hooks in dotcom publish messages to Hydro describing the changes, we cannot guarantee that the order Hydro receives them matches the order in which they were applied in MySQL.

After further investigations, and after researching tools found in the ecosystem, we identified that [Change Data Capture (CDC)](https://en.wikipedia.org/wiki/Change_data_capture) tools may provide a viable and more reliable alternative.
These tools connect directly to the source database and replicate data reliably from that database to other systems.
Because they use transactional features of the source database, they provide a consistent ordering of change events and allow us to reduce the amount of code we have to write ourselves.
CDC tools also give us the ability to replay missed messages to recover from disasters.

Since a CDC tool hooks *directly* in to MySQL, and we know that Hydro keeps messages ordered, we **do** know that the order of events received through Hydro *directly* matches the order in which they were applied in MySQL.

### Background on Maxwell and MySQL binary logging

As part of it's replication system, MySQL maintains a binary log on every server and replica.
The log contains the changes made by every transaction that has been committed to the database.
This log is guaranteed to be in the order that transactions were committed and represent the full set of changes (inserts, updates and deletes, as well as schema changes) made to the database after each transaction.
Only changes from transactions that have been committed appear in the log.
Individual rows changed in a transaction **do** appear as separate events, but we are guaranteed that transactions are never interleaved in the log.

Each change in the log is uniquely identified by "binlog coordinates" (a combination of the binary log file name and the byte offset within the file).
Binlog coordinates are unique and can be compared to each other to determine the order of a particular change.
However, binlog coordinates are **not** random-access, as the records in the log have variable length.
Given a set of coordinates, it is not possible to find the exact coordinates of the preceeding or following event in the log without seeking through the binlog from the start.

[Maxwell's Dameon](https://maxwells-daemon.io) is an open-source CDC tool maintained by Zendesk.
It connects to a MySQL database and establishes itself as a replica.
It streams events from the binary log and emits equivalent JSON payloads to Hydro.
For each insert, update or delete in the log, the JSON payload contains the old row content (if applicable) the new row content (if applicable) and the type of change.
Maxwell has built-in support for encrypting the payload before publishing to Hydro.
The binlog coordinates associated with the change can also be included in the JSON payload.

## Decision

* We will change our replication process to use Maxwell's Daemon.
* We will run Maxwell within our Moda application, and use it to replicate changes to relevant tables in dotcom's databases to Hydro.
  * NOTE: On GHES we should be able to publish to the `kafka-lite` instance, though we may not have the same guarantees of ordering there and should use some caution.
  * This ADR does not cover GHES support, we'll need to do separate work on that.
* We will configure Maxwell to encrypt data before publishing it to Hydro, achieving our confidentiality and security goals.
  * We'll use a shared key in our vault, as we currently do.
* We will change our replication consumer (authnd-replicator) to decrypt and consume the JSON format published by Maxwell.

NOTE: Further ADRs will cover changes to the initial bootstrapping process and disaster recovery as part of this change.

### Consumer changes

Our replication consumer will continue to operate in much the same way it does now.
It will still connect to Hydro, as we do currently, but Maxwell's messages are formatted in JSON instead of protobuf and don't have the Hydro "envelope" format.
The Hydro client libraries can still be used, since they don't enforce the format of messages.
If we need direct control over consumer offsets for DR scenarios, we may need to use a Kafka library for that purpose.

Currently, we track two columns (`sync_timestamp` and `sync_version`) in each row of authnd's database as "metadata" to help with ensuring idempotency.
Moving forward, we will track three columns:

* `sync_timestamp` (already present) - The UTC timestamp at which the sync occurred. This will come from the Maxwell JSON payload.
* `sync_binlog_position` (new column) - The binlog position (in the form `filename:offset`) of the last event that modified this row. This comes from the Maxwell JSON payload.
* `sync_gtid_position` (new column) - The GTID (MySQL Global Transaction ID) of the last event that modified this row. This comes from the Maxwell JSON payload.
* `sync_kafka_offset` (formerly `sync_version`, renamed for clarity) - The offset of the message in Hydro that last modified this row. This comes from the Hydro client.

The `sync_binlog_position` and `sync_kafka_offset` values should always increase, except in the event of an intentional rewind as part of disaster recovery or when switching replicas.
The `sync_gtid_position` provides a unique identifier for the transaction that produced the last change to this row.
A GTID is a two-part identifier: `server_uuid:transaction_id`.
The `server_uuid` is a unique identifier for the server that received the original update (in our case, this is always the `master` server in `mysql1`).
The `transaction_id` is a sequential identifier representing the transaction ID on that server that triggered the event.
The Hydro offset provides an order local to the row.
Messages for the same table and primary key value will have strictly increasing (but **not necessarily consecutive**) `sync_kafka_offset` values.

When a message is received by our consumer, it will:

1. Check the existing values (if any) of the `sync_gtid_position` and `sync_kafka_offset` against the versions in the incoming message
   * If the existing `sync_kafka_offset` is not **less than** the values in the message, one of the following scenarios would be true:
     * We are replaying events from Kafka due to disaster recovery
     * Messages became unexpectedly reordered
   * If the first part of the `sync_gtid_position` (the `server_uuid`) values are not equal, the master database failed over in between updates.
   * If the first parts are the same, but second part of the `sync_gtid_position` in the event is **less than** the one in the row, one of the following is true:
     * We are replaying events from the binlog due to disaster recovery
     * Messages became unexpectedly reordered.
   * We should log and metric in these cases so that if we **are** in DR, we can treat it as expected, but if we **are not** in DR, the on-call operator can investigate.
2. If the message is a delete, remove the row. There is no need for soft-delete, since we know that the events we are receiving are strictly ordered.
3. If the message is an insert/update, perform an "upsert" (insert a new row, or replace the row data if there is already a row with the same primary key) to ensure the row has the values specified in the JSON payload.
4. Log the binlog position and kafka offset of the change to our normal diagnostic logs (to assist in diagnosing issues or picking a place to rewind)
   * If this becomes too noisy, we could log it occasionally, or on startup.
   * Having known binlog positions helps us provide "markers" to rewind to. For example, if we know a bad deploy caused problems, we'd want to rewind to a binlog position **before** that deploy started processing messages.

NOTE: Another ADR will cover rewinding and disaster recovery.

## Consequences

Since we are no longer hooking dotcom to publish changes, we get a few benefits from a code-organization and security point of view:

* All changes are covered, we don't need to worry about if the code that makes a change is properly instrumented with the right hooks
* Encryption keys remain entirely within our control, they're not in memory in dotcom, nor do we have to navigate deployment trains

Since the binlog gives us assurance that we will see **all** changes applied to a table in the proper order, we don't need to soft-delete rows anymore.
If we receive an insert/update event for a row that was previously deleted, we would "recreate" the row.
However, there are only a few situations in which this could occur:

1. We are rewinding the log and replaying it.
   * It makes sense to restore the row in that case.
   * If the row was "properly" deleted, then the delete event is ahead of us in the stream and we will process it later
2. Events got out of sequence (either in the binlog or in Hydro)
   * This would mean a pretty serious bug in either MySQL or Hydro
3. A coding error on our part

We could continue to soft-delete rows, but if we *do* soft-delete rows, we still need some process to come along later and clean up soft-deleted rows.
The cost and complexity of maintaining a "garbage collector" that safely cleans up soft-deleted rows, seems to far outweigh the risks introduced in the above three situations.

We have limited control over what is published to Hydro, since we are using Maxwell to publish.
Unless we make code changes (it *is* open-source), we can only use configuration to modify the payload of the events.
Fortunately, we believe Maxwell is configurable enough to achieve our goals.
We also have some fallback options: Forking or contributing to Maxwell, or having Maxwell publish to some "local" data store and having a separate daemon process the events there and put them in Hydro.
Both options come with risks though, so ideally we will keep to using what Maxwell provides.

GTIDs provide some degree of "global" ordering for us as well.
In the context of the same `server_uuid`, the `transaction_id` provides an "order" for transactions.
However, we cannot determine the order of two GTIDs with different `server_uuid`s, since they mean the two transaction were issued to different servers.
The `server_uuid` for any transaction we care about is the ID of the master that recieved the change.
It should only change if the master fails over, which should be a scenario we are aware of (or can confirm as part of on-call investigation when the UUID changes).
We'll have to do some shipping-to-learn here to identify how useful the GTID is for our replication process.

Maxwell is a third-party component that will be processing our data.
There could be security concerns with that, and we should ensure we understand what Maxwell is doing with the data.
We should strongly consider using a source distribution (cloning specific commits and building it ourselves) so we can inspect the code and have confidence it is not storing or sending data anywhere we don't expect.
We could consider Kubernetes [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) to ensure that Maxwell can only talk to the services we expect it too.
However, given that it is produced by Zendesk, we can have reasonable confidence it is doing what it says it is.

Using a CDC tool to replicate does disconnect us from the user actions that cause changes to be made.
Our previous system of publishing messages from dotcom, when credentials are modified, gave us a clearer connection back to the original event that triggered the change.
Eventually, as authnd takes over managing credentials, we will need to track down those places in dotcom that modify credentials and change them to use authnd.
Using Maxwell (or any CDC) doesn't help us do that, whereas manual hooks did give us some insight into the places modifying credentials.
However, the benefits of a CDC tool far outweigh those costs.
With a stable replication system, based on a reliable CDC tool, we will have a solid foundation to start with when we start trying to track down and replace all the code that modifies credentials.
