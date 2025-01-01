# 30. Postponing database sharding

Date: 2022-05-10

## Status

Accepted

## Context

We had a discussion on the [brief for database improvements][1] and [the following proposal on implementation][2] on how to shard databases.

## Decision

We will not enable sharding right now. Our dataset is too small to justify the expense of additional hardware to support sharding. This will be revisited as we approach 1TB of storage size for a table within the `notifyd` cluster.

## Consequences

- sharding keys are already present in schemas and are ok to add
- we don't actively shard right now

[1]: https://github.com/github/notifyd/blob/main/docs/briefs/database-improvements.md
[2]: https://github.com/github/notifyd/blob/main/docs/proposals/database-improvements.md
