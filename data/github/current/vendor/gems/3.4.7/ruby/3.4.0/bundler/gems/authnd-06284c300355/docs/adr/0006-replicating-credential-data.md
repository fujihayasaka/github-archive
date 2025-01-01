# 6. Replicating credential data

Date: 2020-09-29

## Status

Superceded by [18. Use Maxwell to replicate data to authnd](0018-use-maxwell-to-replicate-data-to-authnd.md)

## Context

*For simplicity, we will refer to "dotcom's databases" as a shorthand for all the databases
used within github/github, including but not limited to `mysql1`, `collab`, etc.*

Currently, we access the dotcom databases directly, but this is not sustainable. Authentication
queries make up about 50% of existing read load on mysql1. Also, the database infrastructure
team wants to reduce touch-points in to dotcom's databases.

Directly accessing dotcom database also does not achieve one of our main goals of decoupling
authentication from dotcom reliability.

During our experiments (see [ADR #7](0007-science-experiments.md)) we will be running both the
existing code, and the new authnd code. If authnd is reading from dotcom's databases, then we
end up **doubling** the already high read load.

## Decision

We want authnd to take control of the data it uses to validate credentials.

We will augment the dotcom codebase to publish events to [Hydro](https://hydro.githubapp.com) when
the relevant data is changed.

We will consume the Hydro events from a *separate* service in authnd which will update a new database,
specific to authnd, with the replicated data.

We will update authnd to read data from the new authnd-specific replica.

## Consequences

Replicating data from dotcom is a necessary step towards gaining data independence from dotcom. It does
not complete the process, since we are still treating dotcom as the authoritative source for data, but
it provides incremental benefit.

By replicating only the data we need, we relieve pressure on dotcom databases by reducing the read traffic
on it's databases and relocating that traffic to the new authnd database. We already discovered during the
experiment that scaling authnd usage up while it still uses dotcom's databases could cause a significant
increase in traffic on those databases and put dotcom at **increased** operation risk.

Replicating data also allows us to operate even when dotcom is down, since we are not directly dependent
upon dotcom's data. This allows authnd (and thus services that depend on authnd) to remain available even
when dotcom is down.

Replication is not simple and it has risks. The data can get out of date, and we must ensure the replication
is prompt in order to quickly revoke credentials when the user requests that we do so. Missed replication events
may cause data to be lost unless we monitor the process closely and have recovery options.
