# 3. Use Twirp for RPC

Date: 2020-09-29

## Status

Accepted

## Context

Authnd is a service that will handle RPC calls from other GitHub applications. We need to decide how these applications
will communicate with it.

## Decision

We will use [Twirp](https://github.com/twitchtv/twirp) to build Authnd RPC services.

## Consequences

Twirp is an RPC protocol with broad support at GitHub. We have many existing applications, such as authzd, using it. There are many examples
of interacting with Twirp services from within the Monolith and all our other services.
