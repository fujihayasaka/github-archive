# 13. Publish a rubygem from the github/notifyd repo for the monolith to use

Date: 2021-03-26

## Status

Accepted

## Context

In [./0012-use-twirp-for-requests-to-notifyd-from-the-monolith-which-require-a-response][./0012-use-twirp-for-requests-to-notifyd-from-the-monolith-which-require-a-response.md] we decided to use Twirp for building our request <-> response API.

One benefit of using twirp and its protobuf definitions for defining our API is that there are libraries that can automatically generate API clients in various languages for accessing the API. This includes [ruby](https://github.com/twitchtv/twirp-ruby/wiki/Code-Generation) which is what we would need for the monolith.

Other github services, including [authzd](https://github.com/github/authzd/tree/master/ruby) use this approach to generate ruby clients.

## Decision

- We will use our twirp protobuf definitions, and the [twirp-ruby](https://github.com/twitchtv/twirp-ruby) library to build a rubygem for accessing the notifyd twirp api.
- The required code/scripts to build this gem will live in the notifyd repository
  - There seems little benefit to separating this into a separate repository at this point
  - Keeping them in the same repository allows us to write integration tests between the server and client
- We will use this rubygem from the monolith to communicate with the notifyd API

## Consequences

### Benefits

- We can write and test the rubygem client outside the monolith, and pull it in when we have a new release - reducing the amount of code we have to write in the monolith directly
- This rubygem may also be a good place to put other supporting code that the monolith needs, such as protobufs for things like [layout templates](./0007-use-layout-templates-in-the-platform-with-protobuf-arguments-to-format-notifications-from-rendered-content-before-delivery.md)

### Drawbacks

- Releasing new versions of the gem will be a multi-step process (update the gem in the notifyd repo, vendor the gem into the monolith).
