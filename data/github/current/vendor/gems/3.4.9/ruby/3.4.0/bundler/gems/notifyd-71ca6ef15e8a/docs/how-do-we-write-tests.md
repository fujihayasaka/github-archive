# How do we write tests

<details><summary>Table of contents</summary>

<!--toc:start-->

- [How do we write tests](#how-do-we-write-tests)
  - [Introduction](#introduction)
    - [Some recommended material and bibliography](#some-recommended-material-and-bibliography)
    - [Glossary](#glossary)
  - [The testing pyramid](#the-testing-pyramid)
  - [How do we make tests fast?](#how-do-we-make-tests-fast)
  - [How do we increase the S/N ratio?](#how-do-we-increase-the-sn-ratio)
  - [How do we avoid flakes?](#how-do-we-avoid-flakes)
  - [Some examples](#some-examples)
  <!--toc:end-->

</details>

## Introduction

Testing is a big topic. Each developer has their own preferences and opinions
on how to write tests or what an ideal test suite looks like.

The goal of this document is to serve as a common ground where we can all agree
while testing the code of `notifyd` and also with some basic recommendations in
that sense.

In addition to that it aims to provide a paved path to adhere our project to
the GitHub's wide [testing strategy][3], more explicitly to these 5 points (as
the other 2 are more relevant for org-wide strategy.)

1. Tests are fast
2. Early signal for developers (`go test` generally does a good job achieving
   this, so we don't have to worry about it)
3. Documented test processes (this is the purpose of this document)
4. No more flakes
5. Outer Loop is Always Runnable in the Inner Loop (we've achieved that pretty
   well so far, so it is not a problem).

In addition to that we also want:

6. Tests have a high S/N ratio

That is, a failing test should mean that something in the code is broken, or in
other words: refactoring without changing behavior shouldn't break a ton of
tests.

This means the purpose of this document is mainly to explain how to fix `1.`,
`4.` and `6.`.

### Some recommended material and bibliography

- [Our own documentation](/docs/how-do-we-write-code.md) about writing code
- [This documentation][7] on `github/go.`
- [This article][3] on TheHub that describes GitHub's testing strategy in detail.
- [This talk][1] by Sandi Metz that explains what to test on unit tests.
- [This talk][9] by Sandi Metz about refactoring and how important good tests are for it.
- [This talk][4] by Justin Searls that explains how to split a whole test
  suite.
- [This article][5] by Martin Fowler that expands hon how to split test suites.

### Glossary

These are some terms used during this document and their definitions. I'm
defining them upfront so that we all have a common language to use.

- **System Under Test (_SUT_)**: The thing you are testing.
- **Unit**: The smaller possible element of a program (for example: a method, a
  class, a struct...).
- **External system**: Anything that is not purely your program (for example: a
  database, an API...)
- **Assertion**: a predicate that is always meant to be true for a test to pass
  (for example: "the string returned by method `a()` is equal to `"b"`")
- **Test double**[^1]: a unit (for example a method, an object, a struct...) that
  is used in testing to replace a part of a program with testing purposes.
- **Dummy**: a test double that is passed around but never actually used.
  Usually they are just used to fill a list of parameters.
- **Fake**: a test double that has a working implementation, they usually take
  some shortcut which makes them not suitable for production (for example a
  storage that works in memory instead of on a real database.)
- **Stub**: a test double that provides canned answers to calls made during the
  test, usually not responding at all to anything outside what's programmed in
  for the test.
- **Spy**: a type of stubs that also record some information based on how they
  were called. One form of this might be an email service that records how many
  messages it was sent.
- **Mock**: a type of test double that is pre-programmed with expectations
  which form a specification of the calls they are expected to receive. It can
  throw an exception if they receive an unexpected call. It is checked during
  the test verification to ensure it received all the calls it was expecting.
- **Dependency Injection (_DI_)**: A software pattern that consists on passing
  dependencies as arguments to a given class or structs. In the context of
  testing this allows dependencies to be substituted by _test doubles_.
- **Unit test**: a test that focuses on testing a single unit. It uses
  test doubles and DI to decouple itself from collaborators.
- **Integration test**: a test that traverses multiple units and ensures they
  collaborate appropriately. It uses test doubles and DI to decouple itself
  from collaborators with side effects (e.g. network calls, DB calls...)
- **Acceptance tests**: a test that operates the system from the point of view
  of an external user or integrator. It uses real systems whenever possible for
  things that produce side effects (like DB calls or API calls).
- **Contract tests**[^2]: a test that operates independently from the point of view
  of a client and a server/producer. It test in each case that both conform to
  a given contract.

## The testing pyramid

A common recommendation when talking about the composition of test suites is
to follow the [test pyramid][8] model.

This model organises the types of tests in categories depending on the how some
trade-offs change between them.

```
  COMPLEXITY | SPEED   | ISOLATION
***********************************
                          more
  complex    | slower  | integration
                                  |               /\
                                  |              /__\      Acceptance
                                  |             /    \
                                  |            /______\    Integration & Contract
                                  |           /        \
                                  |          /__________\  Unit
  simple      | faster | more     ----------------------------- > amount
                         isolation

```

- **Complexity**: How difficult it is to write and maintain a test. For
  example, unit tests are generally simpler to write as their setup is pretty
  lean, but acceptance tests are more complex because their setup has more
  dependencies (a DB connection, a cleanup phase, etc...).
- **Speed**: How fast does a test run. Unit tests are generally faster as they
  generally avoid collaborating with parts that are expensive or slow (like
  databases or network connections). On the other hand acceptance tests are
  slow since they usually depend on the same things (or almost the same things)
  that a real production system would depend on.
- **Isolation**: How much of the program code will a single test run.
  Acceptance tests provide a great level of integration as they generally
  traverse all the layers of the code. Unit tests, on the other hand are
  explicitly designed to increase the level of isolation.

The proponents of the [test pyramid][8] basically explain that by following
this model you will have a faster, more maintainable, and reliable enough test suite.

- It is faster because the majority of tests on it are fast
  (unit/integration/contract) and has a low number of acceptance tests, which
  are slow.
- It is more maintainable because it encourages writing small units that can
  easily be interchanged or rewritten without changes propagating all around on
  the test suite.
- It is reliable because you increase the coverage in many ways, you have
  enough integration and you can spend the proper effort on covering the edges
  through unitary/integration.

## How do we make tests fast?

For this, we focus on the 2 lower layers. That is, most of our tests don't
reach databases or networks in any way, they use some _test double_ instead.

This requires a swift paradigm change on how we write some of our code.

- We need to rely more on dependency injection as it makes composition easier
  to use.
- We need to star writing smaller things. This is probably the most complex
  part of all this and for which [this talk][9] give a very good example.

  Our goal is to have smaller (as small as possible) pieces that can be used
  together to compose bigger solutions.

## How do we increase the S/N ratio?

S/N ratio[^3] is a measure of how good a signal (S) is compared to the amount
of background noise (N) it is surrounded by.

All the measures applied to make tests fast have an effect here too:

- Dependency injection helps decoupling parts, making them better testable on
  isolation.
- Having smaller parts makes them easier to swap and refactor without affecting
  the rest of the application.

In addition to that:

- By focusing on testing the interface, not the implementation. This make
  refactors possible and less dramatic. Changes that keep the behavior (i.e.
  refactors) don't propagate around the whole test suite.

## How do we avoid flakes?

The team in charge of GitHub's testing strategy has some [good
documentation][11] explaining some of the most important categories for flake
tests.

They are written for Ruby, but they can be easily extrapolated to Go.

## Some examples

While having a written documentation on what we want to achieve is good,
examples are helpful as they make it explicit how to achieve it. This is a
non-exhaustive list. If you find other examples that better represent the ideas
in this document, please add them or change them!

- [This pr][12] introduces an interface to decouple the `apiservice` package
  (that spawns an http server with a given set of handlers and middlewares)
  from the handlers it spawns.

  Before this PR, the `apiservice` package depended on all the handlers it
  spawned. Adding or removing one would mean that all the tests for the service
  had to be modified.

  Now this dependency has been inverted, each handler has to implement an
  interface if they want to be used from the `apiservice`. The tests are no
  longer dependent and we can iterate on `apiservice` or on the handlers
  without affecting each other.

  In addition to that, since the `apisservice` package still needs to be
  tested, it introduces a **fake** service implementation that can be used instead
  to test without depending on the real ones (which depend on database,
  metrics...)

  Last, but not least, as the tests don't depend on the database anymore, went
  from 3 seconds to almost instantaneous.

- [This pr][13] extracts a new `body` package for our emails. This has a double
  effect:

  - We were able to have tests for the body itself that were more accurate,
    simpler and maintainable.

  - The `Sender` on the `email` can be tested on isolation, without depending
    on the body composition, which makes the test simpler and also isolates it
    from the implementation details of the body.

- [This pr][14] decouples the internal data structures of the `notify` package
  from the protobuf definitions.

  This makes the inner parts of the model easier to reason as it simplifies the
  data model and its interface.

  This new interface is easier to use and as such easier to test. It decouples
  the data model (the internal structs) from where it is used (the protobuf
  definition for the messages).

  This way the data model can be tested on isolation more easily.

- [This pr][15] refactors our code so that we inject a `clock` struct. This
  struct makes depending on the time (that is a constantly muting entity)
  explicit and transforms it into something that can be easily substituted by a
  test double like a **stub** or a **mock** when necessary.

  Because of that tests are easier to write, but more importantly flake tests
  are harder to write, because the code dependency on time is no explicit
  rather than implicit.

[^1]: Definitions for test doubles are extracted from [Martin Fowler's Bliki][2].
[^2]:
    There's some effort being done to make [turbocassette][6] a contract
    testing tool inside of GitHub.

[^3]:
    SNR or S/N ratio means ["Signal to Noise ratio"][10] and it is a measure
    of how much relevant information there is on a signal. It is a concept
    originally used in signal analysis.

[1]: https://www.youtube.com/watch?v=URSWYvyc42M "Sandi Metz - Rails Conf 2013 The Magic Tricks of Testing"
[2]: https://martinfowler.com/bliki/TestDouble.html "Martin Fowler - Bliki: Test Double"
[3]: https://thehub.github.com/epd/engineering/principles/testing-strategy/ "GitHub's testing strategy"
[4]: https://www.youtube.com/watch?v=9_3RsSvgRd4&t=22s "Justin Searls - Breaking up (with) your test suite"
[5]: https://martinfowler.com/articles/2021-test-shapes.html "Martin Fowler - Test Shapes"
[6]: https://github.com/github/turbocassette "github/turbocassette"
[7]: https://github.com/github/go/blob/main/docs/best-practices.md#testing "testing recommendations at github/go"
[8]: https://martinfowler.com/articles/practical-test-pyramid.html "Bliki - The practical test pyramid"
[9]: https://www.youtube.com/watch?v=8bZh5LMaSmE "Sandi Metz - RailsConf 2014 - All the Little Things"
[10]: https://en.wikipedia.org/wiki/Signal-to-noise_ratio "Signal to Noise ratio"
[11]: https://github.com/github/dev-and-test/blob/main/docs/learnings/flaky_test_learnings.md#symptom-categories "Flaky tests categories"
[12]: https://github.com/github/notifyd/pull/1733 "github/notifyd#1733"
[13]: https://github.com/github/notifyd/pull/1426 "github/notifyd#1426"
[14]: https://github.com/github/notifyd/pull/1532 "github/notifyd#1532"
[15]: https://github.com/github/notifyd/pull/1302 "github/notifyd#1302"
