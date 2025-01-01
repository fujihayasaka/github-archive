> [!WARNING]
> The Maxwell replication pipeline has been decommissioned as of 8/20/2024 ([Initiative](https://github.com/github/authentication/issues/3710), [ADR](https://github.com/github/authentication/blob/4ccd48b5ec6b41a98ae222fd7e426d7df8d28d6f/docs/adr/0035-decomissioning-maxwell.md)). The valuable learnings in this doc are retained for future reference.

# Maxwell for data replication

This document serves as an overview of some of the considerations, challenges encountered, and lessons learned by the authentication team in our time running [Maxwell](https://maxwells-daemon.io/) in production.

### Context

Maxwell is a Change Data Capture (CDC) tool which we use to replicate, and slightly denormalized, data from `mysql1` into our own MySQL clusters.  At a high level, Maxwell connects to the binlog of the configured mysql cluster/server and produces a record for each observed INSERT/UPDATE/DELETE to a configured [producer](https://maxwells-daemon.io/producers/); in our case, messages are produced to Hydro/Kafka. The [`authnd-producer`](https://github.com/github/authnd-producer) repo contains the configuration for our deployment of Maxwell to Moda.

Each table which we replicate via Maxwell has a separate topic in Kafka and has a pool of bespoke consumers (e.g. [`oauth_accesses` consumer](https://github.com/github/authnd/blob/main/config/kubernetes/default/deployments/authnd-replicator-consumer-oauth-accesses.yaml)) which read data from the topic and persist it to our MySQL cluster(s).  Additionally, there is a dead letter consumer which consumes messages from a separate dead letter topic enqueued by normal consumers when they fail to process a record.

## Global resyncs are expensive and slow

In addition to the normal incremental change capture, Maxwell supports a "bootstrap" operation. When provided a list/range of rows in a configured table, Maxwell will produce the current contents of those rows one-at-a-time as UPSERTs.  This is ideal for backfilling data while setting up your replication flow, but is also sometimes necessary to repair individual records (i.e. dead lettering) or large chunks of records.  Doing a full re-bootstrap, what we call a "resync", of a table may be necessary as part of fixing bugs or disaster recovery.

However, this process is quite expensive and can take a long time for large tables.  Our last resync of the `oauth_accesses` table (169M rows) in production took around 10 hours. During that time end-to-end replication lag spiked varied between 2s and 8s.  There are several issues here:

1. During that resync, any new incremental changes will be subject to those replication lag increases.  This can lead to incorrect authentication results for recently changed credentials and performance degradation more broadly.

2. Replication lag isn't just isolated to the table you are resyncing.  The increased volume in Kafka traffic can have knock on effects on your other consumers and other unrelated topics in that Kafka cluster.  Thankfully, this effect hasn't been too severe in our experience.

We've discussed different ways to mitigate these effects (e.g. throttling writes with freno), but none of them are trivial.  Thankfully, full resyncs have been rare in our experience so far.  However, we'll likely need to implement changes to make resyncs smarter/more sensitive to avoid affecting normal production traffic in the future.

## Restarts are disruptive

In our experience, restarts to the Maxwell pod incur a roughly 10x replication lag spike over short period.  Our usual replication lag (from mysql1 commit to consumer read) is around 700ms but spikes to 8s on average for the 2-3 minutes after a Maxwell restart.

![Screen Shot 2022-02-23 at 9 13 17 AM](https://user-images.githubusercontent.com/7198966/155351405-4c8663a8-e5c6-43f5-aac5-8e1d8222ecf7.png)

## HA support shortcomings

As we mentioned above, restarts of a Maxwell singleton induce non-trivial replication lag spikes which we'd like to avoid. One way to avoid that is to have an already running, passive Maxwell ready to take over when the active Maxwell instance shuts down.

Maxwell docs mention support for an [HA mode](https://maxwells-daemon.io/high_availability) which is something we investigated during our [production readiness work](https://github.com/github/authnd/issues/990), but ultimately held off on.  There are a few high level considerations to using this though:

1. HA support is "experimental (alpha quality)".

2. This HA mode uses `jgroup-raft` for leader elections which only supports static group membership, i.e. the member names (pod names) need to be known at configuration time.  This likely forces you into using a [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#stable-network-id) for your a Kubernetes based deployment.

3. You can run into misordered transaction under network partitioning failures when the leader of a previous raft term continues to publish messages.  This can lead to incorrect data.  You could mitigate this by reducing the raft heartbeat interval/timeouts, but that incurs a performance cost and isn't foolproof.  Another proposal for dealing with this is to enrich the records produced by Maxwell to include the current raft term.  Then consumers can ignore messages for anything other than the current term.  This should work but requires some careful semantics on the consumer side to share/synchronize that state and a change to Maxwell upstream.

In the end, running Maxwell in an HA configuration is possible but should only be taken after careful consideration and testing.

## Other technical considerations

Maxwell is an [opensource project](https://github.com/zendesk/maxwell) written in Java.  Historically, GitHub hasn't had a lot of expertise or work happening in Java.  That means the barrier to contributing fixes/improvements is noticeably higher than other external tools which we use.

Maxwell restarts when it can't produce stats via the statsd plugin; ideally, Maxwell would attempt to re-establish this connection in the background or provide a configurable failure mode for this error. As we've already mentioned, restarts of Maxwell as expensive w.r.t end-to-end replication lag.  This is a solvable technical problem, but contributing a fix upstream isn't trivial for our team since we don't have Java expertise.  See [this tracking issue](https://github.com/github/authnd/issues/936).

## Reference links

[Development docs on Maxwell replication](https://github.com/github/authnd/blob/main/docs/authnd-development.md#replication-at-a-glance)

[Internal Maxwell Resync/Boostrapping docs](https://github.com/github/authnd/blob/main/docs/resync-bootstrap.md)

Relevant ADRs:

- <https://github.com/github/authnd/blob/main/docs/adr/0018-use-maxwell-to-replicate-data-to-authnd.md>
- <https://github.com/github/authnd/blob/main/docs/adr/0019-replication-bootstrapping.md>
- <https://github.com/github/authnd/blob/main/docs/adr/0020-replication-disaster-recovery.md>
