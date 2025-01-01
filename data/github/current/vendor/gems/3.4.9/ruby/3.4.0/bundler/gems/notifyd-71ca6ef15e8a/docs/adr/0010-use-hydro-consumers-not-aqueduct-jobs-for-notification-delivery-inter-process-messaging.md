# 10. Use hydro consumers, not aqueduct jobs for notification delivery inter-process messaging

Date: 2021-03-26

## Status

Accepted

## Context

The @github/data-pipelines team provide two related services for inter-process messaging.

- [Hydro](https://github.com/github/hydro)
  - Hydro is an event logging system built on Apache Kafka intended as a building block for data-driven applications.
- [Aqueduct](https://github.com/github/aqueduct)
  - Aqueduct is a scalable job queue service that allows applications to perform work asynchronously or exchange messages between system components.

These two systems are related - indeed Aqueduct is built on top of Hydro. And many workloads can be implemented with either system.

For job-like workloads (arguably like "deliver this notification please") Aqueduct brings a number of conveniences:

- No requirement for protobufs for payloads
- Throttling of job processing via chatops
- No need to operate your own hydro consumers as this is abstracted from you
- Retry logic/data warehousing is built in

For these benefits, you give up a few things:

- Aqueduct has no strict order on message delivery
  - Kafka/hydro will process all messages on a given partition in order, with aqueduct we lack this control
- Aqueduct is less scalable than hydro
  - Aqueduct has a 10k/second job ceiling across all of GitHub, while kafka is effectively infinitely scalable [slack](https://github.slack.com/archives/C94P20RGQ/p1615413019194400)
  - For reference as of today we deliver at peak around 3k notifications per second
- Aqueduct has no ability to process jobs in batches
  - With hydro we could process messages in batches, perhaps to cut down the number of reads/writes we make to external services/databases

These downsides feel relevant to notifications at present. _Strict_ ordering of notification delivery may not be critical but it's certainly preferable. A scaling headroom of only 3x feels limiting if that limit is fairly fundamental (as it appears to be ). And batching could be very effective for some of our workloads.

## Decision

- We will build our new service on hydro consumers for the foreseeable future.
- We will aim to implement the majority of our service logic in a way that is not too tightly coupled to the choice of aqueduct/hydro in case we choose to change this decision in the future as we learn more.

## Consequences

### Benefits

As discussed above, hydro consumers should give us more flexibility and scalability to build out the new service.

### Drawbacks

The drawbacks of hydro mostly center around the development and operational complexity of building kafka consumers to handle (non-exhaustively):

- rebalancing
- head of line blocking
- retries
- dead letter queues
- throttling of processing rates

This will result in more learning for us as a team to do, and more time required to solve these problems.
