# 16. Use an explicit field with the actor for a notification

Date: 2021-05-18

## Status

Accepted

## Context

While building the functionality to [filter out notifications for a user's own activity](https://github.com/github/notifyd/issues/115) we realized that we needed a way to know who's the `Actor` initiating a notification in order to make sure that `Actor != Recipient`. Or a different system in order to decide whether to discard users self mentions.

We considered 3 different options:

1. Keep the same approach we had on the prototype where we added an entry to `explicit_recipients` with `author` as the `reason`. In this case we used this when calculating the [user's delivery channels](https://github.com/github/notifications_platform/blob/98f8903d72e5814c902c0baa0e851f0ba3e3af30/lib/notifications_platform/models/channel_setting.rb#L26-L59) to ignore the notification and would give the user the possibility to change the behavior.
2. Perform a simple check as newsies does today in the form of `actor_id != recipient_id`
    1. Hooking into the `authzd` part of the notify message to pass the `actor_id`
    2. Explicitly adding a new `Actor` field to the message

## Decision

We decided we wanted to use `2.2.` in order to favor explicitness and simplicity over deduplication and also in order to avoid premature abstractions.

## Consequences

### Benefits

 - The API is more explicit and simple.
 - The approach is simple enough for now and avoids abstracting prematurely.

### Drawbacks

 - The cost of the change is bigger since we now have to add a new field and we'll probably have to change it again in the future. However we agree that this cost is negligible vs the benefits.
 - The solution is not Open/Closed and we know we might want to be in the future.
