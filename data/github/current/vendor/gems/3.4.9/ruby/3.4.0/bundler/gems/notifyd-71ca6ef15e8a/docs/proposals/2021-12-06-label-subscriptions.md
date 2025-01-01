# [Proposal] Subscription to labels

## Overview

As outlined in the [brief for supporting label subscriptions](../briefs/label-subscriptions.md), we would like to support a single label subscription scenario: if an issue in a repository has a certain label and a user is subscribed to this label, the user will receive an email notification every time a comment is added to this issue.

For that, we need to add subscriptions support in Notifyd.

Expected outcome:

![image](https://user-images.githubusercontent.com/1885174/144611205-9a59f552-976f-40e8-80dd-e195a65b4d48.png)

This document is aiming to describe the solution and explain architectural decisions and tradeoffs.

## Design considerations

To notify the user as described in the scenario above we need to:

1. Permanently store the fact that the user wants to get notified about a particular label in a particular repository (we will call it "subscription" further in this document).
2. When the event "a comment is added to an issue" happens we need to analyse event related data (labels on the issue in our case) and retrieve corresponding subscriptions.

There are several things to consider when designing a solution:

1. What data shall we store as a "subscription"?
2. How shall we store this data in order to be able to retrieve it fast?
3. What data from integrators do we need in the notification event itself to be able to find out what users shall we notify for this event?
To rephrase it, how do we match an event to subscriptions?

## Proposed solution

We aim to create a flexible notification subscription feature that can be used by different integrators. We want to avoid having custom, integrator-aware logic in the service. Notifyd should receive the data to evaluate subscriptions through the `Notify` hydro message. We'd like to extend the existing `Notify` consumer to consider subscribed users when [calculating the list of recipients and their reasons](https://github.com/github/notifyd/blob/11a5ed1c81399cfc0fd6320021926ac5ebe55355/internal/notify/consumer.go#L81-L96). 

The architecture described in diagrams below is based on [Notifications Platform prototype](https://github.com/github/notifications_platform).

### 1. Script/Transition to add subscriptions

We will implement a script or data transition to generate subscriptions to a test label for notifications team.
This will help us to focus on how we want to extend the existing delivery pipeline to support subscriptions.

As we said in this [this section](https://github.com/github/notifyd/blob/main/docs/briefs/label-subscriptions.md#assumptions) of the brief:

> We don't need any UI for creating/managing subscriptions and this can be done at later stage

We assume here that we'll eventually build a system that can be used to manage subscriptions (Twirp API or maybe Hydro messages or maybe a GraphQL API or maybe something completely different).

### 2. Storage

Subscriptions will be stored in the MySQL Notifyd database in a table with the following schema:

| Column   |      Type      |  Description |
|----------|-------------|------|
| id |  bigint  | id of a subscription (primary key) |
| user_id | bigint | id of a subscriber |
| topic_type | string | topic type provided by integrator. For Dotcom it will be practically an `topic_type` that subscription corresponds to. Examples: `Label`, `Repository`, `Issue`, `PullRequest` etc. |
| topic_value | string   |  Unique identifier of the topic the user is subscribed to |

To prevent having duplicates we should add `uniq` index for `(user_id, topic_type, topic_value)`.

### Notifying subscribed user when event occurs

![image](https://user-images.githubusercontent.com/1885174/145413340-d7979e39-c798-4949-be2b-ef9a5f317581.png)

Let’s say we have a subscription stored as described in "Creating subscription". Now someone comments on the issue with the label we have a subscription for. The `Notify` hydro message shall contain the data necessary to retrieve subscriptions on Notifyd side.

We can use [existing message adapters](https://github.com/github/github/tree/8f8197449af8c35e154350454b225142e945df76/app/models/notifyd) in dotcom to map dotcom Active Record objects to the message format recognizable by Notifyd.

There are additional data pieces we need to put into `Notify` message object for subscription service:

**related_topics** - entities that message relates to (for example, create issue event message may be related to repository and a user that created the issue).

Once the correct message is formed it’s sent to hydro and consumed by notify consumer in Notifyd.

The Notify consumer asks subscription service for the list of users subscribed to the event.

The subscription service executes the following logic:

1. Select all subscriptions for related topics from the database.
2. Return the list of subscribed users to be notified for the event.

### Reasons for new subscriptions
The [`DeliverEmail`](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/deliver_email.proto) hydro message used to trigger email notification delivery requires a set of `reasons` for each recipient. [code link](https://github.com/github/notifyd/blob/238331f23f6405281a16b2611c7d3dbb5b33d526/hydro/schemas/notifyd/v0/deliver_email.pb.go#L27).

The subscription service will generate the reason based on the subscribed topic - `subscribed_to_#{topic_type}` - which allows other components in the deliver pipeline to make decisions based on the reasons (e.g the batch check twirp API endpoint (see [here](https://github.com/github/notifyd/blob/238331f23f6405281a16b2611c7d3dbb5b33d526/proto/monolith-twirp/notifyd/v1/notifyd_api.proto#L94)), or the rendering logic (see [here](https://github.com/github/notifyd/blob/238331f23f6405281a16b2611c7d3dbb5b33d526/internal/mobile/layout/layout.go#L12)). 

### Example

[Notify](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/notify.proto) message coming from dotcom side could look for example, like this:

```
{
  related_topics: [
    {Label : 1},
    {Label : 2},
    {Label : 3}
  ],
  actor: {
    id: actor_id
  },
  context: {
    repository_id: repository_id
  },
  authorization: {...},
  rendering: {...},
  notification_id: <Notification Id>
}
```

Then on subscription service side we would be able to query relevant 'Label' subscriptions from DB:
```
SELECT * from subscriptions where topic_type=Label and topic_value IN (1,2,3)
```

and then return results back to the `notify-consumer`.

### Benefits
- With this approach we won't have integrator specific logic in Notifyd.

### Drawbacks
- Integrators have to know in advance which `related_topics` need to be passed along with `Notify` Hydro message.

**Open questions**

**What's current load? How many subscriptions do we handle right now in `newsies`?**

We took this query as baseline for estimating number of subscriptions https://data.githubapp.com/sql/c4bce4b1-2de7-4e90-9907-ead305b3a9fe that is processed by newsies.
Answer is that at most we have 20k subscriptions per list (repo), which means that we need to support pagination mechanism, it's been already described in this issue - https://github.com/github/notifyd/issues/543
