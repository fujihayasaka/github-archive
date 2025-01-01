# 2. Store Events in the DAG

Date: 2024-11-05

## Status

Accepted

## Context

Events within Enterprise Live Migrations (ELM) refer to resource updates (e.g. issue edits). Updates originate from webhooks, are transformed into domain-level event objects, and sent to the ELM API for processing.

Events are sourced via webhooks and sent to the ELM API by the crawler. Once the API receives an event, it will process it in one of two ways:

1. **Deferment**: If the resource which the event references **has not** been migrated, the event is stored and no further processing occurs. Stored events are applied at resource creation time.

2. **Immediate**: If the resource which the event references **has** been migrated, the event will be queued for processing.

## Decision

Events will be stored within the DAG for determining when they should be processed. Events will establish a dependency with the resource that they modify. The event within the DAG will not contain the event payload, but will contain a unique identifier which allows for the event to be looked up in the event store.

## Consequences

* The logic for determining when to process events re-uses the existing resource processing logic.
* The DAG must be modified to support multiple node types.
* The DAG worker, and all DAG consumers, must be modified to expect multiple node types.
* A new failure mode is introduced: An event may be written to the event store but not the DAG.

## Alternative(s) Considered

The alternative considered was to use only the event store. This required that either the API, or an event worker, implement logic for determining when an event was ready for processing. As this logic is similar to how we determine when to process a resource within the DAG, this alternative was turned down.
