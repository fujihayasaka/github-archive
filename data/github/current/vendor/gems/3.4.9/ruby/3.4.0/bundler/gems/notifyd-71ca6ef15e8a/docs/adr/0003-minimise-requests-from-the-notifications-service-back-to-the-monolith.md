# 3. Minimise requests from the notifications service back to the monolith

Date: 2021-03-26

## Status

Accepted

Amended by [15. Make requests to the monolith for mobile push checks during the migration to notifyd](0015-make-requests-to-the-monolith-for-mobile-push-checks-during-the-migration-to-notifyd.md)

Amended by [18. Make requests to the monolith for notification specific auth checks](0018-make-request-to-monolith-for-notification-specific-auth-checks.md)

Amended by [26. Make request to the monolith to use premailer gem](0026-make-request-to-the-monolith-to-use-premailer-gem.md)

## Context

In [0002-build-a-notifications-service-outside-the-monolith](./0002-build-a-notifications-service-outside-the-monolith.md) we decided to build as much of the new notifications service outside the monolith as possible.

This decision presents an architectural challenge: to send notifications we will need data which is currently stored in the monolith, for example: user <-> content authorization data, the content which we need to send notifications about, and it's associated models (e.g issue comments and their associated issue; repository; organization; author).

One way to solve for this would be to make requests back to the monolith via internal APIs whenever we need the data, however, doing so would reduce many of the benefits of breaking out a separate service in the first place:

- **Resilience/Availability** - every time we make a request back to the monolith we put it back in the dependency path for delivering notifications.
- **Development Experience** - the more we depend on the monolith, the more code we have to write in the monolith, with it's associated problems.
- **Complexity** - A goal of the new platform is that notification delivery flows are easier to understand, and easier to change. The more code that is required for delivering notifications that does not live within the notifications service, the harder this will be.
- **Load on the monolith** - notification delivery is a high fan-out process: 1 comment can generate thousands of notifications. If every one requires many inter-service requests that increases load on other systems.

## Decision

Where possible we will design the architecture such that delivering notifications does not require requests to be made back to the monolith.

This may require:

- denormalizing data into the notifications system
- utilizing other services if they provide canonical sources of data via existing APIs, and can handle our load (e.g. Authzd)
- designing our event-processors, and API requests such that information flows in one direction from monolith -> notification
- making trade-offs around correctness of denormalized data; how quickly we can respond to changes in data in the monolith; correctness; etc

In short, we intend to as far as possible build a separate service, not just distribute a piece of the monolith into another repository.

## Consequences

### Benefits

- Improved separation of the notifications system from the monolith makes it more resilient, easier to understand, easier to change and easier to develop.

### Drawbacks

- Certain features or requirements may be harder or impossible to implement, or require different design trade-offs than if we did make requests back to the monolith.
