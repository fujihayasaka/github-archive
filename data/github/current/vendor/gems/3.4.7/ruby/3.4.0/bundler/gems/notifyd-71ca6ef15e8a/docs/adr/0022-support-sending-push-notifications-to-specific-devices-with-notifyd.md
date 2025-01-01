# 22. Support sending push notifications to specific devices with Notifyd

Date: 2021-11-04

## Status

Accepted

## Context

While working on supporting new mobile push notification use case (2-factor notificaitons) we discovered that the current pipeline did not support the needs of this notification type. One of the use cases that we needed to support was providing a way for integrators (in this case the authnd team) to specify which devices should receive the notification for a specific user. For more details on the requirements please see the [Support sending push notifications to specific devices with Notifyd](https://github.com/github/notifyd/blob/0cad6d4bd69639344db53a22f0e10190751c29da/docs/briefs/select-devices-to-receive-push-notification.md) brief.

## Decision

We explored a two possible solutions to this problem in [[Proposal] Support sending push notifications to specific devices with Notifyd](https://github.com/github/notifyd/blob/main/docs/proposals/sending-push-notifications-specific-devices.md). After implementing the [proposed solution](https://github.com/github/notifyd/blob/main/docs/proposals/sending-push-notifications-specific-devices.md#proposed-solution) in the proposal, we have accepted this as the current architecture for this problem.
**High level overview**

We will use the monolith [twirp api handler](https://github.com/github/github/blob/master/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb) as place for intergrators to hook into Notifyd filtering logic. 

Below is an example illustration of how the 2FA use case fits into this decision:

![image](https://user-images.githubusercontent.com/5173831/139260113-e61971b8-f791-4677-a524-2cf942be32eb.png)

## Benefits 

- Extending existing pattern
- Integrators have defined place to extend Notifyd filtering pipeline
- We have already found itegrators easily integrating logic in this hook (https://github.com/github/github/pull/198986)

## Consequences

- For now we accept integrator specific logic in Twirp API which is a pattern that we want to deprecate at some point in the future
