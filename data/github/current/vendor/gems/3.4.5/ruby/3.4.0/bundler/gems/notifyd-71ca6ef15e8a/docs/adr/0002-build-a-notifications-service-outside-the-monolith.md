# 2. Build a notifications service outside the monolith

Date: 2021-03-26

## Status

Accepted

## Context

A new platform is an opportunity to break out of the monolith and implement a standalone system. The reasons are mostly covered in the [consequences section](#consequences).

## Decision

As far as possible, all logic for determining recipients and delivering notifications will live in service(s) that exist outside the monolith.

## Consequences

### Benefits

- Clearer separation of ownership between services looking to send notifications, and the notifications system itself.
- Faster review-cycles with a reduced surface area of code to worry about.
- Less code to learn for new team members.
- More ownership and control of the development experience.
- Faster development, testing and deployment loops.
- (Eventually) reduced requirement to be on-call for the monolith.
- Forced separation from the rest of the monolith may help guide us towards more separate, and thus resilient architecture designs.
- Clearer interfaces for integrators to use to send notifications.

### Downsides

- May be harder for other teams to contribute to a service outside the monolith.
- Higher operational complexity as we have to run our own services.
- More requirement for us to be directly involved in the  GHES/GHAE process as once our services are included in these.
- Setup (time) costs of getting everything up and running.
- The separation of the notifications system from the rest of the monolith may make solving certain problems harder than if we were in the monolith.

### Risks

- By separating systems, we may have to make different tradeoffs about functionality/correctness/etc than we are used to making in the monolith. We will have to navigate these carefully to ensure we make trade-offs that are both product and architecturally sound.
- The web notification UI is heavily dependent on many pieces of content in the monolith, extracting it, and figuring out where the boundaries should be may be difficult.
