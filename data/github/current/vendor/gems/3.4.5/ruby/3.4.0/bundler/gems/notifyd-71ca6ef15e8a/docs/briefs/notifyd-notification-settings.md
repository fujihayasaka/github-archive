# Porting notification settings from Newsies to Notifyd

## Problem statement

We'd like to [migrate notification for CI activities from Newsies to notifyd](https://github.com/github/planning-tracking/issues/822). Newsies allows users to   configure these notifications through their [notifications settings page](https://github.com/settings/notifications) which is backed by the [`notification_user_settings`](https://github.com/github/github/blob/9f3053fe818e7757842295f628d158ba055ad0d4/db/mysql2-structure.sql#L124-L147) table in `mysql2`:

<img width="1062" alt="image" src="https://user-images.githubusercontent.com/423347/161727671-a78a96b3-8efc-4bba-8d4b-cab8d8ea9d66.png">

Newsies doesn't allow users to configure these settings on a repository level: they apply for all repositories at the same time. [github/notifications/#836](https://github.com/github/notifications/issues/836) describes a few more issues related to notification settings in Newsies from a product perspective.

**As of today, Notifyd doesn't provide any way for users to manage their preferences about how and if they want to receive notifications for CI activities.**

## Context

In the context of [expanding the support for label subscriptions](https://github.com/github/planning-tracking/issues/847) we proposed [generic subscriptions](https://github.com/github/notifyd/blob/main/docs/proposals/generic-subscriptions.md) that allow users to subscribe to application events based on contextual data. Integrators will be able to attach arbitrary contextual data to their events that users can use to define conditions about when they want to receive a notification. For example, users will be able to subscribe to the events of a repository related to discussions that are associated to a specific label.

The subscription component answers the question of 

- Who is interested in receiving (a) notification(s) for a given event?

Integrators can define [explicit recipients](https://github.com/github/hydro-schemas/blob/267c81a808934cd80e1ccb43feddc25af8d2c838/proto/hydro/schemas/notifyd/v0/notify.proto#L89) for a `Notify` event. Based on these two data sources (explicit recipients and subscribers) notifyd is able to aggregate a set of **potential** recipients.

Notifyd needs to answer a few more questions before rendering and delivering actual notifications to the potential recipients:

- Who of the potential recipients are allowed to receive the notification? (E.g. authentication or spam checks)
- Who of the potential recipients actually want to receive a notification for the event (E.g. blocking users, ignoring repositories, disabling ci-activity alerts)
- Where want the recipients get the notification delivered to (mobile, email, ...)?

As of today notifyd can already answer some of these questions: In the `Notify` handler we [remove unauthorized users from the list of recipients](https://github.com/github/notifyd/blob/76b6a3d5938d9fcfc280d9dec1e1441e570934d2/internal/notify/handler.go#L121) and [send a TWRIP API request to the monolith](https://github.com/github/notifyd/blob/76b6a3d5938d9fcfc280d9dec1e1441e570934d2/internal/notify/handler.go#L140-L142) that helps us to discard events coming from [spammy authors](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L122-L127), or authors that are [blocked by the recipients](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L154-L158), or events that are [related to a repository that the recipients ignore](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L167-L178). Other than a simple [hard-coded list of "reasons"](https://github.com/github/notifyd/blob/76b6a3d5938d9fcfc280d9dec1e1441e570934d2/internal/notify/handler.go#L191) we don't have a lot of logic that answers the questions about where (which channels) a notification should go to.

## Goal

In the context of [migrating notifications for CI activity](https://github.com/github/planning-tracking/issues/822) from Newsies to notifyd we'd like to propose a generic filtering and routing component on top of the subscription system that allows users to define their preferences, so notifyd can properly decide if and through which channels (push, email, ...) a potential recipient should be notified (green box in the graph below).

<img width="1208" alt="image" src="https://user-images.githubusercontent.com/423347/161574057-e39faf37-2c92-4bff-aa8f-7c59130233f8.png">

We'll have to think about how
- the system should be embedded into the existing pipeline,
- what kind of data it needs (both from the integrator and the users),
- where and how the data should be transfered and stored,
- how persited data should be managed (API for CRUD operations),
- how we can migrate existing settings in Newsies to notifyd.

As we can't foresee all possible features in the future, we want to consider at least a few of the know use-cases when designing a solution:

- Opt-in/opt-out: Integrators should be able to trigger notifications targeting specific users who can manually disable these notifications (examples in Newsies: ci activity notifications, security alerts, mentions).
- Channels: Users should be able to specify where notifications should be delivered to (email, mobile, ...).
- Global vs specific: Users should be able to configure their channels for all, a broad or a very specific set of notifications.

Examples:

- As a user, I want to receive an email each time a CI workflow completed with a failure.
- As a security integrator, I want to trigger notifications to all repository admins when a security vulnerability has been detected.
- As a user, I want to receive security alerts via email.
- As a user, I don't want to receive security alerts for my personal test repository.
- As a user, I don't want to receive any notifications coming from the `github/entitlements` repository.
- As a user, I want to receive an email and a push notification if I was mentioned anywhere on GitHub.com
