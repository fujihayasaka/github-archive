# 7. Use layout templates in the platform with protobuf arguments to format notifications from rendered content before delivery

Date: 2021-03-26

## Status

Accepted

## Context

A challenge presented by [0006-provide-rendered-notification-content-in-hydro-events-at-triggering-time-not-delivery-time](./0006-provide-rendered-notification-content-in-hydro-events-at-triggering-time-not-delivery-time.md) is that it makes it hard to create notifications like this:

```
Subject: @mikrobi mentioned you and @github/notifications in github/github Issue #123

         <------> <-------------------------------------> <------------------------->
         content              reasons                           content
```

In this notification, the content data (which comes from the monolith) is mixed with reason information: which is determined within notification system during the delivery process and is specific to each recipient.

This combination means that neither the monolith nor the notification system can fully render the content of the notification, as neither has all the data required.

## Decision

We propose to solve this problem by using "layout" templates for notifications.

The notifications system will have a number of layouts that can be chosen from when triggering a notification, and the sender of the notification will be responsible for filling in the required data for the chosen layout to render a notification. Some contents of the layout may be filled in by the notifications system itself.

Here is a simplified example of two layouts for a push notification. In the "Default" layout the event contains the title/subtitle effectively as-is. However, for a "MentionableComment" the event contains the actor and subject instead of the full title. When rendered inside the notification platform, the reasons will be filled in with an appropriate string once the reasons have been calculated for the current recipient.

With this approach, the layout data can be provided once in the event, and be used to generate many notifications with the layout filling in the user-specific recipient reason data when delivering the notification.

```
Default Layout
┌──────────────────────────────────────┐     ┌───────────────────────────────────┐
│Event                                 │     │ Default Layout                    │     ┌───────────────────────────────────┐
│{                                     │     │                                   │     │                                   │
│  layout: "Default",                  │     │          ┌──────────────────────┐ │     │Title:    New login detected       │
│  data: {                             │  +  │Title:    │ event.title          │ │  =  │                                   │
│    title: "New login detected",      │     │          └──────────────────────┘ │     │                                   │
│    subtitle: "Review recent logins"  │     │          ┌──────────────────────┐ │     │SubTitle:  Review recent logins    │
│  }                                   │     │SubTitle: │ event.subtitle       │ │     │                                   │
│}                                     │     │          └──────────────────────┘ │     └───────────────────────────────────┘
└──────────────────────────────────────┘     └───────────────────────────────────┘

MentionableComment Layout
┌──────────────────────────────────────┐     ┌──────────────────────────────────────────────────────────────────────────┐
│Event                                 │     │ MentionableComment Layout                                                │     ┌───────────────────────────────────────────────────────┐
│{                                     │     │                                                                          │     │                                                       │
│  layout: "MentionableComment",       │     │           ┌─────────────┐ ┌────────────────────┐        ┌───────────────┐│     │Title:    @mikrobi mentioned you in github/github #123 │
│  data: {                             │  +  │ Title:    │ event.actor │ │notification.reasons│   in   │ event.subject ││  =  │                                                       │
│    actor: "@mikrobi",                │     │           └─────────────┘ └────────────────────┘        └───────────────┘│     │                                                       │
│    subject: "github/github #123",    │     │           ┌──────────────────────┐                                       │     │SubTitle:  Review recent logins                        │
│    subtitle: "Hello @latentflip"     │     │ SubTitle: │ event.subtitle       │                                       │     │                                                       │
│  }                                   │     │           └──────────────────────┘                                       │     └───────────────────────────────────────────────────────┘
│}                                     │     └──────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────┘
```

## Consequences

### Benefits

- Our hope is that this approach will provide enough flexibility to render user-specific notifications, without having to resort to making requests back to the monolith to render every notification.
- This should mean that for most use-cases an integrator simply needs to provide the data needed by the interface to generate a notification with no other code changes.

### Drawbacks

- Since layouts will live in the notifications service, if a feature wishes to send a notification that doesn't fit into an existing layout, they may have to create a new one, increasing friction for implementing a new notification type.
  - From reviewing existing notifications we believe this will be a rare occurrence.
- We will need to provide documentation for teams to discover/choose a layout and to provide the correct data for it.
