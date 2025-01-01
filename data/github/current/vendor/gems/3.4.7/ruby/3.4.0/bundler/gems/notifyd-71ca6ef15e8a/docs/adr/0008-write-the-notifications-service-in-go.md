# 8. Write the notifications service in go

Date: 2021-03-26

## Status

Accepted

## Context

The existing notification platform (newsies) is written in ruby, as it is in the monolith. Since we are building a new service we have an opportunity to consider a different choice.

The main paved paths for services at github are:

- [Ruby](https://github.com/github/ruby-lang)
  - github, mail-replies, dependency-graph-api, octoshift, pages, render
- [Go](https://github.com/github/go-lang)
  - alive, aqueduct-lite, authzd, gitrpcd, gpgverify, hookshot-go, kafka-lite, launch, lfs-server, registry, spokesd, token-scanning-service, treelights, turboscan

The current engineering team may not know go, but we thought it was worth exploring for a few reasons:

- **better paved paths for new services** than ruby - most new services have been written in go, so there are a lot more examples to reference and teams to talk to
- **performance/concurrency/cost** - hookshot-go, which is a fairly similar shape of service to notifications, was able to leverage concurrency in go to significantly reduce the number of resources required to deliver webhooks
- **ease of learning** - having spoken to a number of engineers who transitioned from ruby to go when breaking out services (alive, authzd, hookshot-go) the transition is reportedly a positive experience
- **fast build/test/compile/deploy loops** - a big frustration of monolith development is slow cycles. Granted this is as much about the monolith as it is ruby, but this a frequently reported benefit of go
- **static types** - beauty is in the eye of the beholder... but static typing and compilation-time checks seems pretty promising for creating a resilient and comprehensible system.


## Decision

After building an [initial prototype](https://github.com/github/notifyd/tree/b12a0806f2d5e5065737db952451e3a176741d52) in go that could deliver mobile push notifications in go, we have decided to use go as our core language for the new notifications system.

## Consequences

### Benefits

As discussed in the [Context](#context) we expect that go will give us a number of benefits both in development and at runtime.

### Drawbacks

- Our existing team has primarily been using ruby so we can expect to spend some extra time/code-churn as we learn go and its patterns/libraries etc
- Other engineers working on the monolith in ruby who look at our service may find it harder to contribute to/understand
- We will not be able to lift any existing code/libraries as-is from the monolith into the new service

### Risks

- Beyond the drawbacks above, the biggest risk is that we half-ship a new notifications platform, with some notifications going through the new service, and some still in the old service, but don't have the funding to complete the transition. This would leave us supporting two platforms in two different languages.
