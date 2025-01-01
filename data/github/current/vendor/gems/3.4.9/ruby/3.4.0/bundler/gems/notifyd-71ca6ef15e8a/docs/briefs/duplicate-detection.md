# Brief: Duplicate notification management

## Problem Statement

Within the notifyd platform we need to be able to decide whether a
notification was already processed and can be skipped or if it needs
processing.

## Context

In notifyd within `mobile` we have a package
[`deliveries`](https://github.com/github/notifyd/tree/main/internal/mobile/deliveries)
which takes care of storing and retrieving information about deliveries we've
done. This is used by the `mobile` handler to decide whether a push
notification went out already or if it needs still be delivered. This is the same
logic that we already [use in Newsies](https://github.com/github/github/blob/master/lib/newsies/tracked_deliveries.rb). 

Of note here is that this duplicate detection isn't intended to protect
against duplicate processing of the same message. But rather it is intended to
guard against semantic duplicates e.g. when a user edits a comment where the
notification already went out and we don't want to send another one for the
edit. So duplicates are really defined by notification content and context
rather than on the message level. We are using the notification ID which
reuses the URI from dotcom for the most part looks something like this:

- `/github/notifyd/pull/123#pullrequestreview-456789`
- `/github/notifyd/issues/456`


So when we get a message to notify for a comment
`/github/notifyd/pull/123#pullrequestreview-456789` and the user edits that
comment, it generates a message with the same ID and thus will get ignored if
we have stored a delivery for this.

### Race conditions

Currently we have a race condition as we only really track these deliveries
[at the very end of the
handler](https://github.com/github/notifyd/blob/968c98816027e6e16cf74da44dc59516fb4ebded/internal/mobile/service.go#L167-L178).
This means if we get a duplicate message faster than the processing time of
the first one, we will send a duplicate.

Currently this isn't a problem as we don't generally see this race conditions
happening with the current timing of the system. However this problem is
exacerbated the longer the time is between starting to process
the message and storing it in the database. So the more we push things into
async processing or incur waiting times in processing from adding more stages
or something like throttling writes during times of high replication lag, the
more we increase the race condition window.
