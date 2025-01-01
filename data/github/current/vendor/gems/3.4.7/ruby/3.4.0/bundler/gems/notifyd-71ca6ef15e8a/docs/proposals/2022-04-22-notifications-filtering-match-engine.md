# [Proposal] Match engine for filtering notifications in Notifyd

## Brief

[Brief](https://github.com/github/notifyd/blob/main/docs/briefs/notifyd-notification-settings.md) describes how filtering and routing works on top of the subscription system that allows users to define their preferences. 

In previous [Proposal](https://github.com/github/notifyd/blob/main/docs/proposals/notification-filtering-and-routing.md) we have defined high level plan how Notifyd could support such filtering and routing component. 

Essential part of this component is **Filtering Engine** and this proposal focuses on its implementation details.

In the way that's similar to subscriptions - integrators should be able to define filtering rules based on the contextual data which is attached to the `Notify` message. 

Given that we have shipped suppoprt for [Generic Subscription](https://github.com/github/notifyd/blob/main/docs/proposals/generic-subscriptions.md) that already incorporates logic for **Subscriptions Rules Matching Engine** we will explore how we can apply same/similar logic for **Notification Filters**.

![image](https://user-images.githubusercontent.com/5173831/164486132-dc7b2d6f-b589-42cb-b1bf-c432010ce8a8.png)

**Match Rules Engine** is component that we want to describe in this proposal.

Given a `Notify` hydro message and a set of potential recipients, the component should be responsible for answering the following questions:

- Who of the potential recipients actually want to receive a notification for the event (E.g. [blocking users](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L154-L158), [ignoring repositories](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L167-L178), disabling ci-activity alerts, ...)
- Which check channels are preferred to receive specific Notification?

## Overview

This document proposes a solution for  **Filtering Engine**.

## Context

First of all here is some context from previous proposal:

### The new generic subscription system

We are currently [implementing a subscription system](https://github.com/github/planning-tracking/issues/847) that will allow users to  [subscribe to events by defining conditions](https://github.com/github/notifyd/blob/main/docs/proposals/generic-subscriptions.md#integration-interface-and-examples). 

These conditions can be defined on the contextual data that integrators can attach to their `Notify` message. Part of the new subscription system will be an engine that can match existing subscriptions with the contextual data of an incoming [`Notify`](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/notify.proto) message (see [github/github/notifyd#954](https://github.com/github/notifyd/issues/954)):

<img width="1030" alt="image" src="https://user-images.githubusercontent.com/423347/162013184-d083b34d-4b87-42f8-a833-167822cd67bf.png">

Example for a subscription:

- As a user, I want to get notified when someone creates a new comment on issue in the `github/github` repository that has the "Bug" label.

### Explicit recipients

While subscriptions allow users to express what they are interested in, there can be other actors who want to notify specific users about an event although they might not have actively created a subscription matching the event.

Notifyd allows integrators to define [explicit recipients](https://github.com/github/hydro-schemas/blob/238a1b4ac5708061235e922619923fd722c0f504/proto/hydro/schemas/notifyd/v0/notify.proto#L97) on a `Notify` hydro message. Notifyd will attempt to notify these users about the event. The integrator needs to provide a [reason](https://github.com/github/hydro-schemas/blob/238a1b4ac5708061235e922619923fd722c0f504/proto/hydro/schemas/notifyd/v0/notify.proto#L18-L20) for each recipient that tells Notifyd why they are listed as explicit recipients.

Examples for explicit recipients:

- As a security integrator, I want to notify all repository admins as soon as a new security vulnerability is detected in their code.
- As a user, I want another user to be notified when I mention them in one of my comments.
- As a PR integrator, I want to notify a user if the CI build failed after they created a PR.

### High level definition for what Notification Filter is

Here are a few examples for user-defined filter and routing rules:

- As a user, I want to receive all notifications related to the `github/notifyd` repository as emails.
- As a user, I want to receive a mobile push notification when someone mentions me on github.com
- As a repository admin, I don't want to receive any security notifications for my test repository even if security vulnerability are detected.
- As a user, I don't want to receive any notifications for the `github/github` repository.

While users can use subscriptions to express what they are interested in, they can use filter and routing rules to express through which channel(s) they want to be notified and about what they **don't** want to be notified. We can derive the following attributes of a filter and routing rule:

- `user`: The user to which the rule should be applied.
- `contextual_conditions`: Conditions that need to match with the contextual data of the `Notify` message to apply the rule.
- `channels`: Set of channels that will be affected by the rule. If empty, the rule applies to all channels.
- `notify`: Flag indicating whether the user wants to receive a notification for the matching `Notify` message or not.

Let's translate the examples above into some pseudo code:

> As a user, I want to receive all notifications related to the `github/notifyd` as emails.

```
{
    contextual_conditions: [
        related_topics contains "Repository": 123
    ],
    channels: ["email"],
    notify: true
}
```

> As a user, I want to receive a mobile push notification when someone mentions me on github.com

```
{
    contextual_conditions: [
        reason == "mentioned"
    ],
    channels: ["push"],
    notify: true
}
```

> As a repository admin, I don't want to receive any security notifications for my test repository even if security vulnerability are detected.

```
{
    contextual_conditions: [
        related_topics contains "Repository": 345,
        subject_type == "VulnerabilityAlert",
        trigger == "detected",
    ],
    channels: [],
    notify: false
}
```

> As a user, I don't want to receive any notifications for the `github/github` repository.

```
{
    contextual_conditions: [
        related_topics contains "Repository": 567,
    ],
    channels: [],
    notify: false
}
```

## Proposed Solution

Once Notifyd has calculated all potential recipients (explicit recipients & subscribers), it needs to decide who of these potential recipients should actually receive a notification and which recipients should be filtered out. 

### Matching filter and routing rules with `Notify` message

Similar to subscriptions, Notifyd needs to find applicable filter and routing rules for a given `Notify` message by matching the data of the message with conditions of existing rules. In contrast to the subscription use case, we also have a set of potential recipients with reasons to find matching filter and routing rules. Here is how we could compare the high-level match functions for subscriptions and filer/routing rules in pseudo code:

```go
func findSubscriptions(contextualData) []Subscription

func findFilterAndRoutingRules(contextualData, potentialRecipientsWithReasons) []Rules
```

The core functionality of both functions is some kind of a match engine that can match given contextual data of a `Notify` message with a set of contextual conditions. As both use-cases operate on the same contextual data, we propose to implement a match engine that we can use for matching subscriptions and matching filter and routing rules:

<img width="1377" alt="image" src="https://user-images.githubusercontent.com/423347/162414515-7bedff61-b2a7-4807-93d6-e0cbe48e8a69.png">

### Defining Matching rules schema

Given that **Notification Matching Rules** seems quite similar to **Subscription Matching Rules** it makes sense to take a closer look at **Subscriptions** tables. 

**Subscriptions_v2** 
This table stores single subscription item which is related to single **user_id**, for specific **Subject_type**, per **topic**, per **trigger**

For example: 
- For `User 123` on `Repository: github/github` when `Subject: Issues` is `trigger: created` subscription should match. 

**Subscription Match Rules**
This table stores additional match rules assosialted with specific subscription, that go beyond filtering by **Subject_type**, per **topic**, per **trigger**. User can define set of arbitrary rules to match subscriptions. 

Single **Subscriptions_v2** can have several Match Rules.

For example:
- For `User 123` on `Repository: github/github` when `Subject: Issues` is `trigger: created` and `author is not user 456` subscription should match.


On `Subscription Match Rules` side we will define additional record that will indicate match rules that is related to `actor_id`:

```sql
SELECT id, user_id, attribute, value, match_rule FROM subscriptions
        INNER JOIN subscription_match_rules ON subscriptions.id = subscription_match_rules.subscription_id
            WHERE subscriptions.topic_type = 'repository' AND subscriptions.topic_value = '123' AND
            (
                subscriptions.subject = 'issue' AND subscriptions.trigger = 'labeled'  AND
                (
                    (attribute = 'author_id' AND (subscription_match_rules.value = '456' OR  match_rule != 'eq')) OR
                )
            )
```


**Meta subscriptions**
Meta subscriptions are responsible for aggregating **Subscriptions_v2** rules and is used for rendering Subscriptions data on UI. 


We could take a step back and think if **Subscriptions Match Engine** semantic can be applied to **Notification Filters**.

Let's take a look at high level **Notification Filter** schema:
```
{
   conditions: [
        related_topics contains "Repository": 345,
        subject_type == "VulnerabilityAlert",
        trigger == "detected",
    ],
    channels: [],
    notify: false
}
```

**Subscriptions_v2** looks very similar to **Notification Filter Rule**  
However there are several differences: 
- `Channels` are not part of **Subscriptions_v2** schema (yet? because we said that we may want to think about channels a bit later?)
- **Subscriptions_v2** schema doesn't define negative conditions - `Notify: true`

Other than that those 2 domain models share lot of propetries answering different questions:
- which **User**
- which **subject_type**
- on which **topic**
- for what **trigger**

should be Notified vs Filtered out from receiving notifications.

### Designing Storage layer for Match Engine

We can consider several options for modeling storage layer for **Match Engine** for **Notification Filters**

### Option 1 - store data needed for Subscriptions Match Engine and Notification Filters Match Engine in generic schema

With model described above and requirements for Match Rules engine needed for **Notification Filters** it looks reasonable to reuse **Notification subscriptions** rules model.

![image](https://user-images.githubusercontent.com/5173831/165063766-625b7449-283e-42a1-924c-594b293edbc9.png)

Idea here would be that  **Subscriptions_v2** would be renamed to **Match Entries** table. 
**Match Entries** will be responsible for association between user and attributes that should match with incoming notification events. 

**Match Entries** will define association that can be used for **Subscription** or **Notification Filter**

- which **User** will be recipient for incoming Notification event
- which **subject_type** of Notification event should match to **Match Entry**
- on which **topic** of Notification event should match to **Match Entry**
- for what **trigger** of Notification event should match

additionally we want to define several additional fields:
- **type** - defines if **Match Entry** is going to be used for **Subscription** or **Notification Filter**
- **notify** - true/false - flag indicating whether the user wants to receive a notification for the matching Notify message or not.

**Match Rules** be be reused 1-1 since it's a simple EAV model as of now that will be bound via assosiation to **Match Entries**.

**Meta filters** table will same thing for **Notification Filters** to what **Meta subscriptions** does to **Subscriptions** - it's going to aggregate information about **Match Entries** and **Match Rules** in order for it to be rendered on UI. 

It's meant to be consumed by concrete **User** when viewing Settings page which could in the future become something like this:

![image](https://user-images.githubusercontent.com/5173831/165085878-c9d529f1-55ef-4f1e-8cdb-114818a6a004.png)


**Pros**
- Schema for Match Engine model for Subscriptions and Notification Filters looks very similar as of today, so we can benefit storing those 2 things in single table
- If we store  Match Engine model for Subscriptions and Notification Filters, we could poteniaully optimise Subscriptions queries in the future, by excluding subscriptions from final result set that will never match due to disabled filter (but it might not happen as well).
- During design stage I felt difficulty picking right name for table that we call now **SubscriptionsV2**, as of today it stores info single subscription item. If we make it sote **Notification Filter** in same 


**Cons**
- This move is limiting us if we want to add Notification Filter specific properties to **Match Engine model** later. We might end up in situation where generic table has 3-4 columns specific only **Subscriptions** or **Notification Filters**
- Complexity of indexes will grow as well as number of rows in single table over time which may cause (unlikely) perf challenges.


### Option 2 - create Notification Filters Match Engine in schema specific for Notification Filters only

As Option 2 we can maintain separate set of tables for **Notification Filters**. Consider diagram:

![image](https://user-images.githubusercontent.com/5173831/165132549-5ce28d90-bd5b-4f6e-800d-4c8881ff40e5.png)

We won't touch **Subscriptions** tables and will have __similar__ tables for **Notification Filters**. 

Proposed tables:
**filters** - this table will store records that will define single **Notification Filter** and describe
**filter_match_rules** - this is EAV table that stores match rules for additional attributes to match notificaiton filters rules
**meta_filters** - this table will store aggregated data for displaying notification filters on UI.

**Pros**
- Leaves option to keep **Subscriptions**  and **Notification Filters** models independent, today we have single field as example: `notify: true`

**Cons**
- We may endup with 2 match engines that look 90% identical and if we would want to make changes to match engine, efforts would need to be x2


### Proposed path forward 
Suggestion here is to go forward with **Option 2** and if we decide to unify 2 match engines we can follow up with this change. 

### Limiting scope for Default rules

As of today GitHub user, right after account was created has certain set of **Notification Settings** enabled/disabled for different `reasons` and `subject_types`. 

We want to support similar capability in `Notifyd` and as possible solution we can think of creating **Match Entries** that as assosiated with **Integrator** rather than user. 

Essentially  **Default Rules** means:
> Even **User** hasn't defined explicit **Match Entries** defined for **Notification Filters** we still want to know to which channels **User** should receive/not receive notifications based on match rules

Straight forward solution is based on adding extra fields on **Match Entries**.
However the scope of changes in this proposal grows and for the first iteration we already know that we will be working with CI activities only. 

That's why for handling **Default rules** I suggest we would not implement this part of model on DB layer but rather will hardcode it to some kind of config as the first step and will create separate proposal for DB based solution.

### Limiting scope for Notification Channels

We had similar thoughts about **Channels**, after thinking about **Channels** entity it feels like it should be separate well thought entity separate from **Match Entries**. 
Thinking about it in detail deserves separate proposal. From practical standpoint we already know that CI activities epic is 100% focused around emails and we are dealing right now with single channel only. 

That's why we suggest to not focus on **Channels** as part of this proposal and go with this assumption:
> If there is a subscription and positive notification filter we assume that the only relevent channel as of today is email. 

### High level API 

On the high level we want to filter out recipients that we got from subscriptions system and then apply filtering step with pre-defined hardcoded rules.

```
notification = {
    subject_type: 'ci_activities_related',
    ...
}
recipients = findRecipients(notification) # Exists today, simplified

recipients_with_channels = []
for each recipient in recipients do 
   rules = findFilterRules(recipient, notification)

   if there is any matching rule that has `notify=false`
        # do not send the notification to any channel for this recipient, move to next one
        next
    elsif there are matching rules with `notify=true`
       recipients_with_channels.push({
           recipient: recipient,
           channels: ["EMAIL"]
       })
    elsif there are not rules apply default rules
       if notification.subject_type == 'ci_activities_related'
            recipients_with_channels.push({
                recipient: recipient,
                channels: ["EMAIL"]
            })
       end
    end

end


for each item in recipients_with_channels do 
    for channel in item.channels do
        if channel == "EMAIL"
          publish_email(recipient)
        end
    end
end
```

### Open questions

- Naming is open question, we need to make sure it's clear
- Tables need to be renamed, data migrated (from one small MySQL table to another)
