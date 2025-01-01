# 34. Subscriptions data mapping

Date: 2022-09-29

## Status

Accepted

## Context

We have paved a path for mapping **Subscriptions** between Newsies and Notifyd in [Subscription migration plan](https://github.com/github/notifyd/blob/main/docs/proposals/2022-08-11-subscription-migration-plan.md).

Team has advanced to the implementation phase where we learned additional requirements about **Subscriptions** data mapping between Newsies and Notifyd.
This ADR captures our decision on how to proceed with **Subscriptions** and **Routing Settings** data mapping.

We illustrate this approach to data mapping based on 4 use-cases:
- Thread subscriptions for **Issues**
- Thread subscriptions for **Gists**
- Thread type subscriptions for **Issues**
- List subscriptions for **Repositories**

As input, we also assumed that Notifyd will receive 2 Notify events:
- **IssueComment** create event 
- **GistComment** create event owned by organisation

## Decision

### Thread subscription

We decided to scope **Thread** subscription with help of `topic`. Such subscription is relevant only for the concrete thread and nothing more.
According to this approach we don't specify concrete `Subject` or `Trigger` information. 

Thread subscriptions are scoped by topic, but we decided to scope them to particular set of events that will include `thread_participant_activity` attribute in `Notify` event. This is needed to avoid sending unintended notifications (for example after adding reactions label removals etc).

#### Issues thread subscription

Example of thread subscription for Issues, pseudocode: 

```
{
  user_id: 123,
  topics: [{type: "issue", value: "123"}],  # Topic scopes thread subscription a concrete thread
  reason: "manual",   # for thread subscriptions we keep reasons from newsies
  filters: [{
    subject_type: "any",
    trigger: "any",
    match_rules: [
      {attribute: "thread_participant_activity", value: "true", match_rule: "eq"},
    ],
  }],
  custom_fields: [
    {name: "repository_id", value: "345"}, # Id of repository, i.e. github/github. This is useful for fetching subscriptions that belong to repository
    {name: "owner_type", value: "user"}, # Owner can be user or organisation that owns thread
    {name: "owner_id", value: "987"}, # Id of org github or concrete user. This is useful to fetch all subscriptions that belong to a user/org
    {name: "thread_id", value: "123"}, # Thread_id and thread_type fields are needed to associate subscription with concrete thread.
    {name: "thread_type", value: "issue"},
    {name: "category", value: "thread"}, # Category field tells us what kind of subscription we have
  ],
}
```

#### Gists thread subscription

Example of thread subscription for Gists, pseudocode: 

```
{
  user_id: 123,
  topics: [{type: "gist", value: "123"}],  # Topic scopes thread subscription a concrete thread
  reason: "manual",   # for thread subscriptions we keep reasons from newsies
  filters: [{
    subject_type: "gist",
    trigger: "any",
    match_rules: [
      {attribute: "thread_participant_activity", value: "true", match_rule: "eq"},
    ],
  }],
  custom_fields: [
    {name: "owner_type", value: "user"}, # Owner can be user or organisation that owns thread
    {name: "owner_id", value: "987"}, # Id of org github or concrete user. This is useful to fetch all subscriptions that belong to a user/org
    {name: "thread_id", value: "123"}, # Thread_id and thread_type fields are needed to associate subscription with concrete thread.
    {name: "thread_type", value: "gist"},
    {name: "category", value: "thread"}, # Category field tells us what kind of subscription we have
  ],
}
```

### Constrains for List and Thread type subscriptions based on UI scenario

**List** and **ThreadType** subscriptions participate in complicated UI scenario which we call `Watcher` scenario today.
**They are mutually exclusive and need to be fetched/updated in single action**.

We decided to define a custom field that will group subscriptions and routing settings under same UI scenario if we need to fetch/update them together. In this case List and Thread type subscriptions are bound under the same `Watchers` scenario.

Also we decided to pick naming convention for such custom fieldsL: `<name of your scenario>_scenario`.
Scenario described above we decided to pick `watcher_scenario` cutom field. This field will be added to **List** and **Thread Type** subscriptions.
  
### Thread type subscription

Thread type subscriptions can match multiple threads in context of a repository. Based on this we scope Thread type Subscriptions to **Repository** instead of **Thread**.
We rely on `match_rules` to store the `thread_type` property. It will match Notify events that belong to a particular `thread_type`.

Thread type subscriptions are quite broad.
So we decided to add an additional matching attribute `watch_activity` to opt-in Notify events. Thread type subscription is supposed to match with ALL events of a certain thread type without active participantion on that thread.

It means that any `Notify` events on a certain `Repository` with certain `thread_type` and `watch_activity` in attribute, will match Thread type subscriptions.

#### Issues thread type subscription
Example of Thread type subscription for Issues

```
{
  user_id: 123,
  topics: [{type: "repository", value: "987"}],  # Topic scopes thread subscription a concrete thread
  reason: "thread_type_subscription",   # explicit reason for thread type subscriptions 
  filters: [{
    subject_type: "issue",
    trigger: "any",
    match_rules: [
      {attribute: "thread_type", value: "issue", match_rule: "eq"},           
      {attribute: "watch_activity", value: "true", match_rule: "eq"},
    ],
  }],
  custom_fields: [
    {name: "repository_id", value: "987"}, # Id of repository, i.e. github/github. This is useful for fetching subscriptions that belong to repository
    {name: "owner_id", value: "987"}, # Id of org github or concrete user. This is useful to fetch all subscriptions that belong to a user/org
    {name: "owner_type", value: "organisation"}, # Owner can be user or organisation that owns thread
    {name: "thread_type", value: "issue"},
    {name: "watcher_scenario", value: "true"},
    {name: "category", value: "thread_type"}, # Category field tells us what kind of subscription we have
  ],
}
```

#### Gist thread type subscription
Gists don't have use-cases for Thread type subscriptions as of today.

### List subscription

List subscriptions can match all subjects/threads in the context of a repository. 
The only option to scope List subscriptions is scoping based on **List** e.g. **Repository** in our case.

For List subscriptions we also want to control which subject will match `List` subscription. For that we add extra matching attribute `watch_activity` to opt-in Notify events to match List subscriptions in Notifyd.


Matching logic for **List** subscriptions also applies for relevant **Routing settings**.

#### Repository list subscription


```
{
  user_id: 123,
  topics: [{type: "repository", value: "987"}],  # Topic scopes thread subscription a concrete thread
  reason: "list_subscription",   # explicit reason for thread type subscriptions 
  filters: [{
    subject_type: "any",
    trigger: "any",
    match_rules: [
      {attribute: "watch_activity", value: "true", match_rule: "eq"},
    ],
  }],
  custom_fields: [
    {name: "repository_id", value: "987"}, # Id of repository, i.e. github/github. This is useful for fetching subscriptions that belong to repository
    {name: "owner_id", value: "987"}, # Id of org github or concrete user. This is useful to fetch all subscriptions that belong to a user/org
    {name: "owner_type", value: "organisation"}, # Owner can be user or organisation that owns thread
    {name: "watcher_scenario", value: "true"},
    {name: "category", value: "all"}, # Category field tells us what kind of subscription we have
  ],
}
```

#### Gist
There are no list subscriptions for Gists as of today, it's possible to easily add them with the new model.

#### Routing settings for Watcher use-case

Routing settings for Watcher use-case will ignore all events from `List`. That's why scheme for Routing settings will be identical to `List` subscriptions. The only different is that routing settings will need to specify `Channel`.

### Notify events we expect as input

As we decided to follow schema for List, Thread type and Thread subscriptions as described above, Notify events also need to change.
Here is the pseudocode for Notify events relate to `Issues` and `Gists`.

#### IssueComment

```
{
  related_topics: [
    { type: "repository", value: "345" }, # GitHub repo id for example
    { type: "issue", value: "123" }
  ],
  subject: {
     type: "issue_comment",
     value: "345"
  },
  attributes: [
    { name: "thread_type", value: "issue" },
    { name: "watch_activity", value: "true" },
    { name: "thread_participant_activity", value: "true" },
    .... # extra attributes for other use-cases
  ],
  ... # rest of fields
}
```

#### GistComment

```
{
  related_topics: [
    { type: "gist", value: "123" },
  ],
  subject: {
     type: "gist_comment",
     value: "345"
  },
  attributes: [
    { name: "thread_type", value: "gist" }, # Gists won't be matched against accidental List/Thread type subscriptions
    { name: "thread_participant_activity", value: "true" },
    .... # extra attributes for other use-cases
  ],
  ... # rest of fields
}
```

### Correlation data between Newsies and Notifyd

Originally we intended to store correlation data between Newsies and Notifyd subscriptions. For example:
- `newsies_thread_subscription_id` 
- `newsies_thread_type_subscription_id`
- `newsies_list_subscription_id`

Correlating data would help us to match Notifyd subscription to a Newsies counterpart. This would help us to ensure we haven't missed subscriptions during migration.

We came to conclusion that this data will be transient, and we should explore other ways to correlate Newsies and Notifyd subscriptions. We had exploration in [data sync quality proposal](https://github.com/github/notifyd/blob/main/docs/proposals/2022-09-12-newsies-notifyd-migration-data-quality.md).
For now, we decided not to store correlation data as part of custom fields for Notifyd subscriptions.


## Consequences

- We paved a path for migrating existing Newsies subscriptions
- We defined a common schema for custom fields related to Newsies subscriptions
- Current schema allows us to separate thread participant activity from the rest of events.
