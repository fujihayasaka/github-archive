# 39. Apply Watching delivery settings for label subscriptions.

Date: 2023-03-23

## Status

Accepted

## Context

Label subscriptions only exist in notifyd and initially no global delivery setting was applied to them, as these were only available in Newsies.
Recently, these settings were migrated to notifyd and global settings were also applied to label subscriptions.
This was done in https://github.com/github/notifyd/issues/2314, and it was decided that _Participating_ settings should apply to label subscriptions.

[A recent discussion](https://github.com/github/notifyd/discussions/2676) gives some further context about this decision and how it's wrong, _Watching_ settings should apply to label subscriptions instead.

## Decision

Apply _Watching_ delivery settings for label subscriptions instead of _Participating_ delivery settings.

## Consequences

- `subscribed` reason should not be part of the _participants_ reason group in the notification event.
- `subscribed` reason should not be part of the _participant reasons_ in the web notification delivery job.
