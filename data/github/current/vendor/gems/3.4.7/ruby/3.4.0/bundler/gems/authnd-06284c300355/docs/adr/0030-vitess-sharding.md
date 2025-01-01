# 30. Vitess Sharding for Project Mint

Date: 2021-09-20

## Status

Accepted

Superceded by [31. Vitess Sharding for Project Mint Update](0031-vitess-sharding-pivot.md)

## Context

As part of Project Mint, we have introduced the new `ProgrammaticAccessToken` type in support of the PATv2 initiative being delivered by the Apps team.  Today, those tokens are stored in their own mysql table inside the same mysql clusters as the data replicated from `mysql1` via Maxwell.  As we look forward to the Staff Ship of PATv2, GH mobile 2FA, and other future initiatives, we need to codify the long-term home of data that is originated within `authnd`.

## Decision

We will store `ProgrammaticAccessToken` and other authnd _originated_ data within a sharded keyspace in a [Vitess](https://thehub.github.com/engineering/development-and-ops/mysql/vitess/) cluster.  Because of current [datacenter capacity constraints](https://github.com/github/database-infrastructure/issues/3749), we will retrofit the existing `authnd` Mysql clusters with the Vitess frontend.  For PrATs, the primary VIndex (i.e. shard key) will be `hashed_token`. The tables for data replicated from dotcom will be stored in a separate unsharded keyspace in the same Vitess cluster.

### Why are we sharding?

As `authnd` is the future home of authentication at GitHub, we want to plan our data storage strategy with an eye toward scalability.  Dotcom's availability and performance are heavily linked to the scale and performance of its core mysql clusters (e.g. `mysql1`). Over the years, different tables have been migrated out of `mysql1` to separate databases to resolve issues of scale, as part of the [data-partitioning initiative](https://github.com/github/data-partitioning). Fronting our mysql clusters with Vitess from the start allows us to distribute the data into multiple shards, the number and size of which can be scaled over time to accomodate additional load.  Most importantly, these adjustments can be done in a way that is completely opaque to `authnd` and its downstream services.

Importantly, Vitess has been [widely used](https://github.com/github/vitess#production) by a number of production services over the years at GitHub.  As a result, it is well understand both from an operation and application standpoint.

### Why shard by `hashed_token`?

The initial plan expressed in the Project Mint EDR was to use `actor_id` the primary VIndex (shard key) for PrATs (see [schema](https://github.com/github/authnd/blob/0e5eac9a9d47d7be800eedb8c4f01789bd83cad2/schemas/authnd/programmatic_access_tokens.sql)).  The primary advantage of using `actor_id` for sharding is that all credentials for a given user would be bound to one shard.  Therefore, `FindCredentials` requests by actor ID would never have to query multiple shards, thereby reducing overall system load and (potentially) latency.

However, we were [cautioned](https://github.com/github/authnd/issues/1017#issuecomment-905744303) against columns other than non-UUIDs for sharding as they lead to an uneven distributions of data, request throughput, and server load across shards, so called "hot shards".  By using a randomized key, like `hashed_token` or `token_suffix`, we ensure a more even distribution of data between shards regardless of underlying usage patterns by specific actors.

Data gathered from an [investigation](https://github.com/github/authnd/issues/1179) into performance of Vitess under these three potential shard keys further demonstrated the validity of that concern. Namely, even at relatively small scale and under controlled conditions, we still observed server-side usage patterns indicative of hot sharding. For example, we saw a difference of 2-3x total CPU usage and request volume between shards when sharding by `actor_id`. See the testing [methodology](https://github.com/github/authnd/issues/1179#issuecomment-921066907) and [results](https://github.com/github/authnd/issues/1179#issuecomment-922957897) for more details.

As a result, we've decided to use a random-value column as our shard key.  The choice between `hashed_token` or `token_suffix` is less important. The `hashed_token` column is slightly preferred because
1. It contains more bits of entropy, which is preferrable for the input to a hash, and
2. Our `Authenticate` requests already query mysql using the `hashed_token` value, so our existing queries would not need to be modified.

### What about other data?

Other present and future data which is originated within `authnd`, such as [GH Mobile 2FA](https://github.com/github/authentication/issues/611) tables, should be stored in these new Vitess clusters whenever possible.  Similar standards should be applied when choosing shard keys for those tables.

### Long term database infrastructure plans

As mentioned above, we're planning to retrofit our existing `authnd` Mysql clusters with Vitess while creating a _logical_ separation between authnd-originated and dotcom-replicated data by using separate keyspaces.  This decision is primarily due to the current shortage of capacity in the GitHub datacenters.  We desire to be good stewards of GitHub's physical resources and our data needs do not necessitate new clusters at this time.

Were that not the case, it would be much simpler to leave our existing Mysql untouched and provision new Vitess clusters for this new data.  Moreover, we believe that such a _physical_ separation of these two data types would help insulate `authnd` from failures induced by dotcom load.  We control neither the volume of the data owned by dotcom nor the rate of creation/modification/deletion of that data.  We have already seen instances where spikes in dotcom database writes have overwhelmed authnd's replication system in ways that negatively affected performance and availability; see one such example where [nightly `user_sessions` cleanup](https://github.com/github/authnd/issues/964) lead to large spikes in authnd request latency and intra-cluster replication lag.  Obviously, we can mitigate these kinds of issues as they arise, but its very difficult to preempt them in a way that avoids impact to our downstream services and users.

The primary goal of `authnd` is to enable services outside of dotcom to become independent of dotcom, wherever possible, with respect to authentication.  For that reason, we think physically partitioning these two sets of data is in the best interest of `authnd` in the long term.

## Consequences

In the long term, the decision to introduce sharding through Vitess now will mitigate a significant amount of future risk and development/operations work.  We strongly believe that partitioning of authnd-originated data and isolation from dotcom-replicated data will be necessary. Making those changes today, even in part, is preferrable to making them when `authnd` is serving more production traffic.  On the other hand, Vitess clusters do introduce extra operational, monitoring, and runtime overhead compared to traditional Mysql clusters.  In addition to the underlying Mysql machines, we would need to add monitoring and alerting for the Vitess infrastructure (e.g. `vtgate`, `vttablet`).  Moreover, Vitess introduces an additional network hop (`vtgate`) in the path to the database which will increase query latency.

In the short term, adding the additional set of Vitess clusters will make our connection handling, schema configuration, and CI scripts more complicated.  VSchema configuration changes for Vitess clusters are not handled by `skeema` and need to be applied manually.  Additionally, we'll need to run Vitess in local development/CI to ensure our code is properly integration tested; there is [precedent](https://github.com/github/authnd/issues/1017#issuecomment-905778200) for this in other services.

## Helpful links

- [MINT EDR](https://docs.google.com/document/d/1ymcNOfG2HuTPckRGDgzowXhbE8cCSOiKCwWdBYfEmuw/edit#heading=h.p7fafm28bw5)
- [Vitess Sharding Spike](https://github.com/github/authnd/issues/1179)
- [Staging Vitess development cluster](https://professorx.githubapp.com/mysql/cluster/authnd-mint-staging/vitess)
- [Capacity planning discussion for new cluster(s)](https://github.com/github/database-infrastructure/issues/3749)
- [Vitess docs on thehub](https://thehub.github.com/engineering/development-and-ops/mysql/vitess/)
- [Vitess docs on github](https://github.com/github/vitess#github-and-vitess)
