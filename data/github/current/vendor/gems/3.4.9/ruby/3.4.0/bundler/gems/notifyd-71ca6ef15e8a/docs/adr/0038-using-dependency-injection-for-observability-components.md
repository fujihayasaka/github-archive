# 38. Using depedency injection for observability components.

Date: 2022-12-03

## Status

Accepted

## Context

According to our [docs][docs] we use dependency injection,
but that has not always been the case for logging,
where a logger was created when a component needed to log.

A [refactor][refactor] of the logging system to use dependency injection
has raised the question again of whether to use dependency injection
for our observability components (not only logging) or treat them
differently as they are pervasive.

## Decision

We will use dependency injection also for logging as well
as the rest of the rest of the observability components.

## Consequences

As a consequence of this we will:
- Merge the refactor to the logging system.
- Use the same approach when we migrate to the new github telemetry system.

[docs]: ../how-do-we-write-code.md
[refactor]: https://github.com/github/notifyd/pull/2101
