# 25. Send notifications to subscribers using the email channel

Date: 2021-12-17

## Status

Accepted

## Context

While [shaping label subscriptions epic](https://github.com/github/planning-tracking/issues/633), we realized that we might want to filter deliveries by channel when sending notifications to subscribers.

Some of these architectural questions are related to when, where and how we are going to decide whether a recipient receives a notification by a specific channel:
- Should `notify-consumer` manage all the logic?
- How do integrators decide the delivery channel on the monolith?

## Decision

As we don't want to think about what's the proper architectural solution for this right now, we have decided:

- We won't add extra logic in `notify-consumer` to filter deliveries between channels for the moment.
- `NotifydAPIHandler` will be in charge of avoiding push notifications for `subscribed` reason [when checking the user settings in `check_deliver_mobile_push_policy` method](https://github.com/github/github/blob/5e80d174ec736f9cb75eeadf7ae7a2658ca19083/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L218-L227)

## Benefits

- It is not necessary to enlarge the scope of the label subscription epic
- We are not adding extra logic to filter by channel
- We are avoiding making architectural decisions prematurely

## Consequences

This is a temporary solution as we want to send subscription notifications to multiple channels.

- At some point we will want to decide where, when an how we are going to filter notifications by channel
- Notifyd service doesn't know about this decision, so there is a risk of sending push notifications to subscribers if we avoid the policy checks at some point
