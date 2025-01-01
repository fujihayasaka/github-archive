# 20. Replication Disaster Recovery

Date: 2021-01-07

## Status

Accepted

Supercedes:

- [11. Replication and reconciliation strategies](0011-consistency-guarantees-in-replication.md)

## Context

There are a handful of Disaster Recovery (DR) scenarios we need to be prepared for in our replication:

**Scenario 1.** Consumer (authnd replicator) downtime

**Scenario 2.** Authnd DB downtime or unavailability

**Scenario 3.** Producer (Maxwell) downtime

**Scenario 4.** Code defect/bug

**Scenario 5.** Migration issue

**Scenario 6.** Unknown disaster

In all cases, our approach for reconciling the authnd DB differs based on the amount of time it takes for the issue to be fixed (e.g. bug fixed and deployed, service restarted, DB becoming available, etc.). This means that in general, there will be a few approaches for reconciliation based on whether we fixed the issue within the applicable retention periods. To jump to the solutions, see [Reconciliation Solutions](#reconciliation-solutions) below.

There are 2 different retention periods we are concerned about:

1. Kafka Topic Retention (**1 hour** for the [replication topic](https://github.com/github/hydro-schemas/blob/596ab26805e0f4dc9cbcaa302883af31fd1e97f4/topic-configuration/production/potomac/kafka-topics.yaml#L6496))
2. Binlog Retention (**2 days** on a mysql1 read replica - it might differ on a primary)

The [Decision](#decision) in this ADR walks through the different scenarios and explains which solution is required for reconciliation based on time to recovery. Keep the retention periods in mind when reading through the scenarios, and also keep in mind that the topic retention can be easily increased via configuration (to match binlog retention, or exceed it).

## Decision

[ADR 18 (Use Maxwell to replicate data to authnd)](0018-use-maxwell-to-replicate-data-to-authnd.md) walks through decisions made to use Maxwell for our CDC tool and how we will track binlog and kafka commit log positions. We can assume there is an easy way for individuals to find/retrieve applicable log positions for the solutions below.

### 1. Consumer (Authnd Replicator) Downtime

In this scenario, we are laying out a plan for if/when the replication consumer (authnd replicator) has downtime.

#### In-Time Recovery (before topic retention)

If we know we (re)started authnd replicator within the retention period of the kafka topic(s), the consumer will pickup where it left off on the commit log and no replication data is missed. There are no disaster recovery steps in this scenario - it's not much different than rolling out a change to the replicator.

#### Late Recovery (after topic retention)

If the consumer has **not** been restarted within the topics retention period, but it **is** within the binlog retention period, we need to [replay the producer](#replay-producer-maxwell) from a position in the binlog that was written before the downtime.

#### Later Recovery (after binlog retention)

If the consumer hasn't been restarted within the topic retention period **and after** the binlogs retention period, we need to [re-bootstrap](#re-bootstrap).

### 2. Authnd DB Downtime

In this scenario, if there was a DB outage or unavailability that caused database write failures from the authnd replicator (that hard-failed even after local retries), we know that we missed replication event(s) even though the producers and consumers were alive and running.

#### Early Recovery (before topic retention)

If the DB downtime is short, and we are still within the topic retention, we need to change the offset on our consumer group so that we replay the data that we know was missed. In this case, we need to [rewind the consumer](#rewind-consumer-authnd-replicator-consumer-group).

#### Late Recovery (after topic retention)

If the DB was down for longer than the topic retention or there was a short DB outage and our team hasn't been notified (or isn't available) until **after** the topic retention from the outage but it **is** within the binlog retention period, we need to [replay the producer](#replay-producer-maxwell).

#### Later Recovery (after binlog retention)

If the DB was down for longer than the topic retention or there was a short DB outage and our team hasn't been notified (or isn't available) until **after** the topic retention **and after** the binlog retention period, we need to [re-bootstrap](#re-bootstrap).

### 3. Producer (Maxwell) Downtime

In this scenario, topic retention does **not** matter because when the producer is down, the data isn't making it to a topic 🙂

#### In-Time (before binlog retention)

If the Maxwell producer goes down and it is restarted **before** the binlog retention, the producer will pickup where it left off on the binlog and no replication data is missed.

#### Late Recovery (after binlog retention)

If the Maxwell producer goes down and has **not** been started within the binlog retention, we need to [re-bootstrap](#re-bootstrap).

### 4. Code Defect/Bug

In this scenario, we have detected a code defect that caused a bug and found the PR or code that needs to be reverted as a fix. Similar to the scenarios above, depending on when we find the issue and are able to deploy a fix, there are different ways we can handle reconciling our table(s) based on timing.

#### Early Recovery (before topic retention)

If we are able to resolve the code defect quickly, and we are still within the topic retention, we need to reset the offset on our consumer group so that we replay the data that might have had issues from a bug. In this case, we need to [rewind the consumer](#rewind-consumer-authnd-replicator-consumer-group).

#### Late Recovery (after topic retention)

If it took longer for us to discover or fix the bug and it was longer than the topic retention but it **is** within the binlog retention period, we need to [replay the producer](#replay-producer-maxwell).

#### Later Recovery (after binlog retention)

If it took longer for us to discover or fix the bug and it was longer than the topic retention **and after** the binlog retention period, we need to [re-bootstrap](#re-bootstrap).

### 5. Migration Issue

In this scenario, there was an issue with a table migration that we were not aware of or didn't expect. Once the issue is fixed (if it requires a code change on the authnd replicator consumer), there are similar solutions to the DB outage scenario described above based on timing.

#### Early Recovery (before topic retention)

In this case, we need to [rewind the consumer](#rewind-consumer-authnd-replicator-consumer-group).

#### Late Recovery (after topic retention)

We need to [replay the producer](#replay-producer-maxwell).

#### Later Recovery (after binlog retention)

We need to [re-bootstrap](#re-bootstrap).

### 6. Unknown Disaster

In this scenario, we are aware that our DB is out of sync but do not know the reasoning and are unable to trace back when or how it happened. This could be due to a bug that was released in production for an extended period of time, a disaster migration scenario, lack of metrics or logs, etc. Since we don't know when we missed or mishandled replication events, the best solution in this situation is to [re-bootstrap](#re-bootstrap).

## Reconciliation Solutions

### Rewind Consumer (authnd replicator consumer group)

In this solution, the goal is to "rewind" our consumer group to start at a defined position in the Kafka commit log. Since we currently perform "upserts" on INSERT or UPDATE events, replaying events won't cause issues and will result in a reconciled table. During this time, there may be slight inconsistencies in the tables data as we replay through the events. Note that depending on how we implement our DELETE handling, events may raise errors or emit metrics for a missing record if we are replaying a DELETE event that has already been successfully processed - this is something we should expect when executing this solution.

We have two options to rewind the authnd replication consumer group:

1. Work with `#data-pipelines` to gain access to Kafka hosts (managed via entitlements) so that we can use the `kafka-consumer-groups.sh` tool to set the consumer group offset to a certain position (we can even supply a datetime to the tool and it will give us the most recent offset from that datetime - see [Managing Consumer Groups](https://kafka.apache.org/documentation/#basic_ops_consumer_group) documentation). This requires the pods for the group to be stopped, the command to be run, and then the pods for the consumer group can be started again.
2. Write a Golang utility script to change the offset for us. This could be in the form of a chatops command, but can be considered as an implementation detail. This approach would simplify permissions and hoops/risk we'd go through to access the Kafka host machines. It also _might_ not require us to stop the consumer group. [Here](https://gist.github.com/BenEddy/70b9ba2eb239ebf8ca4f05fe1372dedc) is a quick Gist of a Ruby script for changing offsets.

### Replay Producer (Maxwell)

In this solution, since we have exceeded the retention on the commit log, but we still have the events available on the binlog, the goal is to "replay" events from the producer so that they are reprocessed by the authnd replicator consumers. This behaves similar to the solution above (by "replaying" replication events that we have already seen in the consumer and potentially already processed), but there are a couple of things to watch out for before starting back up the producer.

If the consumer is still processing events on the topic, we need to make sure that it is "caught up" before starting back up the producer. Remember, in this case the producer is not running, and also hasn't been running for a while so it's unlikely the consumers would still have work to do. There are two options if we ever end up in this situation:

1. Wait for the consumers to work through the leftover commit log
2. Restart the consumers with a configuration to tell it to use the "latest" offset. This will basically fast-forward/skip through the logs that are left.

Once we are confident the producer is not running and the consumer group is sitting at the latest offset (and has no work to do), we are ready to start Maxwell back up with configuration to tell it to start producing from a defined location in the binlog. This can be done using the `--init_position` flag that Maxwell supports. It accepts values like `mysql-bin.000023:6579505` where the left half of the colon is the binlog file, and the right half is the position. This will start Maxwell at the binlog position specified, "replay" the events we wanted to see again, then continue to process future events. No further action is required.  

### Re-Bootstrap

This process for bootstrapping is defined in the [ADR 19 (Replication Bootstrapping)](0019-replication-bootstrapping.md#2-disaster-scenario).

## Consequences

- The solutions defined in this ADR leverage the commit log and binlog positioning in a way that "replay" events to fix missed/mishandled events.
- In the most likely scenarios (where time to recovery is short / reasonable), reconciling our DB requires 0 or minimal additional downtime, minimal code, and only a short (depending on how far back in the log we need to go) period of time where our data is a bit inconsistent while we replay the events.
- We should consider upping our replication topic retention period. It's currently 1 hour, but since the data is encrypted there shouldn't be a reason why we can't increase it. If we were to match the binlog retention (2 days), it would decrease the applicable scenarios where we need to "Replay the Producer" which is a tad more complicated that "Rewinding the Consumer".
- As mentioned in the [Replication Bootstrapping](0019-replication-bootstrapping.md) ADR, in the case where we exceed our maximum retention limit (currently 2 days defined by the binlog retention), we do have the option to begin building up a reconciled table while our current/out-of-sync table is still handling request.
- As mentioned in the [Replication Bootstrapping](0019-replication-bootstrapping.md#consequences) ADR consequences section, the re-bootstrapping option does not provide a solution where we can re-bootstrap/repair a table while continuing to process replication data for that table. A solution like this is possible but since this is _hopefully_ an unlikely disaster case scenario (since it means we were down/unavailable/unaware for >2 days), we have opted to keep the re-bootstrapping solution as simple as possible while we learn more.
