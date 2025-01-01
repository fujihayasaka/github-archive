# 11. Duplicate mobile device tokens into the new service

Date: 2021-03-26

## Status

Accepted

## Context

As we build out the first iteration of the new platform ["Mobile push notifications for @mentions in issue comments delivered by a new notifications platform"](https://github.com/github/i2c-backlog/issues/671) we were presented with the challenge of how to access user's mobile push device tokens from the new service.

These are generated on a users mobile device, and sent to the monolith via the graphql API, where they are stored in the `mysql2` database.

We explored a few options:

1. use vitess vreplication to clone the entire `mobile_device_tokens` table from `mysql2` to our new cluster
  - too complex
  - too temporary
  - mysql2 is not currently using vitess
2. access the tokens in `mysql2` via an api request from `notifyd`
  - violates [./0003-minimise-requests-from-the-notifications-service-back-to-the-monolith](./0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md)
3. duplicate the tokens from the monolith to `notifyd` via an api request
## Decision

We will implement option **3.** Notifyd will have an internal twirp API which the monolith will use to update `notifyd` about changes to users' device tokens.

This most closely resembles what the architecture will look like when we have fully replaced the existing notifications code - with mobile devices communicating only with the monolith via GraphQL, and relevant data being forwarded-to/retrieved-from notifyd via internal twirp requests.

## Consequences

### Benefits

- We are working towards the longer term architecture, instead of doing something more temporary

### Drawbacks

- We have to figure out building a twirp API and a ruby client for it up front. Which will slow down our initial iteration (but hopefully speed up late ones).
