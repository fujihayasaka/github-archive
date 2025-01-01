# 36. Add sorbet type checking

Date: 2022-11-02

## Status

Accepted

## Context

Ruby is a dynamically typed language. While there are books written about the
trade-offs between dynamically typed languages, we (GitHub) have reached the
conclusion that gradually typing Ruby code is helpful and because of that there
has been an ongoing effort to add [Sorbet][sorbet] typings to the GitHub monolith.

The `notifyd-client` Ruby gem we use doesn't include any kind of typings for
its code, which makes it a bit complex to properly use it, even with the work
that has been done on the monolith to type it.

## Decision

We will include RBI definitions and Ruby types on the Ruby gem to help us
dynamically type the integrations we write while we migrate from newsies and to
help our integrators as well.

## Consequences

As a consequence of this we have:

- Installed `sorbet` and `tapioca` gems as development dependencies of our gem.
- Added a new `make sorbet`, `make tapioca` and `make rbi` targets to our
  `Makefile` that run as checks on the CI and that help us manage RBI
  generation.
- Written two custom DSL compilers for tapioca that fill in the pieces that
  tapioca RBI generation doesn't know about for Twirp RPCs.

[sorbet]: https://sorbet.org
