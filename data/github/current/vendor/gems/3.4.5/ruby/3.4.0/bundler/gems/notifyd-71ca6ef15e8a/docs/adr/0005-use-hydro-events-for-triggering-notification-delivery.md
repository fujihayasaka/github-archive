# 5. Use hydro events for triggering notification delivery

Date: 2021-03-26

## Status

Accepted

## Context

On our busiest days, we deliver notifications for around 10M events on github per-day (resulting in around 120M delivered notifications).

Having decided to build the new system [outside the monolith](./0002-build-a-notifications-service-outside-the-monolith.md) we need a mechanism by which the monolith can trigger upwards of 10M notification requests per day.

Constraints/assumptions:

- The triggering service doesn't need to know if delivery was successful, only that a request to deliver notifications was accepted successfully.
- Once a request to deliver notifications has been accepted, it should not be lost until it has been processed.
- If delivery/processing fails for some reason, it should be retried.
- Delivery/processing of notifications should happen quickly, but is understood to not be instant, at peak traffic some delays are acceptable. Further, different types of notifications may be prioritised differently.
## Decision

We have decided that services should trigger notification delivery by publishing a [hydro event](https://hydro.githubapp.com/schemas/notifications-v0-Notify). The other obvious choice for inter-process communication at GitHub is a twirp (http) API.

Hydro has a number of clear benefits

- hydro is well supported at GitHub
- hydro can support our notification volumes (indeed we already publish a message to hydro for every notification we deliver)
- protobufs which are required for event payloads on hydro, are typed and self-documenting
- kafka, which backs hydro, is highly resilient - we can be confident that once kafka has accepted a message it will be processed
- hydro provides us with "queueing" for free. If we implemented an http API, we would likely have to implement a queue of some form to queue notification requests into anyway

## Consequences

### Benefits

- As discussed above, hydro and kafka have many clear and obvious benefits for building event-based services like ours.

### Downsides

- There is a certain level of complexity to building and operating hydro consumers that we are going to have to figure out.
- Services which want to trigger notification delivery will need to configure and use a hydro client and it's protobufs to do so.
- At present there is no authentication/authorization for hydro messages beyond having enough access to internal systems to publish messages. This means that any internal system may trigger notifications to be sent to users by virtue of having access. If this risk is of concern we may have to layer additional authentication on top of the message to allow us to verify the sending system.

### Risks

- Our uptime will be dependent on hydro's uptime.
