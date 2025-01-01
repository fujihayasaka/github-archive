# Notifyd subscriptions

## Context

The need for new subscription system to replace current Newsies subscriptions stems from the multiple customer requests to support more granular subscriptions. Customers are overwhelmed with the notifications they are getting which makes them much less useful as many of them are simply ignored. For example, by [watching repository](https://github.com/github/github/issues/98225) user gets a lot of notifications, only small percentage of which are of any interest to them.

Taking this into account we have [three main requirements](https://github.com/github/notifications/issues/864) that new subscriptions system shall satisfy:

- Customers want to receive more notifications about the events they care about, many of which we don't support today.
- Customers want to receive fewer notifications about the events that they don't care about.
- Customers want the ability to personalize their own mix of notifications using granular controls.

### Granular subscriptions scenarios

- As a user, I want to be notified via email when someone creates an issue with the bug label on the repo I'm maintaining.
- As a user, I want to get pinged in Slack when my CI fails
- As a user, I want to get notified via mobile push if someone is requested a review from me
- As a user, I want to get notified via email when someone created a discussion in a particular category

### UI scenarios

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


## Subscriptions subsystem in NotifyD

### Workflow overview

The goal of subscriptions subsystem is to calculate and return a list of potential recipients for a notification message. For that we need to store how a user "wishes" to be notified on certain events and when any event occurs we should be able to determine if said user is subscribed to this event.

In order to subscribe to certain events a user creates a subscription via UI. Then the integrator sends the request to Notifyd's Twirp API and Notifyd saves the subscription to the database. For example, the user wants to be notified when an issue is labeled "bug" in a particular repository.

Then another user labels an issue with "bug". The integrator sends an event message to Notifyd with all the data needed to match subscriptions.

Inside Notifyd, the `notify` worker uses the matching engine to determine the list of potential recipients of this notification.

![image](https://user-images.githubusercontent.com/1885174/172811775-f1df055b-b4e9-4bda-b085-2a6797955dfb.png)


### Matching engine

#### Overview

In order to support the granular subscriptions scenarios mentioned above we shall be able to find subscriptions that match particular events.

To do this we store the data related to the events a user wants to be notified about as a subscription and pass this data in an event message. This way we can match event message data with subscriptions. This is a core functionality of the subscriptions system.

![image](https://user-images.githubusercontent.com/1885174/170010825-aaa36f48-f10b-43be-b9ef-850c3c2ef5f7.png)

The output of the matching engine is the list of potential recipients with the reasons to be notified. It is not a final list of recipients, some of the potential recipients will be filtered out on the next step by the user's routing settings.

#### Subscription related data in the notification message

The data on a message is matched against subscriptions consists of three parts.

1. **Related Topics**

   Topics are a way to group incoming messages under some category and it can be done in a really flexible way. Theoretically we can use anything as a topic. In the case of label subscriptions we use the repository as a topic. Using topics we can specify a scope for the notification. For example, I want to get notified only about the events related to particular repo or I want to be notified about the events related to the issue thread.

2. **Event**

   Event consists of a subject type and a trigger. For example when an issue is created the subject is `Issue` and the trigger is `create`.

   When an issue gets labeled then the subject is `Issue` and the trigger is `labeled`.

3. **Attributes**

   Attributes are arbitrary data that is sent in the message to match it even more granularly with subscriptions.

   For example, to match subscriptions for the event `Issue labeled` but only when an issue is assigned a particular label, we put the label id in the attribute list for the event.

   ![image](https://user-images.githubusercontent.com/1885174/172802634-e77dd684-a415-45e5-ae3e-cd0614069aa9.png)


   Sample fragment of the event message that we send when an issue is labeled:

   ```ruby
   {
       subject: {
           type: "Issue",
           id: 123
       },
       context: {
           trigger: "labeled"
       },
       related_topics: {
           type: "repository",
           value: "456"
       },
       attributes: [
           {name: "added_label", value: "1"}
       ]
   }
   ```

#### Subscriptions data

The data on the message is matched with the subscriptions data stored on the database by the matching engine.

Below is the schema that stores the data on subscriptions.

![image](https://user-images.githubusercontent.com/1885174/171893699-c208de01-7387-4dd4-a1b0-26325784ae7c.png)


Tables `subscriptions_v2` and `subscriptions_match_rules` are used by the matching engine. The matching engine then takes the data from the message and finds the subscriptions that match this data.

#### Matching algorithm

The following table shows what is the relevant data from the message compared to what is the data stored in the database for subscriptions.

| message data           | subscriptions data                 |
| ----                   | ----                               |
| related_topics[].type  | subscriptions_v2.topic_type        |
| related_topics[].value | subscriptions_v2.topic_value       |
| subject.type           | subscriptions_v2.subject           |
| context.trigger        | subscriptions_v2.trigger           |
| attributes[].name      | subscription_match_rules.attribute |
| attributes[].value     | subscription_match_rules.value     |


On the first step the matching engine does a pre-selection of the rows from the subscriptions table based on the message's data.

On the pre-selection phase we fetch subscriptions based on `topics`, `subject_type`, `trigger` and `attributes`. The pre-selection results in a list of matching entries. A matching entry is an entry that combines the data from `subscriptions_v2` table and `subscriptions_match_rules` table.

For example, we have a subscription that indicates we shall notify a user when a label with id 1 is assigned to an issue in a repository with id 123.

The matching entry in case subscription matches the incoming event will look the following:


| column                             | value       |
| ----                               | ----        |
| subscriptions_v2.topic_type        | repository  |
| subscriptions_v2.topic_value       | 123         |
| subscriptions_v2.subject           | Issue       |
| subscriptions_v2.trigger           | labeled     |
| subscription_match_rules.attribute | added_label |
| subscription_match_rules.value     | 1           |


Pre-selection will return a matching entry per every match rule. Those are match rules that need to be evaluated in memory to determine whether the subscription they belong to matches the incoming notification message. Why do we need in-memory filtering step? The answer is we need to apply more sophisticated logic that is non-trivial to achieve with a single SQL query.

#### In-memory filtering logic

For a subscription to be selected all the attributes must be matched.

_Example 1:_

Message attributes:

```ruby
{
    attributes: [
        {name: "added_label", value: "2"},
        {name: "author_id", value: "1"},
        {name: "has_label", value: "3"}
    ]
}
```

Subscription match rules in database:

| attribute | value | match |
| ----      | ----  | ----  |
| author_id | 1     | eq    |

This subscription will be matched because the only attribute specified in the filter `author_id` matches one in the message and we do not care about `added_label` and `has_label` attributes (there are no filter rules for them therefore we accept any values for these attributes).

_Example 2:_

Message attributes:

```ruby
{
    attributes: [
        {name: "added_label", value: "2"},
        {name: "author_id", value: "1"},
    ]
}
```

Subscription match rules in database:


| attribute | value | match |
| ----      | ----  | ----  |
| author_id | 1     | eq    |
| has_label | 3     | eq    |


This subscription will not be matched because the message does not contain the `has_label` attribute that would pass the rule specified by the filter.


_Example 3:_

Message attributes:

```ruby
{
    attributes: [
        {name: "has_label", value: "2"},
        {name: "author_id", value: "1"},
    ]
}
```

Subscription filter:

| attribute | value | match |
| ----      | ----  | ----  |
| author_id | 1     | eq    |
| has_label | 3     | eq    |

This subscription will not be matched because the message attribute `has_label` does not pass the rule specified by the filter (the attribute on the message has a different value than the one saved in the match rule for a subscription).

In order to evaluate whether each attribute matches rules in `subscription_match_rules`, the column `match` is used. Currently we only support the `eq` match type which means that we need to check if the attribute from the message equals the attribute value from the match rule.

After in-memory filtering the match engine returns a list of potential recipients and a list of notification reasons for each said potential recipient.

Only those recipients end up in a final list who have at least one subscription that has been matched with the event message by match engine.

## Managing subscriptions via UI in Monolith

Tables `subscriptions_v2` and `subscriptions_match_rules` contain subscription data used by the match engine. There's another entity we use to manage subscriptions via the Twirp API which is `meta_subscriptions`. `meta_subscriptions` and
`subscriptions_v2` tables have a one to many relationship. Several subscriptions can reference one meta subscription. This is needed so that we can edit multiple subscriptions on one UI page.

For example, user might want to subscribe to someone's comments in several repositories. We save repository as a topic so we have to create several entries (at least one per each topic) in `subscriptions_v2` table (see [example](#example-2-issue-is-commented)). Later we need a way to retrieve this data and display it in the UI as one subscription. That's why we group these entries under one `meta_id` which is the subscription id that is exposed to integrators via Twirp API.

`meta_subscriptions` has a one to many relation with the `subscriptions_custom_fields` table. `subscriptions_custom_fields` contains fields that enable searching and retrieval of meta subscriptions by certain fields. An integrator can specify custom fields they want to search by to enable custom UI scenarios.

### Example 1: Label subscriptions

We have an existing working scenario of label subscriptions.

In this scenario we can edit a list of labels in a repository watch dropdown.

![image](https://user-images.githubusercontent.com/1885174/172593552-940077a1-51cc-44a6-8ea1-93493649e6cf.png)

For the label subscriptions scenario we need to retrieve all label subscriptions for a particular repository and display them in the `Watch` dropdown. For that we need to be able to query by `repository_id`. We use custom_fields to save that `repository_id` along with every label subscription so that later we can easily retrieve them.

For every label subscription we make a request that creates two meta subscriptions: one is responsible for notifications when an issue with a label is commented and the second one is responsible for notifications when a label is assigned/removed:

https://github.com/github/github/blob/56f187f09ca86d8df38ac68e8c08b08055880c78/packages/notifications/app/models/user/notifications_dependency.rb#L138-L197


Let's look at how subscriptions for label with `id=1` in a repository with `id=123` end up in database:

```ruby
    {
      user_id: id,
      reason: "subscribed",
      topics: [{type: "repository", value: "123"}],
      filters: [
        {
          subject_type: "Issue",
          trigger: "labeled",
          match_rules: [
            {attribute: "added_label", value: "1", match_rule: "eq"},
          ]
        },
      ],
    }
```

**meta_subscriptions**

| id  | user_id | name | details |
| --- | ---     | ---  | ---     |
| 1   | 1       | NULL | json    |
| 2   | 1       | NULL | json    |

`details` column contains json with the dump of the data related to that subscription. It is basically the payload that we send to create a subscription, with minor modifications.

It duplicates the info we have in `subscriptions_v2` and `subscription_match_rules` tables.
We introduced this column to account for future sharding. We planned to shard all tables by user_id. One meta subscription can potentially reference subscriptions in multiple shards. In order to avoid querying multiple shards to display subscriptions in the UI this field was introduced.

This duplication of the data has a disadvantage because we need to make sure the data in `meta_subscriptions` is updated along with other tables. That's why it's an open question whether we shall keep the `details` column or we can think of sharding everything per user. In this case we can query the data that we need instead of dumping a copy of it in `details`.

**NOTE** (2023-05): Sharding support has been removed. Without storing auto-subscriptions there's no need for sharding and the need for this table needs to be reevaluated.

**subscriptions_v2**

| id  | user_id | topic_type | topic_value | subject      | trigger   | reason     | meta_id |
| --- | ---     | ---        | ---         | ---          | ---       | ---        | ---     |
| 1   | 1       | repository | 123         | Issue        | created   | subscribed | 1       |
| 2   | 1       | repository | 123         | IssueComment | create    | subscribed | 1       |
| 3   | 1       | repository | 123         | Issue        | labeled   | subscribed | 2       |
| 4   | 1       | repository | 123         | Issue        | unlabeled | subscribed | 2       |

**subscriptions_match_rules**

| id  | subscription_id | name          | value | match |
| --- | ---             | ---           | ---   | ---   |
| 1   | 1               | has_label     | 1     | eq    |
| 2   | 2               | has_label     | 1     | eq    |
| 3   | 3               | added_label   | 1     | eq    |
| 4   | 4               | removed_label | 1     | eq    |

**subscription_custom_fields**
| id  | meta_id | user_id | name          | value |
| --- | ---     | ---     | ---           | ---   |
| 2   | 1       | 1       | repository_id | 123   |
| 3   | 1       | 1       | label_id      | 1     |
| 5   | 2       | 1       | repository_id | 123   |
| 6   | 2       | 1       | label_id      | 1     |


After subscriptions are saved they can be retrieved using custom fields:

```ruby
request = Notifyd::Proto::Subscriptions::GetRequest.new(
  user_id: id,
  filter_by_custom_fields: [
    {name: "repository_id", value: "123"},
    {name: "label_id"}
  ],
)
```

This request retrieves all subscriptions that have the custom field `repository_id` with the value `123` and the `label_id` custom field with any value. In this way we retrieve label subscriptions for a particular repository.

We also have all the necessary data for the match engine to work.

For example, we get an incoming message with the following data:

```ruby
{
    subject: {
        type: "Issue",
        id: 123
    },
    context: {
        trigger: "labeled"
    },
    related_topics: [{
        type: "repository",
        value: "456"
    }],
    attributes: [
        {name: "added_label", value: "1"}
    ]
}
```

Match engine will find the subscription in subscriptions_v2 that matches:

| id  | user_id | topic_type | topic_value | subject | trigger | reason     | meta_id |
| --- | ---     | ---        | ---         | ---     | ---     | ---      | ---     |
| 3   | 1       | repository | 123         | Issue   | labeled | subscribed | 2       |

With this subscription we have one associated match rule:

| id  | subscription_id | name        | value | match |
| --- | ---             | ---         | ---   | ---   |
| 3   | 3               | added_label | 1     | eq    |

This match rule will match the data in the `attributes` section in the message, therefore the subscription will be selected and we will return the user with `id=1` as a potential recipient of the notification.


### Example 2: Issue is commented

Let's look at the design mockup of editing form for custom subscription:

![image](https://user-images.githubusercontent.com/1885174/172578719-e9c9c25a-3364-43c5-a22a-15c8ad1e130b.png)


When a user saves this subscription, the integrator will make a call to Notifyd from dotcom. The payload would look like the following:

```ruby
subscriptions = Notifyd::Proto::Subscriptions::SubscriptionsClient.new(@connection)
result = subscriptions.batch_create_and_delete(
        Notifyd::Proto::Subscriptions::BatchCreateAndDeleteRequest.new(to_create: [{
            user_id: 1,
            reason: "subscribed",
            filters: [
                {
                    subject: "IssueComment",
                    trigger: "create",
                    match_rules: [
                        { attribute: "has_label", value: "11", match: "eq" },
                        { attribute: "assignee", value: "12", match: "eq" },
                        { attribute: "body", value: "design", match: "contains" },
                        { attribute: "author", value: "13", match: "eq" },
                    ]
                },
            ],
            custom_fields: {
               { name: "repository", value: "1" },
               { name: "repository", value: "2" },
               ...(12 repos)
            },
            topics: [
                { type: "repository", value: "1" },
                { type: "repository", value: "2" },
                ...(12 repos)
            ]
    }])
```


You might notice that the subscription is created for multiple repositories. We represent repositories as topics. This means the subscription is scoped only to the listed repositories.

This is how this subscription will end up in a database.

**meta_subscriptions**

| id  | user_id | name | details |
| --- | ---     | ---  | ---     |
| 1   | 1       | NULL | json    |


**subscriptions_v2**

| id  | user_id | topic_type | topic_value | subject      | trigger | reason     | meta_id |
| --- | ---     | ---        | ---         | ---          | ---     | ---      | ---     |
| 1   | 1       | repository | 1           | IssueComment | create  | subscribed | 1       |
| 2   | 1       | repository | 2           | IssueComment | create  | subscribed | 1       |
...(12 repos)

**subscriptions_match_rules**

| id  | subscription_id | name      | value  | match    |
| --- | ---             | ---       | ---    | ---      |
| 1   | 1               | has_label | 11     | eq       |
| 2   | 1               | assignee  | 12     | eq       |
| 3   | 1               | body      | design | contains |
| 4   | 1               | author    | 13     | eq       |
| 5   | 2               | has_label | 11     | eq       |
| 6   | 2               | assignee  | 12     | eq       |
| 7   | 2               | body      | design | contains |
| 8   | 2               | author    | 13     | eq       |
...(12 repos)

**subscription_custom_fields**
| id  | meta_id | user_id | name          | value |
| --- | ---     | ---     | ---           | ---   |
| 1   | 1       | 1       | repository_id | 1     |
| 2   | 2       | 1       | repository_id | 2     |
...(12 repos)


## Sample scenarios from Newsies

### Thread subscriptions

If a user is mentioned in an issue comment and the integrator wants to auto-subscribe such user to the thread they can do it with the following request to the Twirp API:

```ruby
subscriptions = Notifyd::Proto::Subscriptions::SubscriptionsClient.new(@connection)
result = subscriptions.batch_create_and_delete(
        Notifyd::Proto::Subscriptions::BatchCreateAndDeleteRequest.new(to_create: [{
            user_id: 1,
            reason: "subscribed",
            filters: [
                { subject: "Issue", },
                { subject: "IssueComment", },
            ],
            topics: [
                { type: "issue", value: "1" },
            ]
    }]))
```

This will subscribe the user to all the events on the issue with id=1.

The sample notification message that will match the subscription will contain the following data:

```ruby
{
    subject: {
        type: "IssueComment",
        id: 1
    },
    context: {
        trigger: "create"
    },
    related_topics: [
        { type: "repository", value: "456" },
        { type: "issue", value: "1" },
    ],
    attributes: [...]
}
```

### Watching

If a user wants to subscribe to all the events in a repo, the integrator can send the following Twirp API request:

```ruby
subscriptions = Notifyd::Proto::Subscriptions::SubscriptionsClient.new(@connection)
result = subscriptions.batch_create_and_delete(
        Notifyd::Proto::Subscriptions::BatchCreateAndDeleteRequest.new(to_create: [{
            user_id: 1,
            reason: "subscribed",
            topics: [
                { type: "repository", value: "1" },
            ]
    }]))
```


If a user wants to subscribe to all the events for Discussions in a particular repo, the integrator can send the following request:

```ruby
subscriptions = Notifyd::Proto::Subscriptions::SubscriptionsClient.new(@connection)
result = subscriptions.batch_create_and_delete(
        Notifyd::Proto::Subscriptions::BatchCreateAndDeleteRequest.new(to_create: [{
            user_id: 1,
            reason: "subscribed",
            filters: [
                { subject: "Discussion" },
            ],
            topics: [
                { type: "repository", value: "1" },
            ]
    }]))
```

The sample notification message that will match the subscription will contain the following data:

```ruby
{
    subject: {
        type: "Discussion",
        id: 1
    },
    context: {
        trigger: "create"
    },
    related_topics: [
        { type: "repository", value: "456" }
    ],
    attributes: [...]
}
```


