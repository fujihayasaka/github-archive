# Generic subscriptions

## Overview

We currently support single subscription scenario which is a label subscription. The implementation was mostly driven by MVP requirements and though we made our implementation as generic as possible there are adjustments needed to support generic subscriptions.

## Design considerations

### 1. Flexibility and extensibility of subscription matching rules

This means that subscription system shall provide the possibility to define custom set of rules to filter the messages user wants to be notified about.


For example, we want to get notified when
 - issue is labeled with label "bug" in a particular repo
 - issue with label "bug" is commented
 - issues created by a certain user in a particular repo
 - particular issue is commented
 - a review is requested for a team I belong to
 - a CI check fails on a PR that I created
 - a comment is created on one of my commits


### 2. Clear interface for integrators

It's clear for integrators how to create a subscription and what data to add to notification message for it to match certain subscriptions.

There should be clear rules for integrator on how to define a subscription. We shall minimize the possibility to create a broken subscription.

### 3. Various UI scenarios support

- Display repo-related subscription in a watch dropdown

![image](https://user-images.githubusercontent.com/1885174/154848039-9d1130e9-b36b-4182-8268-8e678774c257.png)
- Display a list of repo-related subscriptions

- Display user's subscriptions grouped by reasons

![image](https://user-images.githubusercontent.com/1885174/154861986-d7c710dd-516d-4dcc-beac-6c166ecca989.png)

- Disable user's subscriptions with the particular reason
- Display user's custom subscriptions grouped by entity subscription belongs to

![image](https://user-images.githubusercontent.com/1885174/154862162-68f07861-74ca-4c3d-b5c2-0c1800c1ee2b.png)

- Display and edit user's custom subscription that is scoped to several repos

![image](https://user-images.githubusercontent.com/1885174/154862015-e758175a-a02d-424c-94f5-88eeefe4726e.png)

- Disable user's custom subscription
- Add/remove notification channels per subscription


### 4. Performant retrieval of the recipients for the incoming notification message

When notification comes to Notifyd we should be able to match notification data with stored subscriptions to identify list of recipients we need to notify. We also need to do it with minimal possible time and memory complexity.


### Drawbacks of current implementation

MVP implementation is focused on single use case - label subscriptions. Our database schema and logic that we use in API and notify-consumer are pretty generic but there are some problems.

Let's take a look at our current data model for subscriptions.

![image](https://user-images.githubusercontent.com/1885174/154806776-1528df17-33c6-4ef0-bd04-f95cc10a705d.png)


We can see that only one topic per subscription is allowed and there's one to many relationship between subscription and its attributes that we initially wanted to use for filtering.

**Note**: Topic is represented by two fields - `topic_type` and `topic_value`. In case of monolith integration `topic_type` is entity and `topic_value` is identifier of the entity. We currently store 'label' in `topic_type` and label id in `topic_value`.


There are several problems with this data model and current implementation based on it.

#### 1. Missing data

We currently do not store
- **channels**
User shall be able to customize default channel settings per subscription.

- **triggers**
User shall be able to configure triggering events in the subscription. Currently we do not store triggers in a subscription.

- **reasons**
We need reasons for UI scenarios like grouping by reason on settings page and managing subscriptions by reasons. Apart from that reasons will be migrated from Newsies and shown to users in the email template.

- **enabled/disabled flag**
According to design mockups user should be able to disable notifications for certain subscription or subscription group. For that we need to store an indicator whether subscription is currently active.


- **optional name for custom subscriptions**
User should be able to assign a name to custom subscription, according to some mockups.


#### 2. No attribute matching

Currently we have attributes that are used only to filter subscriptions for the UI. We do not perform any attribute matching in the consumer, we match only topics.

#### 3. No clear definition of "topic"

We currently store one topic per subscription and there's no clear definition what topic means. We put label id as a topic and create one subscription per label. In order to migrate data from Newsies and scale subscriptions we need to understand what is the relation between topic and subscription.


#### 4. No trigger matching

We do not take into account activity that triggered notification and support only one event. In the future subscriptions platform should enable client to flexibly configure what events they want to be notified of.

## Proposed solution

###  Domain modelling

#### What is a subscription?

Before moving to data schema definition for subscription we need to explore what does "subscription" mean and what entities we need to represent it. Subscription can be represented as user defined set of rules to match activity in order to produce notifications for that user.

Generally subscription can be described by the statement:

When `<something happens>` notify me via `<channels>` if `<conditions>` are satisfied.


The goal is to correctly model these three variables.

1. **Something happens** is a trigger or event that we want to subscribe to. We can provide the possibility to subscribe to several triggers.
2. In **channels** we can configure one or several delivery channels for notification. Known channels so far are email, push and web.
3. **Conditions** is the most non-trivial part to implement.
Here we need to consider several requirements:
 - flexibility of configuration
 - clarity for integrators
 - performance on the retrieval stage
 - scalability on the storage level

Let's start with **flexibility**. It is useful to take a look at existing design mockups to get an idea of the requirements. We see the following possibilities on various design mockups we have available by now:
- configure several triggers per subscription

![image](https://user-images.githubusercontent.com/1885174/154848141-66181346-e4f2-40e7-9d6c-704ba9665427.png)

- configure conditions per trigger

![image](https://user-images.githubusercontent.com/1885174/154848229-353c2213-918c-4518-87b2-e831fe1fd50b.png)
- match list-like conditions (receive only notifications when issues with both labels "bug" and "triaged" are commented)
- configure pattern matching rules
- configure subscription scoped to several repos (as opposed to one-repo scoped subscriptions we have so far)


As for **clarity for integrators**, here we need to consider two parts:
- interface to create a subscription
- data to specify in the notification message itself

Taking into account first two requirements we still need to model our conditions to keep best possible **performance on retrieval stage**.
When notification comes we will have to retrieve recipients to notify. The number of subscriptions to operate on can be very high and we need to filter effectively using the data that came inside the message.


#### What is a topic?

If you look at message delivery systems like Kafka the topic is just a way to categorize and organize messages. As Notifyd is supposed to be a generic notification delivery system we do not tie topics to the dotcom domain objects. Topic can be anything, for example "abcd".

Subscription that is created with "abcd" topic will match all the messages with "abcd" topic.
However we decided to split topic to two parts: type and value. This is to adjust to dotcom requirements and simplify indexing and filtering by topics. In order to match dotcom subscriptions more effectively we can use dotcom entities as a topic: in this case type will be the entity object type like repository, user, organization etc. and value is an identifier of the object. By subscribing to a topic we subscribe to the events related to a particular entity. For example "issue commented" event might be related to different entities: repository, organization, milestone, label etc.

If it is decided, for example, to use repository as a subscription topic, it means we are subscribing to the events in this repository. So basically topic is a way to group incoming messages and it can be done really flexibly. Theoretically we can use literally anything as a topic.

#### What is a trigger?

It is intuitive what trigger is: identificator of the event in the system like "issue created". If we look at dotcom triggers https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows we can see that they can be also combined from two parts: entity + actual event on this entity. For example event "pull request reviewed" has two parts in it: pull request (entity) and "reviewed" (actual event). We could model trigger as one identifier (pull_request_reviewed) but having a dedicated field for entity will help to satisfy some dotcom specific requirements and simplify subscriptions filtering. We already have "subject" and "trigger" concepts in the Notifyd so we can use both to represent triggering event.

Trigger may also have data associated with them and specific for the particular trigger only.
For example, for "issue labeled" event we have added `label` as an attribute which is missing on the event `issue commented`. For the `issue unlabeled` event we have deleted label as an attribute. At the same time all the issue related events may have attributes like `issue title` and `labels` (labels that are already assigned to the issue).

#### What is a subscription attribute?

Currently we use subscription attribute to filter subscriptions in the UI. Notifyd does not know anything about dotcom data models and hierarchy therefore to enable scenarios like "show me all subscriptions for this repository" the integrator shall specify custom attributes that later can be used for subscriptions retrieval.

#### Data model

The flaws of current implementation already were mentioned in this document, let's see how we can change it to match the domain and satisfy the requirements.

In order to satisfy scalability requirements we need to design storage to enable sharding.

**Why do we need sharding now?**

Moving unshared schemas to shared ones is long and complicated process because sharding imposes certain requirements on database. If we design our schema without considering sharding in the first place we may end up re-making the whole schema and as a result rewriting our business logic as well.
We plan to migrate Newsies to Notifyd soon, which means the amount of data will not grow gradually and it won't take months or years to reach our limits. Therefore accounting for data distribution in advance will spare us difficulties in the nearest future.


More details on benefits of horizontal sharding you can find in [Vitess EDR](https://docs.google.com/document/d/1zb2-PMlWS5A4jgfW0_rSjY16VUQ95ilKHBH0S4oTqEg/edit#).

**Sharding key**

Sharding means data distribution across mysql instances. We currently use vitess as mysql middleware that supports sharding out of the box. But we need to decide on the key that will be used to distribute our data accross shards.

The main concern here is the nature of the load on database. We need to make sure that we minimize the amount of cross shard queries. In case of subscriptions the most frequent queries to data storage will be queries that pre-select subscriptions that match notification message.

The second type of queries would be queries that select subscriptions to display them in the UI, almost all of them are scoped to a single user. Examples: subscriptions in repo watch dropdown, subscriptions on user settings page.

As matching queries are more frequent we need to make sure that they hit only one shard. For that we need to pick the attribute we're going to use as sharding key.

The proposal is to use `owner_id` or `repository_id` as sharding attributes.

**Algorithm to pick sharding key in case of dotcom integration**

1. Pick `repository_id` as sharding key if message comes to consumer and it has `repository_id` attribute. It means that we will use `repository_id` as a condition in match queries to pre-filter subscriptions.
2. Pick `owner_id` as sharding key if message comes to consumer and it does not have `repository_id` attribute. For example Memex projects belong to organization and not to repo, therefore we will not get `repository_id` in notification message. owner_id shall be required attribute to pass for monolith.

**UI queries**

However according to the UI mockups we shall be able to configure subscription for multiple repositories (and maybe orgs in the future). To accomodate for that and also for the possibility to add multiple triggers per subscription we
introduce "meta" subscriptions: entity that will allow us to edit complex conditions for subscription matching (multiple repositories and multiple triggers) on one single page. Meta subscriptions shall be located in a separate vitess keyspace as they may include subscriptions that belong to different repos therefore to different shards.
Meta subscriptions keyspace can be sharded by `user_id` column.

Data storage schema for subscriptions will look the following:

![image](https://user-images.githubusercontent.com/1885174/164458812-37d21918-aa67-4c7b-9e95-cb52d086fecc.png)



`topic_type` and `topic_value` remain in the table and new columns `subject` and `trigger` are added to enable filtering subscriptions by trigger.

`meta_id` column will link subscriptions to the meta subscription in a separate keyspace.

Additional fields `reason` is  added to store the subscription reason.


Table `subscription_match_rules` is added to enable filtering subscriptions by attributes. This table stores the rule to match certain attribute of the notification message with `match` column to indicate how the attribute should be matched when filtering out subscriptions. This table is supposed to be used by consumer to select the subscriptions based on the data in the notification message.

Possible match types:

1. equality - simply check if attribute equals the value in the notification message.
2. contains - check that value from notification matches the regexp that is stored in attributes (example: notify only on issues with the titles that match certain pattern)
3. list - if certain subscription has several attributes of the same name to match with the notification.
...
(further matching types possible)


Table `subscription_channels` is added which relates to `subscriptions` table via `meta_id` column. Although channels relate to `meta_subscriptions` we need to store them in the first keyspace because we need channels in the consumer to determine where to send notifications and we want to avoid queying second keyspace in the consumer.


#### Matching subscriptions by topics and attributes in the consumer

In the consumer we need to get the list of recipients to notify about the event. For that we need to perform subscriptions matching against the data in the incoming message.

The diagram below demonstrates the matching logic for certain scenarios.

![image](https://user-images.githubusercontent.com/1885174/154862454-f73d2776-5f73-4af8-8378-43eae471aaff.png)


When message comes in we do two steps to match the subscriptions:

1. Pre-filtering in database based on the related_topics and attributes specified in the message. The goal of pre-filtering is to narrow down the list of subscriptions as much as possible on database level.

**Pre-filtering algorithm (spike PR required)**

**A.** Select subscriptions that contain at least one of the related_topics and have no triggers specified (which means they match all triggers).

**B.** Select subscriptions that contain at least one of the related_topics with the trigger that matches one specified in the message but no attributes filter.


**Sample SQL query for A. and B. pre-filtering steps**

```sql
SELECT DISTINCT user_id, reason, topic_type, topic_value FROM subscriptions
        LEFT JOIN subscription_match_rules ON subscriptions.id = subscription_match_rules.subscription_id
            WHERE subscriptions.topic_type = 'repository' AND subscriptions.topic_value = '123' AND
            (
                subscriptions.subject is NULL OR
                (subscriptions.subject = 'issue' AND subscriptions.trigger = 'labeled' AND subscription_match_rules.subscription_id is NULL)
            )
```


**C.** Select  subscriptions that contain at least one of the related_topics, match the trigger specified in the message, equals to at least on of the attributes specified in the message or have a complex match type (contains, regexp). In case attribute has complex match type we cannot apply it using SQL so it will be checked on the application level during final matching.

**Sample SQL query for C. pre-filtering step**


```sql
SELECT subscriptions.id, subscriptions.user_id, subscription_match_rules.attribute, subscription_match_rules.value, subscription_match_rules.match_rule FROM subscriptions
        INNER JOIN subscription_match_rules ON subscriptions.id = subscription_match_rules.subscription_id
            WHERE subscriptions.topic_type = 'repository' AND subscriptions.topic_value = '123' AND
            (
                subscriptions.subject = 'issue' AND subscriptions.trigger = 'labeled'  AND
                (
                    (attribute = 'author_id' AND (subscription_match_rules.value = '456' OR      match_rule != 'eq')) OR
                    (attribute = 'added_label' AND (subscription_match_rules.value = '111' OR match_rule != 'eq'))
                )
            )
```

2. Final matching of the attributes in memory.

On this stage we will perform final matching of the attributes for the subscriptions retrieved on step C of pre-filtering. The logic of attribute matching is the following:
- if the attribute is absent on the message but the rule for the attribute is present in the subscription filter - attribute not matched
- if the attribute is absent in the subscription filter and present on the message - attribute is matched
- if the attribute is present on both message and the filter, apply the filter rule to the attribute to see if it matches

For subscription to be selected all the attributes must be matched.

_Example 1:_

Message attributes:

```
author_id: 1
added_label: 2
has_label: 3
```

Subscription filter:

```
author_id: 1
```

This subscription will be matched because the only attribute specified in the filter `author_id` matches one in the message and we do not care about `added_label` and `has_label` attributes (there are no filter rules for them therefore we accept any values for these attributes).

_Example 2:_

Message attributes:

```
author_id: 1
added_label: 2
```

Subscription filter:

```
author_id: 1
has_label: 3
```

This subscription will not be matched because message does not contain `has_label` attribute that would pass the rule specified by the filter.


_Example 3:_

Message attributes:

```
author_id: 1
has_label: 2
```

Subscription filter:

```
author_id: 1
has_label: 3
```

This subscription will not be matched because message attribute `has_label` attribute does not pass the rule specified by the filter.


3. Create a list of recipients.

On this stage we take the list of subscriptions from step A. and B. of pre-filtering without changes and subscriptions from step C. after attribute filter matching was applied and create a list of users to be notified about the event.


**Pre-filtering metrics**

We might want to add metrics that would show the following:

- How many subscriptions get pre-filtered on A. and B. stages?
- On how many subscriptions we perform attribute matching?
- How does the usage of memory grow with the number of subscriptions?
- How many subscriptions get filtered by event?

These metrics will be needed to take informed decisions on how to proceed with notifications that should be delivered to large amount of recipients.

#### Integration interface and examples


**Example 1**
Create a custom subscription to be notified of the following events:
- the issue created events if labels "bug" and "triaged" are assigned to the issue and issue title contains word "subscription"
- the issue labeled events if the issue has a "bug" label, issue title contains word "subscription", and it is labeled with "triage" label


Creating a subscription:

```ruby
subscriptions = Notifyd::Proto::SubscriptionsClient.new(@connection)
result = subscriptions.create(
        Notifyd::Proto::Subscriptions::CreateRequest.new(
            user_id: 1,
            reason: "subscribed",
            channels: ["email"],
            filters: [
                {
                    subject: "issue",
                    trigger: "created",
                    match_rules: [
                        { attribute: "has_label", value: ["1","2"], match: "list" },
                        { attribute: "title", value: "subscription", match: "contains" },
                    ]
                },
                {
                    subject: "issue",
                    trigger: "labeled",
                    match_rules: [
                        { attribute: "has_label", value: ["1","2"], match: "list" },
                        { attribute: "title", value: "subscription", match: "contains" },
                        { attribute: "added_label", value: "4", match: "eq" }
                    ]
                },
            ],
            attributes: {
                "repository_id": "123"
            },
            topics: [
                { type: "label", value: "1" },
                { type: "label", value: "2" },
                { type: "label", value: "3" },
            ]
    })
```


Message examples:

```ruby
...
related_topics: [
    { type: "repository", value: "123"},
    { type: "label", value: "1" },
    { type: "label", value: "2" },
],
subject: "issue",
trigger: "created",
context: {
    has_label: ["1","2"],
    title: "Bug in the subscriptions"
}
```

```ruby
...
related_topics: [
    { type: "repository", value: "123"},
    { type: "label", value: "1" },
    { type: "label", value: "2" },
],
subject: "issue",
trigger: "labeled",
context: {
    subscription_attributes: [
       { name: "has_label", value: "1" },
       { name: "added_label", value: "2" },
       { name: "title", value: "Bug in the description" }
    ]
}
```

**Example 2**

Create a custom subscription to be notified when issue assigned to a certain user is commented and has a "bug" label.

```ruby
subscriptions = Notifyd::Proto::SubscriptionsClient.new(@connection)
result = subscriptions.create(
        Notifyd::Proto::Subscriptions::CreateRequest.new(
            user_id: 1,
            reason: "subscribed",
            channels: ["email"],
            filters: [{
                subject: "issue",
                trigger: "commented",
                match_rules: [
                   { attribute: "has_label", "value": "1", "match": "eq" },
                   { attribute: "assignee", "value": "1", "match": "eq" }
                ]
            }],
            attributes: {
                repository_id: "123"
            },
            topics: [
                { type: "label", value: "1" },
                { type: "assignee", value: "1" },
            ])
```

Message example:

```ruby
...
related_topics: [
    { type: "repository", value: "123"},
    { type: "label", value: "1" },
    { type: "assignee", value: "1" },
],
subject: "issue",
trigger: "commented",
match_rules: {
    subscription_attributes: [
       { name: "has_label", value: "1" },
       { name: "assignee", value: "1" },
       { name: "title", value: "Bug in the description" }
    ]
}
```

**Example 3**

Create a custom subscription to be notified about all the events in a certain repo.


```ruby
subscriptions = Notifyd::Proto::SubscriptionsClient.new(@connection)
result = subscriptions.create(
        Notifyd::Proto::Subscriptions::CreateRequest.new(
            user_id: 1,
            reason: "subscribed",
            channels: ["email"],
            attributes: {
                repository_id: "123",
                organization_id: "345"
            },
            topics: [
                { type: "repository", value: "123" },
            ])
```

Message example:

```ruby
...
related_topics: [
    {type: "repository", value: "123"}
],
subject: "pull_request",
trigger: "reviewed",
context: {...}
```


**Example 4**

Automatic subscription to an issue thread (for example, when commenting the issue).


```ruby
subscriptions = Notifyd::Proto::SubscriptionsClient.new(@connection)
result = subscriptions.create(
        Notifyd::Proto::Subscriptions::CreateRequest.new(
            user_id: 1,
            reason: "subscribed",
            channels: ["email"],
            reason: "participating",
            filters: [
               {
                subject: "issue",
                trigger: "any"
               }
            ],
            attributes: {
                repository_id: "123"
            },
            topics: [
                { "type": "issue", "value": "1" },
            ])
```

Message example:

```ruby
...
related_topics: [
    { type: "issue", value: "1" }
],
subject: "issue",
trigger: "commented",
context: {...}
```


### Notification tracking

Currently we separate notifications related to label subs in data warehouse by reason. For the label subscriptions we hardcoded "subscribed" reason but after we scale subscriptions platform to support variety of cases "subscribed" reason will mean "custom subscription" but there's not insight what filters or topics user has subscribed to. In order to have this data in datawarehouse we will have to add additional fields:

**subject** - entity that produced the event user was notified about (for example, issue or pull request)

**trigger** - event that user was notified about, for example "commented", "labeled" etc.

**topics** (array) - topics that were matched by notification

**filter_attributes** (array) - subscription attributes that were matched by notification. For example, "has_label", "added_label" etc.

By having this data we can distinguish notifications for labels by using **topics** and/or **filter_attributes**.

## Drawbacks

We have to make certain trade offs to make our subscription engine flexible enough to serve complex matching scenarios.
In order to support  several triggers and several topics per subscription we need to complicate our database schema which results in additional joins on pre-filtering stage and therefore worse performance. Also to enable attribute matching which we don't currently have we need to perform some in-memory filtering on application level.

We already iterate over recipients and subscriptions in memory, and currently we limit amount of recipients we can process for one notification. We will soon have to remove this limitation and introduce batching.

## Alternatives explored

### One subscription per trigger

![image](https://user-images.githubusercontent.com/1885174/154849150-85c76851-a462-48c7-aa23-eb8ef12d4735.png)

It was explored to represent subscription <-> trigger relation as one to one. In this case we will not be able to assign multiple triggers per subscription which might be required when creating subscription in the UI.

### Store attribute matching rules as json

![image](https://user-images.githubusercontent.com/1885174/154849165-1db060d7-b47a-49cf-9815-bf8edb7ece03.png)

There's a possibility to get rid of subscription_match_rules table by putting matching rules for attributes into json but in this case we cannot perform pre-filtering based on the attributes which might hurt matching performance.

