# 31. Vitess Sharding for Project Mint Update

Date: 2021-09-30

## Status

Accepted

Supercedes [30. Vitess Sharding for Project Mint](0030-vitess-sharding.md)

## Context

As part of Project Mint, we have introduced the new `ProgrammaticAccessToken` (PrAT) type in support of the PATv2 initiative being delivered by the Apps team.  In the [30. Vitess Sharding for Project Mint](0030-vitess-sharding.md), we detailed the decision to store the PrAT table and other authnd-originated data in a new sharded keyspace in Vitess.  Further, we proposed to retrofit the existing `authnd` Mysql clusters with Vitess for this purpose.


## Decision

We will not be migrating the `authnd` Mysql clusters to Vitess clusters immediately. Instead, we will move the tables and PrATs and other authnd-originated data (e.g. GitHub Mobile 2FA) to a separate database within the existing clusters.  Finally, we will update our development and CI setups to run Vitess (using [minivt](https://github.com/github/minivt)) with sharding schemas for the appropriate tables.
Additionally, the earlier decision around the choice of shard key is still valid and not superceded by this ADR.

We still believe that database sharding may be in the best interest of `authnd` long term. However, our decision needs to consider some important pieces of context, namely:
1. The lack of need for sharding today. There current and project scale of usage and data for `authnd` can be easily supported by our existing Mysql clusters, as we've long acknowledged.
2.  The constraints on the database infrastructure team. As pointed in the preceding ADR, there is a known shortage in datacenter capacity; we endeavor to be good stewards of those limited resources. Additionally, the database infrastructure team is short on development time; we should take care in requesting work from them where it's not absolutely necessary.

The key factor in the decision to switch to Vitess immediately, as spelled out in the previous ADR, was our attempt to mitigate risk incurred from migrating our database later when we will be serving more "hot path" production traffic.  There are two specific kinds of risk we were concerned about with delaying the migration: availability risk and development risk.

In our continued discussions, the database infrastructure team has convinced us that the availability risk for Vitess migration is minimal.  It is a well understood process which has been executed many times at GitHub and, in general, is executed with no downtime.

Our larger concern was development risk.  Vitess is not a drop in replacement for Mysql in all cases; most notably, [not all Mysql queries are supported by Vitess](https://thehub.github.com/engineering/development-and-ops/mysql/vitess/vitess-for-application-developers/#some-queries-may-not-be-supported).  The primary concern is that, in the normal development of `authnd` over time, its Mysql usage could extend beyond what is supported by Vitess.  When it comes time to migrate to Vitess in the future, that would result in additional development time at a time when our service might be plagued with instability or performance issues.  However, by introducing Vitess in our normal development and CI process, we could guarantee that such a divergence from Vitess support would not happen. Moreover, we would already have all of the schema configuration necessary to switch from Mysql from Vitess immediately.

## Consequences

By using Vitess in local development and CI, our development/test and production environments' database configuration will be different. But since we have a stage and canary environment for `authnd`, the availability risk should be minimal.  However, it will make testing Mysql schema changes more difficult.  As a result, we may want to maintain a way to run _either_ Mysql or Vitess in local developement and CI, which defaults to Vitess.

Using a separate database for tables containing authnd-originated data will create a logical separation from dotcom-replicated data.  It will, however, require us to have separate DB configurations.  This makes our configuration logic slightly more complicated and error prone, albeit minimally so.

## Helpful links

- [MINT EDR](https://docs.google.com/document/d/1ymcNOfG2HuTPckRGDgzowXhbE8cCSOiKCwWdBYfEmuw/edit#heading=h.p7fafm28bw5)
- [Vitess Sharding Spike](https://github.com/github/authnd/issues/1179)
