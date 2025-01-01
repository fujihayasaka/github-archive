# Newsies to Notifyd subscriptions migration plan

**Edit September 2nd 2022**: Added more information after the initial analysis and the change of direction.

## Context

We aim to migrate **Newsies** subscriptions into **Notifyd**. At this point we have defined a model that describes subscriptions in the old system Newsies.

Subscriptions in **Newsies** are described by 3 models:

- **List Subscriptions**. In simple words represents subscription to everything that happens in _Repository/ImportableRepository/Team_. List subscriptions allow to subscribe to all the kinds of threads in some entity, including those thread types that don't currently have support for thread type subscriptions.
- **Thread Type Subscriptions** - optimisation subscription that allows user to subscribe to events of certain type (_Issue/PR/Discussion/Release_) that happen on specific _Repository_. Thread type subscriptions allow to subscribe to all the threads of some kind, in some entity (list in Newsies terms).
- **Thread Subscription** - represents subscription to concrete **Thread** (concrete Issue, PR, etc.). We have a wide variety of threads defined in **Newsies**. Threads subscriptions are subscriptions to particular threads of any kind, in some entity (list in Newsies terms).

An important thing to note about **List Subscriptions** and **Thread Type Subscriptions** is that they act as a single entity. They generally change together, an example: When a user subscribes to a repo all the previous thread type subscriptions for the repo are removed.

## Goals of this proposal

- Describe the **Newsies** subscriptions model using the **Notifyd** subscriptions domain.
- Propose the way to migrate **Newsies** subscriptions to **Notifyd** in iterations, i.e. split migrations in parts.
- Understand and describe dependencies between different subscriptions.

## Non goals of this proposal

- This proposal doesn't offer a concrete order of executing data transitions, but rather focuses on understanding how **Newsies** subscriptions can be moved to **Notifyd** model
- This proposal suggests common practices that should be applied when running a transition
- Reference implementation is left out of scope
- Data sync is left out of scope for separate proposal
- Settings sync is left out of scope
- Tracking data consistency is handled in a different proposal, for now we assume that we will rely on plain logs.

## Migration dependencies

We are doing a migration of the subscriptions to move parts of notifications delivery flows from **Newsies** to **Notifyd**. For example, we want _all_ `Issues` notifications to be delivered by our new system.

Naively, we could try to pick `Issue` or `Release` subscriptions and try to migrate it from **Newsies** to **Notifyd**.

But we couldn't go to GA after such migration, because more specific subscriptions (`Issue`) have dependencies on broader types of Subscriptions **Repository** or **Thread Type for Issues**.

### Example

Consider the following example of a user that has 3 types of subscriptions:

- **Watch** for **gh/gh repository**
- **Thread** for **Issue 123** in **gh/gh** because user was **assigned** to it
- **Thread** for **Issue 123** because user has **manually** subscribed to a thread

