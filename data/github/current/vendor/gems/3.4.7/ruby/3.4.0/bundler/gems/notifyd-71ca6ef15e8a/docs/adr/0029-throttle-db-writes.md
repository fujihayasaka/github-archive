# 29. Throttle writes to the database

Date: 2022-05-10

## Status

Accepted

## Context

We had a discussion on the [brief for database improvements][1] and [the following proposal on implementation][2] on how to throttle writes to the database.

## Decision

We implement a [freno](https://github.com/github/freno) client within notifyd but don't use throttling in the twirp API. Currently the only write path in workers is to track deliveries and we will only use throttling there after we have implemented more robust duplicate detection as outlined [in this brief](https://github.com/github/notifyd/blob/main/docs/briefs/duplicate-detection.md).

## Consequences

- there throttling capabilities ready to use
- they are currently not being used

[1]: https://github.com/github/notifyd/blob/main/docs/briefs/database-improvements.md
[2]: https://github.com/github/notifyd/blob/main/docs/proposals/database-improvements.md
