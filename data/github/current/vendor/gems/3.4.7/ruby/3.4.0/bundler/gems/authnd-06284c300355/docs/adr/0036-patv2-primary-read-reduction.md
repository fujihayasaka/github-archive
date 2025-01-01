# 36. PATv2 Primary Read Reduction
Date: 2022-07-26

## Status
Accepted

## Context
When users create a PATv2, there is replication lag before it is available in the read replica database.  There needs to be a way for Authnd to determine where to fetch a token, in which it is known where that token currently exists.

## Decision
Solving the problem of reading a PATv2 from the read replica before replication has occurred should be addressed in two stages. The first stage is to modify the token format to include an `issued_at` timestamp at creation time.  The second stage is to set up caching within Authnd to further alleviate primary reads.

### Stage One - `issued_at`
This is a quick to implement solution which can be used to offer temporary relief.  The token format would need modifcation to include this timestamp, and this can be compared against an arbitrary number of seconds `n` to determine which database should be read from.
- If less than `n` seconds from `issued_at`
  - Check primary
- if greater than `n` seconds from `issued_at`
  - Check read replica

In this scenario, `n` seconds is a best guess on how long the application has to wait before assuming the record has been replicated.  If replication ever takes longer than this, a 404 will be returned as there is no way to guarantee the token requested is real.  If `n` is increased in size, primary reads also increase as the time required to wait between switching datasources expands.

### Stage Two - Caching
The next stage should be to add caching capabilities to Authnd. A cache in tandem with the `issued_at` timestamp will provide the most reduction in primary database reads. Mapping out all of the scenarios with a cache, five can be observed:

- Healthy cache
  -  `issued_at + cache_TTL > current_time`
  - Fetch from cache
- Healthy cache
  -  `issued_at + cache_TTL < current_time`
  - Fetch from read replica
- Healthy cache
  - `issued_at + cache_TTL < current_time`, but item is not in cache due to reasons such as: eviction policy, restart, etc
  - Fetch from primary
- Degraded/offline cache
  - `issued_at + cache_TTL > current_time`
  - Fetch from primary
- Degraded/offline cache
  - `issued_at + cache_TTL < current_time`
  - No-op, still fetching from read replica

As long as the cache is healthy, and hasnt experienced any data loss, the primary database will never need to be hit with a read operation.

Additionally, when token revocation occurs, the cache will need to be checked for the existence of the token and cleared if it exists.

## Alternatives Considered
Alternatives have been considered, however they do not offer the same level of primary read alleviation or robustness as the proposed solution.

### `issued_at` only
- In this scenario, `n` seconds is only a best guess on how long the application has to wait before assuming the record has been replicated.  If replication ever takes longer than this, a `404` will be returned as there is no way to guarantee the token requested is real.  As `n` increases in size, primary reads also increase as the time required to wait before switching datasources expands.

### Cache only
- Without `issued_at`, we have no way to guarantee it is known where the data is stored. For this reason, both the read replica and the primary would need to be checked if it is not found in the replica
- This also has the disadvantage of always hitting primary when a non-existing token is queried

### Always read from primary
- This is the problem being solved, and therefore is not a solution

### Always check read replica first, then fallback to primary
- Would result in lots of failed hits on the read replica before checking primary
- Non-existing tokens would always hit primary still

### `available_after`
- Non-standard pattern
- Bad user experience

### Max sequential Id check
In a [suggestion](https://github.com/github/authnd/pull/1589#discussion_r930431971) made, it was proposed to use the Id of the records, added to the token header instead of `issued_at`, to determine where to read from. It was decided not to go with this solution for a few reasons:
- Does not integrate with a cache solution nicely, which is the best long term solution
- Would result in 2 DB hits per request, either 2 read replica hits, or 1 read and 1 primary
- Still requires a primary hit in scenarios where tokens are used right after creation

## Consequences
- Adds a new attribute to the PATv2 token header 
- Not implementing caching from the start will result in a greater number of primary hits.
- `issued_at` is a quick fix to the underlying issue that can be implemented before GA, and is still useful to have with a caching implementation.
- Credentials will be stored in another datasource for the duration of the cache TTL
- Adding a cache is another potential point of failure
- Cache infrastructure will be available for later use on other features that need a caching solution

## Additional Notes
- [`issued_at` fits within point 2 of the original PATv2 structure ADR](https://github.com/github/authnd/blob/main/docs/adr/0028-pat-token-format.md#context)
- [The consequence of this ADR](https://github.com/github/authnd/blob/main/docs/adr/0032-pat-token-prefix-update.md#consequences) mentions increasing the PATv2 length from 85 to 93 characters, and that that we have notified people to support up to 255 [in this blog post](https://github.blog/changelog/2021-03-31-authentication-token-format-updates-are-generally-available/)
- [Conversation about redis in dotcom](https://github.slack.com/archives/C03EQQR0WKC/p1653059385300189)
- [Data-pipelines team redis provisioning notes](https://github.com/github/data-pipelines/blob/main/docs/redis/provision.md)
- [Redis clusters used at GH](https://professorx.githubapp.com/redis)
