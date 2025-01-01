# 35. Move away of aqueduct bridge

Date: 2022-10-18

## Status

Accepted

## Context

In the week of 2022-07-18 notifyd suffered a series of incidents described in
this [RCA][1]. The bottom line is that aqueduct bridge has some limits we were
not totally aware of and it can hurt our availability and throughput heavily.

While the service's stability has been excellent and the data pipelines team is
working on improving their latency, it is also important to notice that
aqueduct bridge was just a tool that we used [moving to aqueduct][2] in order
to easily drain our old hydro topic and have an easy way to publish to
aqueduct.

We can now afford to publish to aqueduct directly and remove this extra moving
part.

## Decision

We will move away from aqueduct-bridge.

## Consequences

### The dotcom publisher

This publisher was modified while [moving to aqueduct][2] in order to use a
feature flag to either publish to the old direct hydro topic or to the new
"aqueduct-bridged" topic.

This has now to change so that it publishes directly to aqueduct instead.

### The retries system

Our message retry system works by republishing to hydro from aqueduct after a
backoff period. This can now be heavily simplified by just directly enqueueing
to aqueduct with a proper backoff period instead.

### The workers and the pipeline

Our workers communicate with each other through hydro too. While we have not
detected that they have already hit the traffic limit that we found on
aqueduct-bridge, it is only a matter of time that they do.

That's why we also want to implement an aqueduct-direct strategy for them.

## Still undecided

### Hydro schemas

Our message schemas are right now owned by hydro-schemas. This is something
that has been convenient for now, but we might want to move the ownership to
our repository and share them with the monolith or others via our gem.

### Integrators

The authentication team delivers a hydro message to our aqueduct-bridged topic.
They produce a small amount of traffic, so it is lower priority to move them to
an aqueduct-direct strategy.

In this case I think it is worth exploring the following:

- Exposing a Go client for notifyd.
- Using it from their project.

That way any further change to our publishing mechanisms will be properly
encapsulated and controlled by us.

[1]: https://github.com/github/notifications/issues/1414 "RCA"
[2]: ./2022-04-27-pipeline-scale.md "Pipeline Scale"
