# 27. Use aqueduct to handle retries

Date: 2022-04-25

## Status

Accepted

## Context

On [`#10`][1] we decided to use hydro consumers to process notifications in `notifyd`.

One of the consequences of that decision is that notifyd doesn't have an effective way to handle retries for messages that have failed.

## Decision

We will use aqueduct jobs to process retries. Alternatives, architecture and other considerations can be explored in the [proposal][2]

## Consequences

- There, apparently, a 10k jobs/second limit for the whole GitHub on the amount of messages aqueduct can handle. Retries is expected to be a low traffic queue, however we might want to make sure we know how to throttle it in case this limit is reached somehow.
- We have had to introduce a new technology to our architecture stack, which increases our operational cost.
- This has spawned some conversation about whether [`#10`][1] is still valid and should be reevaluated in order to move towards an aqueduct only system instead.

[1]: https://github.com/github/notifyd/blob/main/docs/adr/0010-use-hydro-consumers-not-aqueduct-jobs-for-notification-delivery-inter-process-messaging.md
[2]: https://github.com/github/notifyd/blob/main/docs/proposals/retries.md
