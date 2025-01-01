# Notifyd platform fundamental requirements

## Motivation

Notifyd is a new notifications platform for GitHub that eventually shall replace current Newsies system. We build it from scratch and have to make sure that Notifyd platform is capable to satisfy current and future requirements. This document aims to outline key requirements we must consider when adding new functionality or modifying existing one in Notifyd.

Whenever we make changes or proposals we have to check if proposed architecture/code changes satisfy all the requirements we deem important in the current stage. If not, we must re-iterate on architecture proposal or implementation. These requirements should be criteria we measure our quality by. If we see that parts of the system we implemented do not satisfy the requirements we need to either re-architect/re-implement them or document any shortcut made so that they can be reevaluated and fixed when appropriate.

## Requirements

### 1. Integration simplicity

It must be easy for integrators to add new notifications scenarios without participation of Notifyd team.

**Rationale**

This requirement is one of the main reasons we deprecate Newsies. Cost of maintaining and using notification system that requires changes for every integration is too high. We want to cut the time spent on integrations on both Notifyd and integrator's side.

**Implications**

The problem is that Newsies embodies too much integrator logic to accomodate certain integration cases. We want to avoid that and keep Notifyd both generic and flexible to satisfy custom cases. It means that we must not leak any monolith (or other system) logic into Notifyd codebase.

It works other way around as well: Notifyd shall not leak internal implementation details to integrators by exposing them in the interfaces.
[Example](https://github.com/github/github/blob/561fe95dc48cabcf1098c864301f5a5627566021/app/models/notifyd/notify_publisher.rb#L44-L52) of leaking internal details that we shall avoid.

Another implication is that we should be able to have clear instructions on how to integrate with Notifyd that would be true for every case (or vast majority of them). We should minimize the time we spend consulting other teams on how to integrate with Notifyd.


### 2. Separation from Newsies.

Notifyd domain must be separated from Newsies.

**Rationale**

We want to simplify transition from Newsies to Notifyd and avoid bad user experience during this transition phase. We also want to avoid slowing down the implementation of new functionality.

**Implications**

When integrating Notifyd with monolith we must avoid mixing Notifyd logic with Newsies logic and shall separate the implementation as much as possible.

[Here](https://thehub.github.com/engineering/products-and-services/dotcom/app-partitioning/) is a doc describing app partitioning effort and why it is important.


### 3. Maintainability and extensibility

It must be easy to add new functionality to Notifyd.

**Rationale**

Our codebase is quickly evolving and it's critical that we are not held back by code that is hard to comprehend and extend.

**Implications**

We'll have to make sure code we write follows the following rules:

1. Well structured
2. Easy to follow
3. Easy to extend
4. Has a great test coverage so that we can painlessly refactor it to satisfy this requirement

### 4. Reliability

We must not lose notifications or deliver them incorrectly.

**Rationale**

Dropping notifications or not notifying users on the events they subscribed to will result in bad user experience and defeats the purpose of the whole notifications system.

**Implications**

When adding new functionality we must consider unhappy paths. We must avoid or if possible completely exclude having corrupted data stored in Notifyd and make sure that all the notifications are eventually processed.

### 5. Observability

We should have the information related to the system health.

**Rationale**

We constantly add new functionality and refactor our code and it's critical for us to have insight into what's going on in the system to be able to quickly identify problems on production and resolve incidents with minimal customer impact.

**Implications**

We need to make sure we have proper logging, datadog metrics and tracing in place.

### 6. Throughtput

Notifyd must be able to deliver notifications mostly without delays.

**Rationale**

User experience will degrade if we fail to deliver notifications within reasonable time. What is "reasonable" may depend on the type of notifications (for example, watching is less importnant than participating or mentions). Currently we do not prioritize notifications but acceptable delivery time defined by our [SLO](https://app.datadoghq.com/slo?slo_id=078512b7c0095e84ae7d558b35c7a01b&timeframe=7d)

**Implications**

We'll have to make sure that disregarding the amount of notifications and recipients we're able to process notifications without delays. We need to

1. Identify and get rid of bottlenecks we currently have in Notifyd that can reduce our throughtput.
2. Make sure processing of individual notification is as fast as possible
3. Make sure that increasing number of notifications processed by notifyd will not result in breaching our [SLO](https://app.datadoghq.com/slo?slo_id=078512b7c0095e84ae7d558b35c7a01b&timeframe=7d)

The future functionality we add should not be introducing bottlenecks or slowing down processing.
