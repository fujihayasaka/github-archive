# [Proposal] Filtering and routing notifications in Notifyd

## Brief

A previous [brief](https://github.com/github/notifyd/blob/main/docs/briefs/notifyd-notification-settings.md) described the need for a generic filtering and routing component on top of the subscription system that allows users to define their preferences, so notifyd can properly decide if and through which channels (push, email, ...) a potential recipient should be notified.

<img width="1208" alt="image" src="https://user-images.githubusercontent.com/423347/161574057-e39faf37-2c92-4bff-aa8f-7c59130233f8.png">

Given a `Notify` hydro message and a set of potential recipients, the component should be responsible for answering the following questions:

- Who of the potential recipients are allowed to receive the notification? (E.g. [authentication](https://github.com/github/notifyd/blob/76b6a3d5938d9fcfc280d9dec1e1441e570934d2/internal/notify/handler.go#L121) or [spam checks](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L122-L127), ...)
- Who of the potential recipients actually want to receive a notification for the event (E.g. [blocking users](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L154-L158), [ignoring repositories](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L167-L178), disabling ci-activity alerts, ...)
- Where want the recipients get the notification delivered to (mobile, email, ...)?

## Overview

This document proposes a solution for filtering and routing notifications. Given the scope of this area, this document is meant to discuss the high-level idea and concepts. This proposal doesn't provide in depth technical solutions. Some parts of the idea are presented as black-box components or abstract data types that need to be discussed in more detail in separate proposals. 

There is a [summarizing TLDR](#summary) at the end of the document in case you don't have enough time to read through the whole proposal. ;)

## Context

### The new generic subscription system

We are currently [implementing a subscription system](https://github.com/github/planning-tracking/issues/847) that will allow users to  [subscribe to events by defining conditions](https://github.com/github/notifyd/blob/main/docs/proposals/generic-subscriptions.md#integration-interface-and-examples). These conditions can be defined on the contextual data that integrators can attach to their `Notify` message. Part of the new subscription system will be an engine that can match existing subscriptions with the contextual data of an incoming [`Notify`](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/notify.proto) message (see [github/github/notifyd#954](https://github.com/github/notifyd/issues/954)):

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

## Proposed Solution

Once Notifyd has calculated all potential recipients (explicit recipients & subscribers), it needs to decide who of these potential recipients should actually receive a notification and through which channels (email, mobile push, ...). Similar to subscriptions, users should be able to define filter and routing rules based on the contextual data that integrators can attach to the `Notify` message.

### Semantic model of filter and routing rules

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

### Matching filter and routing rules with `Notify` message

Similar to subscriptions, Notifyd needs to find applicable filter and routing rules for a given `Notify` message by matching the contextual data of the message with contextual conditions of existing rules. In contrast to the subscription use case, we also have a set of potential recipients with reasons to find matching filter and routing rules. Here is how we could compare the high-level match functions for subscriptions and filer/routing rules in pseudo code:

```go
func findSubscriptions(contextualData) []Subscription

func findFilterAndRoutingRules(contextualData, potentialRecipientsWithReasons) []Rules
```

The core functionality of both functions is some kind of a match engine that can match given contextual data of a `Notify` message with a set of contextual conditions. As both use-cases operate on the same contextual data, we propose to implement a match engine that we can use for matching subscriptions and matching filter and routing rules:

<img width="1377" alt="image" src="https://user-images.githubusercontent.com/423347/162414515-7bedff61-b2a7-4807-93d6-e0cbe48e8a69.png">

### Algorithm to apply matched filter and routing rules

Once the match engine has identified all matching rules for each potential recipient, the "filter and routing" system needs to decide which notification should be delivered for each recipient. Given that users can define multiple rules that can match the same event, we need to define priorities. Let's have a look at the following example use-case:

- As a user, I want to receive a mobile push notification whenever someone mentions me anywhere on GitHub.com.
- As a user, I don't want to receive any notifications to any channel for events related to the `github/github` repository.

If that user gets mentioned somewhere in `github/github`, the first rule matches and suggests to deliver a mobile push notification to the user. However, the second rule also matches the event and suggests to skip delivering any notification to the user. We can solve this problem by defining a priority: "negative" rules always override "positive" rules. So in the example above, we'd not deliver any notifications because ignoring the `github/github` repository is considered of higher priority than receiving mobile pushes for mentions anywhere on GitHub.com

We also need to think about multiple matching rules that define different channels. Let's have a look at this use-case:

- As a user, I want to receive a mobile push notification whenever someone mentions me anywhere on GitHub.com.
- As a user, I want to receive email notifications for all events related to the `github/github` repository.

If that user gets mentioned somewhere in `github/github`, the first rule matches and suggests to deliver a mobile push notification to the user. The second rule also matches the event and suggests to send an email notification. To make sure we deliver the notification to all desired channels, the system needs to deliver the notification to the union of the channels of all matching rules.

Putting this together we can derive the following algorithm (pseudo code):

```ruby
for each potential recipient
    skipped_channels = []
    if there is no matching rule
        # do not send the notification to any channel and process the next potential recipient
        next
    elsif there is any matching rule that has `notify=false` and `channels=[]`
        # do not send the notification to any channel and process the next potential recipient
        next
    elsif there are matching rules with `notify=false`
        # do not send the notification to the union of the channels defined by these records
        for each matching_rule_with_notify_false do |rule|
            skipped_channels.add(rule.channels)
        end
    end

    if there are matching rules with `notify=true` and at least one of them sets `channels=[]`
        channels_to_send = ALL_CHANNELS - skipped_channels
        # send the notification to all channels expect for the skipped channels
    elsif there are matching rules with `notify=true`
        channels = []
        for each matching_rule_with_notify_true do |rule|
            channels.add(rule.channels)
        end

        channels_to_send = channels - skipped_channels
        # send the notification to the union of the channels defined by these records
    end
end
```

#### Defining default rules

The algorithm proposed above has one disadvantage:

```ruby
if there is no matching rule
        # do not send the notification to any channel and process the next potential recipient
        next
```

If there isn't any matching rule, we won't deliver any notifications. This makes a lot of sense for opt-in notifications. However, we also support a bunch of opt-out notifications in Newsies today. For example by default we deliver notifications to mentioned users anywhere on GitHub.com. If they don't want to receive these notifications, they need to disable notifications for "mentions and participating" on their [notifications settings page](https://github.com/settings/notifications) or need to "ignore" the affected repositories. Similarly we want to send security alert notifications to all admins of a repository as soon as a security vulnerability has been detected. If users don't want to receive these notifications, they need to disable these alerts on their [notifications settings page](https://github.com/settings/notifications).

So given the algorithm above, how can we make sure that users receive certain notifications without manually defining a filter and routing rule? We could either

- a) auto create rules for users reflecting the default behavior
- b) extend the algorithm and support some sort of default rules that apply to all users

a) seems problematic in certain ways:

**Storage size**: As soon as we implement a new feature that wants to send notifications by default, we'd have to auto create several million of records. We faced this issue when we introduced security alerts (see [github/github#164044](https://github.com/github/github/pull/164044)):

> If we want to use "thread type subscriptions" to support user opt-out. We need to insert the records for all the users that could possibly receive these notifications. As you can imagine, this could be a lot of records, quote from @kevinsawicki:
> 
> Rough estimate of new `notification_thread_type_subscriptions` rows to backfill: ~500 million - 1 billion
> 
> This is equal to roughly the same size as our biggest table on `mysql2` - [github/notifications#929 (comment)](https://github.com/github/notifications/issues/929#issuecomment-733016273).

The more data we store the slower queries become and the more we need to invest into sharding and additional hardware.

**Managing default rules**: Once a default rule has been created for a user, how can we differentiate whether it's a rule that they added manually or was added by the system? If an integrator wants to change the default behavior, how would we know which rules to update or remove? And even if we would be able to distinguish between manual and default rules: how would we efficiently update several billion of records without major effort?

Option b) seems to solve the problem more efficiently if a single "default" filter and routing rule can be defined globally that will be applied to all users. 

Discussing the concrete model and the implementation of default rules has been considered out of scope and should be handled in a separate proposal in more detail. For now, we'll continue with a basic model for default rules that will allow to define the default behavior of the examples above in the following way:

```
{
    contextual_conditions: [
        reason == "mentioned"
    ],
    channels: ["email", "mobile"],
    notify: true
},
{
    contextual_conditions: [
        subject_type == "VulnerabilityAlert",
        trigger == "detected",
    ],
    channels: ["email"],
    notify: true
}
```

Users would be able to override these default rules. For example, if I don't want to receive the default mobile push notifications for mentions I could define the following rule:

```
{
    user: 123,
    contextual_conditions: [
        reason == "mentioned"
    ],
    channels: ["mobile"],
    notify: false
}
```

We'd have to adapt the algorithm to account for default rules:

```ruby
default_channels = []
for each matching default rule do |rule|
    default_channels.add(rule.channels)
end

for each potential recipient
    skipped_channels = []
    if there is any matching rule that has `notify=false` and `channels=[]`
        # do not send the notification to any channel and process the next potential recipient
        next
    elsif there are matching rules with `notify=false`
        # do not send the notification to the union of the channels defined by these records
        for each matching_rule_with_notify_false do |rule|
            skipped_channels.add(rule.channels)
        end
    end

    if there are matching rules with `notify=true` and at least one of them sets `channels=[]`
        channels_to_send = ALL_CHANNELS - skipped_channels
        # send the notification to all channels expect for the skipped channels and process the next potential recipient
        next
    end

    channels = default_channels
    for each matching_rule_with_notify_true do |rule|
        channels.add(rule.channels)
    end
    channels_to_send = channels - skipped_channels
    # send the notification to the desired channels and process the next potential recipient
end
```

## Summary

This document proposes a match engine that can be used by the subscription system and the filter and routing system to match subscriptions and filter/routing rules with the contextual data of a `Notify` hydro message. Detailed specifications for that match engine have been considered out of scope and should be discussed in a separate proposal.

The document further proposes an abstract model of a filter and routing rule with the following attributes:

- `user`: The user to which the rule should be applied.
- `contextual_conditions`: Conditions that need to match with the contextual data of the `Notify` message to apply the rule.
- `channels`: Set of channels that will be affected by the rule. If empty, the rule applies to all channels.
- `notify`: Flag indicating whether the user wants to receive a notification for the matching `Notify` message or not.

The proposal also introduces some sort of default rules that will be applied if no matching user-owned rules can be found.

The filter and routing system is supposed to apply matching rules using the following algorithm (pseudo code):

```ruby
default_channels = []
for each matching default rule do |rule|
    default_channels.add(rule.channels)
end

for each potential recipient
    skipped_channels = []
    if there is any matching rule that has `notify=false` and `channels=[]`
        # do not send the notification to any channel and process the next potential recipient
        next
    elsif there are matching rules with `notify=false`
        # do not send the notification to the union of the channels defined by these records
        for each matching_rule_with_notify_false do |rule|
            skipped_channels.add(rule.channels)
        end
    end

    if there are matching rules with `notify=true` and at least one of them sets `channels=[]`
        channels_to_send = ALL_CHANNELS - skipped_channels
        # send the notification to all channels expect for the skipped channels and process the next potential recipient
        next
    end

    channels = default_channels
    for each matching_rule_with_notify_true do |rule|
        channels.add(rule.channels)
    end
    channels_to_send = channels - skipped_channels
    # send the notification to the desired channels and process the next potential recipient
end
```

## Open questions and next steps

### Naming

I purposely used terms like "filtering and routing rules" instead of "notification settings" in this document to force myself to think outside the "Newsies box". After agreeing on the concepts proposed in this document we might be able to find better terms? Maybe "settings", "channel settings", or "routing settings" fit even better than "rules"?

### Match Engine

The match engine has been treated as a black box in this proposal to keep it scoped. As outlined in @almaleksia's [comment](https://github.com/github/notifyd/pull/985#discussion_r844950792), this might affect how we model contextual data in the `Notify` message and how model and evaluate conditions for subscriptions. We probably need a separate proposal that is focused on the match engine and its consumers:

- How do we model and store `contextual_conditions` for subscriptions and filter/routing rules?
- What's the interface of the match engine?
- How does the subscription system interact with the match engine?
- How does the filter and routing system interact with the match engine?
- How does the match engine match contextual data with subscriptions or filter and routing rules (e.g. do we use a relational DB, a custom DSL, JSON and regexes, ...?)

### Reasons

While working on this document, we started a [discussion about "reasons"](https://github.com/github/notifyd/pull/985#discussion_r844998789) in the context of subscriptions and explicit recipients that raised some core questions about what reasons mean, what they are used for and how they should be modeled in the notifyd domain. We might want to start a separate discussion/proposal to better understand the concept of "reasons" and answer questions like:

- What's the semantic of "reasons" across the notifyd pipeline?
- Do we need a central place where all reason can be registered? Where should that be?
- How do we model a "reason"? Is a simple string like `mentioned` or `assigned` enough or do we need to store more contextual data? E.g. do we need to store information about the team for the `team_mentioned` reason to allow users to define a rule like "I don't want to receive any notifications when the @github/engineering team was mentioned"?
- How do "reasons" and subscriptions work together? Should we have a `subscribed` reason? If so, should the `subscribed` reason have additional contextual data describing why the subscription exists?

### Default rules

This proposal identified the need for default rules. For example we'd like to notify users when they were mentioned or we'd like to notify all admins of a repository if a security vulnerability was detected by default.

- What information should be contained in a default rule? How do we model a default rule?
- Where do we store default rules? Hardcoded in code? In a DB table? If the later: how do we populate that table (also in GHES)?
- Who owns default rules? Who can change them? Should admins be able to change them via stafftools? Or the GHES admin console? Do we need to audit changes to the default rules?
- Do we need multiple levels of default rules? Should GHES instances have the same default rules like github.com? Should organization admins be able to define default rules for the members of their org?

### Channel specific filtering

The filter and routing system proposed in this document is meant to evaluate "global" filters that can be applied to all channels. It is not meant to apply filters that are only relevant for specific channels. For example the [SAML](https://github.com/github/github/blob/e94c78b4241880a4c884af666ef884aed36d7c99/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L71-L75) or [schedule check](https://github.com/github/github/blob/e94c78b4241880a4c884af666ef884aed36d7c99/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L69) is only applied for notifications going through the mobile push channel. We also [skip email notifications](https://github.com/github/github/blob/e94c78b4241880a4c884af666ef884aed36d7c99/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L40) if there is no email address available for the recipient. These channel specific filters should probably be owned by the channels and won't be handled by the filter and routing system.

### Migrating existing checks to the new filter and routing system

Some of the existing checks in the Notifyd Twirp API like the [ignoring repository check](https://github.com/github/github/blob/a0671ef43635e022b3b57ca9baf96549e81ad80b/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L167-L178) or the [evaluation of the mobile push notification settings](https://github.com/github/github/blob/e94c78b4241880a4c884af666ef884aed36d7c99/app/api/internal/twirp/notifications/notifyd/v1/notifyd_api_handler.rb#L245-L261) can probably be migrated from the Twirp API into the new filter and routing system:

#### Ignoring a repository:

> As a user, I don't want to receive any notifications for the `github/github` repository.

```
{
    user: 123,
    contextual_conditions: [
        related_topics contains "Repository": 567,
    ],
    channels: [],
    notify: false
}
```

#### Mobile push notification settings:

![IMG_353350C10779-1](https://user-images.githubusercontent.com/423347/162916578-7611f1e2-9fdc-453d-8c0b-3bcc82cc9b89.jpeg)

> As a user, I want to receive mobile push notifications for mentions.

```
{
    user: 123,
    contextual_conditions: [
        reason == "mentioned"
    ],
    channels: ["mobile"],
    notify: true
}
```

> As a user, I want to receive mobile push notifications when someone requested my review.

```
{
    user: 123,
    contextual_conditions: [
        reason == "review_requested"
    ],
    channels: ["mobile"],
    notify: true
}
```

> As a user, I want to receive mobile push notifications when someone assigned myself to an item.

```
{
    user: 123,
    contextual_conditions: [
        reason == "assigned"
    ],
    channels: ["mobile"],
    notify: true
}
```

We might want to discuss potential migration strategies in more details in a separate discussion/proposal. 
