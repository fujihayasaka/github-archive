# 12. Use twirp for requests to notifyd from the monolith which require a response

Date: 2021-03-26

## Status

Accepted

## Context

In [0011-duplicate-mobile-device-tokens-into-the-new-service](./0011-duplicate-mobile-device-tokens-into-the-new-service.md) we referenced building a twirp API for internal communications, this ADR records that decision explicitly.

Twirp APIs are the standard for internal service communication at GitHub. For example the recently published [twirp feature flag api](https://github.com/orgs/github/teams/engineering/discussions/253) and [authzd](https://github.com/github/authzd) both use twirp. These services should be authenticated as per the guidelines on [HMAC headers and shared secrets](https://thehub.github.com/engineering/development-and-ops/secure-coding/secure-coding-general/service-to-service-auth/#service-to-service-auth).

Some of our functionality can be delivered solely with hydro events (as per [0005-use-hydro-events-for-triggering-notification-delivery](./docs/adr/0005-use-hydro-events-for-triggering-notification-delivery.md)) however in cases where a client (like the monolith) needs us to return a response with either a success status, or data, or both; we will require a request-response API of some sort.
## Decision

We will implement our internal API using twirp. It will be secured using HMAC signed headers with shared secrets.

## Consequences

### Benefits

- We will use standard patterns at GitHub.
- We can reference other projects for examples, and re-use internal libraries.
- We can generate ruby and go client code from the twirp protobuf definitions, to make it easier for other services to communicate with `notifyd`
- This would allow us to CRUD tokens when we move towards a complete ownership of the data model.
- Having a synchronous call allows us to know the result of the synchronization without having to rely on eventual consistency.

### Drawbacks

- The initial setup time for us to figure out how to write a new twirp API.
- Synchronous request-response APIs will create more internal coupling between systems than hydro events. This could present scalability/reliability challenges in the future if we use a request-response API where a hydro event would be preferable.
