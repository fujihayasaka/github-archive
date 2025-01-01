# Enable the possibility to subscribe to labels in a repository

## Problem statement

We want to support a single label subscription scenario: if an issue in a repository has a certain label and a user is subscribed to this label, the user will receive an email notification every time a comment is added to this issue.

Our current notifications system (neither Newsies nor Notifyd) don't support this scenario. The decision was to implement this functionality in Notifyd.

At the moment we have an end-to-end [email delivery pipeline](https://github.com/github/planning-tracking/issues/585) in Notifyd. This is team shipped and we send email notifications only when the user is mentioned directly in the issue body.

In order to support the scenario described above we need to add subscriptions support to Notifyd.

### Current Notifyd email notifications flow:

![image](https://user-images.githubusercontent.com/1885174/144611230-10219a44-f0b9-4f6d-acd0-31d7360b028a.png)

Currently the `Notifyd` system supports only `@mentions` notifications but we don't have any subscription model setup.

### Expected outcome:

![image](https://user-images.githubusercontent.com/1885174/144611205-9a59f552-976f-40e8-80dd-e195a65b4d48.png)

As outcome `Notifyd` will have a basic subscription system in place that will allow to create/delete subscriptions and get subscribed users for incoming events processed by `Notifyd`.

## Context

We got a [request from LLVM](https://github.com/github/devrel/issues/874) where they ask to be able to subscribe/filter notifications by labels because they are overwhelmed by all the notifications they receive with the existing subscription capabilities of Newsies. The problem has been articulated by several customers in the past and we gathered [customer feedback](https://github.com/github/notifications/issues/864) to understand what notification scenarios are required. 

The current system (Newsies) is not architected to support these scenarios. The notification team did a research and came up with a prototype of a [Notification Platform](https://github.com/github/notifications_platform) that satisfies new requirements.

We want to build a subscription system in Notifyd that will replace Newsies in the future and support flexible scenarios requested by customers. Label subscriptions will be the first scenario that uses new subscription system's capabilities and will allow us to move LLVM migration to issues forward.

## Goals and objectives

- Build an MVP for the subscription service that supports label subscriptions and send notifications to subscribed users when the comments are added to the issue.
- Provide a basic API to create/manage notifications subscriptions

## Assumptions

- We're not concerned about optimising performance
- We don't need any UI for creating/managing subscriptions and this can be done at later stage

## Guiding Principles

* Notifyd shouldn't incorporate domain logic of integrators
* Integrator interface to issue notifications should remain as simple as possible 
