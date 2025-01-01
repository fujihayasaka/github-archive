# 6. Provide rendered notification content in hydro events at triggering time, not delivery time

Date: 2021-03-26

## Status

Accepted

## Context

A consequence of [0003-minimise-requests-from-the-notifications-service-back-to-the-monolith](./0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md) is that when rendering a notification we will be unable to make a request back to the monolith to load the content that we would like to put into the notification.

## Decision

When publishing the [hydro event](./0005-use-hydro-events-for-triggering-notification-delivery) that triggers notification delivery, all the content required for rendering the notification will need to be included in the event payload.

## Consequences

### Benefits

- Keeping requests back to the monolith out of the delivery pipeline, will keep notification delivery fast, and resilient to outages/code changes/etc in the monolith.
- By requiring teams to provide content up-front when triggering notifications should also reduce the amount of code that needs to be written to start delivering a new notification.

### Drawbacks

- This design will make it hard to customize content per-recipient, this may require us to make trade-offs in the types of notification rendering we can do, or to decide to violate this guideline in certain situations.