![184151846-cce69e4a-6e09-46e9-9bf6-51f9119d703f (1)](https://user-images.githubusercontent.com/5173831/185654024-1320d737-9148-42e1-b405-0d63ecd12587.png)

Imagine we migrate only specific **Thread** subscription for **Issues:assign** from **Newsies** to **Notifyd**

<img src="https://user-images.githubusercontent.com/5173831/184151937-fc7a9181-f24e-4f4b-be51-8e8d2bae64d9.png" alt="image" width="600" style="max-width: 100%;">

If we describe what **Newsies** and **Notifyd** systems know about **User** subscriptions on **gh/gh** repo then we get following results:

**Newsies:**

- **User** is subscribed to everything (Including **all events on Issue 123**) in **gh/gh** repo.
- **User** is subscribed to update on **Issue 123** because of reason **manual**

**Notifyd**:

- **User** is subscribed to **Issue 123** because of reason **assigned**

In case **Issue 123** gets updated then the two systems will have a _legit reason_ to send a notification to the end user, which will **result in duplicate emails/pushes**, etc.

> More generic subscription can still trigger a notification even if we migrated the subscription that is more specific to a triggered event.

It brings us to 2 conclusions:

- **Thread subscriptions** require **List** subscriptions to be present in **Newsies** and **Notifyd** to avoid duplicates.
- **Thread subscriptions** for different reasons for same **ThreadType** are required to be present in **Newsies** and **Notifyd** to avoid duplicates
- Besides that, **Thread Type Subscriptions** and **List Subscriptions** generally change as a single entity, which means that they have to be migrated as such even when their state is stored in different tables on **Newsies**

## Data mapping

Mapping of **Newsies** subscriptions to the data model in **Notifyd** is a complex problem that steps into **Data sync** problematic. We haven't solved it in previous proposals that's why we cover it here.

Let's take a look at data that needs to be migrated from **Newsies** to **Notifyd**.

### List Subscriptions

Most of **List** subscriptions are created using repository subscription dialog:
<img src="https://user-images.githubusercontent.com/5173831/185432036-96f51f3b-5201-45ec-862f-b33fc4b35a75.png" alt="image" height="400" style="max-width: 100%;">

So we can think of those **List** subscriptions in 2 categories:

- **Watchers** - checks if **User** is watching all notifications from specific **List** (Repository/Team/Org)
- **Ignored** - checks if **User** is ignoring all notifications from specific **List**

### Watchers

For the use-case of **Watchers** we can create a subscription that will be triggered on **all events** that happen on specific repository.

That said, we need to define what does **all events** mean, and if we expect to have any kind of dependencies for such subscriptions.

### Ignoring

For the use-case of **Ignoring** we shouldn't create a **Subscription** but rather a **Routing setting** that mutes all channels on that particular **List** - Repository/Team/Org.

We also need to turn off **ThreadType** subscriptions if they were created on repository

Here we run into the same question - if **Ignoring** actually mutes every type of subscriptions that is related to a repository? Wouldn't we have special-cases?
For example wouldn't we have cases when we want to ignore all subscriptions _except_ some special case? 

### Thread Type subscriptions

**Thread type subscriptions** are relevant for **Repository** List type only and are also created with subscription dialog:

<img src="https://user-images.githubusercontent.com/5173831/185433663-2c5c204b-e28b-4bcf-b1d0-4b828f8e5f98.png" alt="image" height="400" style="max-width: 100%;">

Even when their state is granularly stored on the database, they can't be incrementally migrated as their state depends directly of **List Subscriptions** and they need to be handled together.

### Thread Subscriptions

**Thread** subscriptions are related to specific **Issue**, **Discussion**, **PR** or other thread type.

Each **Thread** exists in a **Lists** (think of Repository or Team).

Migration of **Thread subscriptions** can be scoped as well to specific **Thread type** and ran in smaller iterations.

As we mentioned above - the migration of **Thread subscriptions** also requires the migration of corresponding the **List** and **Thread type** subscriptions.

See **Data** section.

### Mapping Notifyd subscriptions/routing settings to UI flows

**Newsies subscriptions** or **Newsies settings** are related to some specific UI flows. For example: **Watcher** and **Thread Type** subscriptions are related to the subscription dialog, etc.

However after we migrate Subscriptions/Routing settings to **Notifyd** by default **Subscription** or **Routing setting** will contain information on which notification events they should match or not.

![image](https://user-images.githubusercontent.com/5173831/185656176-c3b99bee-e585-4905-9a93-53231eeabf6a.png)

To fill this gap we need to add proper `custom_fields` so Notifyd API clients in dotcom can differentiate one subscription/routing setting from another and use correct data for existing and new UI flows.

We have been doing it already for `label_subscriptions` and `ci_activities` Subscriptions/Routing settings, however this approach wasn't standardized.
As we are taking on migrating Newsies flows - we need to bring some standardization into this process.

![image](https://user-images.githubusercontent.com/5173831/185660896-1c37be89-a307-4439-928d-804b5e243e55.png)

This is a solution for such mapping that we can define across **Newsies** related subscriptions/routing settings.

<!-- TODO: change this schema to use granularity instead (can be done with mermaid) -->

![image](https://user-images.githubusercontent.com/5173831/185664129-722a051f-112e-4806-b53a-3f20df438982.png)

The **granularity** custom field is proposed to be included in all synced/migrated subscriptions/routing settings records. Later we may consider to enforce this field via an SDK/Validation rule on our API.

The main motivation is to have a clear API for **Notifyd API** client to interact with subscriptions/routing settings. Imagine the use-case where you enable **Watcher** notifications (meaning you want all the activity on a repository) then we should delete all the rest of subscriptions for the same repository.

<!-- TODO: I'm now doubting this :D would it be possible to handle this asynchronously? -->

### Attribute **Notifyd** subscription to **Newsies** subscription

We need this in for several reasons:

- Connect specific **Notifyd** subscription/routing setting to specific **Newsies** subscription for investigations.
- Join **Notifyd** to **Newsies** data to assess quality of migration
- Better observability with more useful data

This approach can be taken across different Newsies subscription types, we just add related metadata to `custom_fields`.
Important to mention: We should use same custom fields attribution both in transition and data sync logic.

For example:

```go
CustomFields: []CustomField{
  {
    Name:  "newsies_list_subscription",
    Value: "<newsies-list-subscription-id>",
  },
  {
    Name:  "newsies_list_id",
    Value: "<repository-id>",
  },
  {
    Name:  "newsies_list_type",
    Value: "Repository",
  },
},
```

<!-- TODO: Is  there any other way to do this? should we find a way to store any kind of observability/debugging related data separated from real production data? -->

This data is needed mainly for debugging/observability purposes, so eventually we can delete it.

## Transition script considerations

Here are common considerations for transition scripts that we will need to implement.

### Use iterator for transitions

We should use `iterator` with a batching mechanism - [here are docs on how to setup a migration and use iterator](https://thehub.github.com/epd/engineering/products-and-services/dotcom/migrations-and-transitions/transitions/#applicationrecorddomaingithub_sql_batched)
We'll leave concrete implementation whoever works on the transition.

#### Request retries

During CI activities transition we have learned that `BatchCreateAndDelete` endpoint could end-up with **deadlock** and thus require a request retry.
We propose here to make sure that **Notifyd API** returns specific Twirp Error in case if deadlock appears. Then our client should attempt a retry.

### Migration logging

Every migrated/errored record should emit a logfile with information about:

- Affected user
- Newsies ListSubscription id
- Created Notifyd subscription id

It's considered in separate proposal, but we are thinking about emitting Hydro events to assess quality of data sync and migration.
Consider if it's available at the time of implementation.

### Idempotency

Transition should be built in a way that it can be re-ran for the same Newsies records, and it wouldn't
create duplicate subscription records in Notifyd.

### Resuming transition

We should be able to resume transition if it fails.
Usually for this purpose we can take latest migrated offset.

Errored records should be re-migrated separately.

### Use read only connection to not interrupt DB Primary

Heavy reads from Primary may result in increasing replication lag.
So please use

```ruby
readonly {
  ...
}
```

blocks.

# Proposal

## Create migration for List subscriptions

Proposal here is to create migration that will focus on single type of `List` subscriptions for example **Repository** based on our current roadmap.

![image](https://user-images.githubusercontent.com/5173831/185416489-5bd7d753-04b8-4efa-b5da-edd38aeb3c0f.png)

### Existing data

Here how records for List type subscriptions for repository look like today:

| #   | user_id | list_type  | list_id | ignored | notified |
| --- | ------- | ---------- | ------- | ------- | -------- |
| 10  | 123     | Repository | 456     | false   | false    |
| 10  | 321     | Repository | 876     | false   | true     |

- `ignored` flag indicates if notifications associated with specific list are ignored
- `notified` flag indicates if user has received notification after joining team/org and automatically watching team repos. This field doesn't create subscription on it's own, rather marks if one-off action has been ran for this type of subscription.

### Proposal Data mapping

When thinking about mapping **List subscriptions** to **Notifyd** we need to consider these things:

#### 1) How **List subscriptions** can be identified among other subscriptions for **User** when fetching those from UI?

We talked about this problem in [Mapping Notifyd subscriptions/routing settings to UI flows](#mapping-notifyd-subscriptionsrouting-settings-to-ui-flows) section.

Examples where we might need to fetch/update _only_ **Watcher** and **Ignoring** subscriptions/routing settings:

- Add **Watcher subscription** remove **Ignoring** and another way around
- Toggle **Thread type** subscription that should change state of **Watcher** or **Ignoring**

Proposal here is to add `category` into `custom_fields` section for migrated subscription/routing settings.
For **List subscriptions** case we will have add such `custom_field`:

```
CustomFields: [
  {
    Name:  "category",
    Value: "all",
  }
]
```

#### 2) How **Notifyd** subscription can be attributed to **Newsies** subscription?

We have discussed this question in **Attribute **Notifyd** subscription to **Newsies** subscription** section. In case of List subscriptions we can migrate:

```go
CustomFields: []CustomField{
  {
    Name:  "newsies_list_subscription",
    Value: "<newsies-list-subscription-id>",
  },
  {
    Name:  "newsies_list_id",
    Value: "<repository-id>",
  },
  {
    Name:  "newsies_list_type",
    Value: "Repository",
  },
},
```

#### 3) `Watchers/Ignored` "all notifications" behaviour

**Watcher** and **Ignoring** from product perspective can described as:

- when **Watch** subscription is enabled on repository - **User** wants to receive ALL notifications related to the repo.
- when **Ignoring** is set on repository - **User** won't receive ANY notifications related to the repo.

However, we need to be careful with definition of "all notifications". Let's consider different ways to solve this data mapping problem.

**Option 1**

In the simplest case we can define **Watch Subscription** like this:

```go
{
  UserID: 123,
  Name:   "Watcher Repository subscription for 123 user for ALL events",
  Details: {
    Topics: []subscriptions.Topic{
      {Type: "repository", Value: "456"},
    },
    Filters: [],
    CustomFields: [...]
  },
},
```

In this case, **ALL** notification events where user puts `repository:456` to `related_topcs` will match this subscription.
⚠️ This approach can work, we should carefully consider tradeoffs:

**Pros:**

- Straightforward data mapping
- No additional configuration from integrator side

**Cons:**

- ⚠️ **Easy to trigger unintended notifications.** - there are no safeguards that would prevent this kind of subscription
- Fixing this issue would require another data transition to add extra `match_rules` or `subject` filters.
- Harder to ensure grandual rollout to **Watchers** notifications. It's going to be harder to scope watcher subscriptions to specific subject type.

**Option 2**

What if we make `Watcher/Ignored` subscriptions behavior to be opt-in for integrators? In this case `Watcher/Ignored` subscriptions/routing settings
would define a match rule, for example:

```go
MatchRules:  [{
         MatchRule: "eq",
         Attribute: "category",  <- it means that integrator would include `category:all` attibute to the notification event when compositing a message
         Value: "all"
    }]
}]
```

Then integrator in `Notify` event would just need to add extra attribute, consider following `Notify` message:

```
{
  related_topics: [
    {"repository" : 456},
  ],
  actor: {
    id: actor_id
  },
  authorization: {...},
  rendering: {...},
  attributes: [
    { "name": "category", "value": "all" }
  ]
}
```

**Pros:**

- It's possible to opt-out from `Watcher/Ignoring` subscriptions
- Its declarative behaviour driven by integrator
- Integrators are less likely to trigger unintended `Watcher` notifications
- We will be in the position to scope Watchers/Ignoring rollout to specific subject type (For example Issues), it will make it easier to do gradual feature release and avoid email duplicates.

**Cons:**

- I anticipate that cases of opt-out are going to be rare. It _feels_ like SDK should be handling cases like this and not make integrators to pass this attribute all over the place.
- More records per migration.

Another alternative here would be specifying concrete `Subject_types` that would be enabled for `Watcher/Ignoring` use-case,
but we haven't event considered this option because this option is tedious in support.

Here how final data mapping could look like for `Watching/Ignoring` use-cases:

Subscription:

```go
{
  UserID: 123,
  Name:   "Watcher Repository subscription for 123 user",
  Details: {
    Topics: []subscriptions.Topic{
      {Type: "repository", Value: "456"},
    },
    Filters: [{
      {
	MatchRules:  [{
             MatchRule: "eq",
             Attribute: "category",
             Value: "all"
          }]
       }]
    },
    CustomFields: []CustomField{
      {
        Name:  "newsies_list_subscription",
        Value: "<list subscription id>",
      },
      {
        Name:  "newsies_list_id",
        Value: "456",
      },
      {
        Name:  "newsies_list_type",
        Value: "Repository",
      },
      {
        Name:  "category",
        Value: "all",
      },
    },
  },
},
```

Idea here to create `Watcher` subscription without specifying concrete `Subject` or `Trigger` types, but with `MatchRules` filter that enables logic discussed above.

`Ignoring` case will be represented by a routing setting where we will apply similar suggestions.
On top for Ignore use-case we will need to introduce some `channel` setting that mutes everything to avoid data re-migrations once we add support for new channels.
If we just turn off concrete all known channels now, then new channel that is enabled by default can create a bug in the futute.

Here is example of final routing setting for `Ignoring` use-case:

```go
  UserID: 123,
  Name:   "Routing setting: Ignoring Repository for 123 user",
  Details: {
    Topics: [{
      {Type: "repository", Value: "456"},
    }],
    Channels: {
      "ALL": "false", <- disable all channels, we need to introduce turn off block
    },
    Filters: [{
    {
	MatchRules:  [{
            MatchRule: "eq",
            Attribute: "category",
            Value: "all"
	    }]
       }]
    },
    CustomFields: []CustomField{
      {
		 Name:  "newsies_list_subscription",
		 Value: "<list subscription id>",
	  },
      {
        Name:  "newsies_list_id",
        Value: "456",
      },
      {
        Name:  "newsies_list_type",
        Value: "Repository",
      },
      {
	    Name:  "category",
	    Value: "all",
      },
    },
  },
},
```

That's how we could map `Wathers/Ignoring` use-cases.

### Migration script

Migration script can be implemented as Dotcom transition that should focus on single **List type**:

Example: Query for **List Subscriptions** should select only records for **Repository**

pseudo code:

```sql
SELECT * from notification_subscriptions
WHERE list_type = 'Repository' AND r.id > :last LIMIT 100
ORDER BY id;
```

Based on suggestions above transition should build **Notifyd** subscription or routing setting and make a Notifyd API call.
Same transition script could be reused for migrating other **List subscription** types: "Team" for example.

## Sub-Proposal: Create migration for thread type subscriptions

Proposal here is to create migration that will focus on single type of `ThreadType` subscriptions for example **Issues** based on our current roadmap.

![image](https://user-images.githubusercontent.com/5173831/185416446-6ef6dd72-3b2c-477b-a2cc-d47ed41ff024.png)

### Existing data

Here how records for **ThreadType subscriptions** for **Issues** look like in **Newsies** right now:

| id  | user_id | list_id | list_type  | thread_type | created_at              |
| --- | ------- | ------- | ---------- | ----------- | ----------------------- |
| 1   | 123     | 987     | Repository | Issue       | 2020-10-08 23:45:29.000 |
| 2   | 789     | 654     | Repository | Issue       | 2020-10-09 18:25:02.000 |

- Comparing **ThreadType subscription** to **List subscriptions**, we don't have **Ignoring** use-case.
- **Issues** and **PRs** have different subscriptions `thread_type` **ThreadType subscriptions**.
- Dataset is relatively small comparing to **Thread** and **List** subscriptions.
  Data: https://data.githubapp.com/sql/share/4bec78b6

| #   | thread_type   | count   |
| --- | ------------- | ------- |
| 1   | Discussion    | 118734  |
| 2   | Issue         | 165394  |
| 3   | PullRequest   | 199887  |
| 4   | Release       | 5818202 |
| 5   | SecurityAlert | 365531  |

### Data mapping

We talked about this problem in [Mapping Notifyd subscriptions/routing settings to UI flows](#mapping-notifyd-subscriptionsrouting-settings-to-ui-flows) section.
When thinking about mapping **Thread type subscriptions** to **Notifyd** we need to consider following things:

#### 1) How **Thread type** subscriptions can be identified among other subscriptions for **User** when fetching those from UI?

Examples where we might need to fetch/update _only_ **Thread Type** subscriptions settings:

- Modify **Thread type subscription** add/remove extra thread type.
- Toggle **Thread type** subscription that should change state of **Watcher** or **Ignoring**

Newsies code where **User** subscribing to **Watchers** to will trigger unsubscribe from **ThreadType** subscriptions - [link](https://cs.github.com/github/github/blob/f807a895bb1d82fc9cfac179d83b82983229ef2c/lib/newsies/service.rb#L346)

Solution is similar to what we have described for **List subscriptions**, suggestion here to use same `category` custom field attribute but with different value:
`category:thread_type`

Here how **Thread Type Subscription** could look like on **Notifyd** side:

```go
{
  UserID: 123,
  Name:   "Thread Type Issue subscription for 123 user",
  Details: {
    Topics: []subscriptions.Topic{
      {Type: "repository", Value: "987"},
    },
    Filters: []{
      {
        SubjectType: "Issue"
      },
      {
        SubjectType: "IssueComment"
      },
    },
    CustomFields: []CustomField{
      {
        Name:  "newsies_list_id",
        Value: "987",
      },
      {
        Name:  "newsies_list_type",
        Value: "Repository",
      },
      {
        Name:  "newsies_thread_type",
        Value: "Issue",
      },
      {
	    Name:  "category",
        Value: "thread_type",
      },
      {
	    Name:  "owner_type",
        Value: "repository",
      },
      {
	    Name:  "owner_id",
        Value: "<repository_id>",
      },
      {
	    Name:  "thread_type",
        Value: "Issue",
      },
    },
  },
}
```

### Migration script

Migration script can be implemented as Dotcom transition that should focus on single **Thread type**.

Example: Query for **Thread type Subscriptions** should select only records for **Repository** and **Issue**

pseudo code:

```sql
SELECT * from thread_type_subscriptions
WHERE list_type = 'Repository' and thread_type='Issue' AND r.id > :last LIMIT 100
ORDER BY id;
```

Based on suggestions above transition should build **Notifyd** subscription and make a Notifyd API call.
Same transition script could be reused for migrating other **Thread type subscriptions** types: "PR/Release/etc" for example.

## Sub-Proposal: Create reusable migration for thread subscription

Proposal here is to create migration that will focus on single type of `Thread` subscriptions **Issue** or **Gist** based on our current roadmap.

### Existing data

| id  | user_id | list_type  | list_id | ignored | reason       | thread_key | created_at              |
| --- | ------- | ---------- | ------- | ------- | ------------ | ---------- | ----------------------- |
| 1   | 123     | Repository | 1       | false   | state_change | Issue;456  | 2022-03-07 15:00:12.000 |
| 2   | 124     | Repository | 2       | false   | state_change | Issue;789  | 2022-03-07 15:00:12.000 |

**Thread subscriptions** are much better scoped than 2 previous types of subscriptions with following data:

- Concrete list type - **Repository** in this example
- Concrete thread - **Issue** in this case
- subscription **reason**

We need to consider several things when analyzing existing data:

1. **Issues** in `thread_key` may represent **Issues** or **PRs**. Migration script should account for that.
2. Dataset is quite large, for **Issues** the largest we have.

It allows to create very specific subscription on **Notifyd** side as well.

### Data mapping

When thinking about mapping **Thread subscriptions** to **Notifyd** we need to consider following things:

- We have some UI flows where we would need to differentiate **Thread** subscriptions from some other subscriptions users can create (for example Label subscriptions).
  Here we will apply same approach we did for 2 previous subscription types: `category:thread`

- We need to attribute **Notifyd** subscription to **Newsies** subscriptions as in previous subscription types
  Here we apply same approach we did for 2 previous subscription types.

### Migration script

Migration script can be implemented as Dotcom transition that should focus on single **Thread**.

Example: Query for **Thread Subscriptions** should select only records for **Repository** and **Issue**

pseudo code:

```sql
SELECT * FROM notification_thread_subscription
WHERE list_type = 'Repository' AND thread_key LIKE `Issue;%`
AND reason IN ('x', 'y', 'z') AND id > :last LIMIT 100
ORDER BY id;
```

Alternative approach for thread subscription is using Newsies Ruby api that offers great filtering functionality.

Considerations:

1. We need to split thread_key for transition query, or use `LIKE` query instead to match thread type.
2. If we decide to disable auto-subscriptions flows - we may want to migrate only subset of `reasons`. In this case we can create allowlist of `reasons`
3. **Issues** in this transition include **PR** so while implementing transitions we need to differentiate those from each other.

## Open questions

Add them here.
