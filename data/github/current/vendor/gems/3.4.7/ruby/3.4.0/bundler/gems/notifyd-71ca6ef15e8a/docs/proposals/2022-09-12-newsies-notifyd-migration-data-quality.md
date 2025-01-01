# Proposal—ensure quality of data during Data Sync Flow

## Context

We are migrating data between 2 systems that will be processing production notifications.
To understand the quality of migrated data and detect out of sync events early on we need a way to compare migrated subscriptions between **Newsies** and **Notifyd**.
However, we have several challenges with assessing the quality of migrated data.

### Data shape change

In the diagram below you can see how entities from 3 Newsies tables will be mapped to Notifyd tables.

![image](https://user-images.githubusercontent.com/5173831/185893585-5c9ace17-92da-4eb9-a2e8-025fa831a3bf.png)

Subscription data won't be migrated 1-1 and the shape of data is going to be changed as well.

### Data sync complexity – hard to cover all Newsies call sites at once

**Newsies** has multiple call sites to subscribe/unsubscribe users for a certain subscription type.
As part of data sync story we plan to do roughly following thing:

- Find Newsies call site that modifies subscription
- Implement similar call site that modified Notifyd subscription in similar way
- Repeat

However, there is a risk of missing certain call sites, which can lead us to get subscriptions out of sync. Consider following diagram:

![image](https://user-images.githubusercontent.com/5173831/185893751-0c22b919-390c-40e3-bd0c-cb83abe171a7.png)

- In green we marked flows that are covered in the current data sync proposal.
- In orange we marked maintenance jobs that are not covered yet in the data sync proposal yet but it’s clear that we need to Notifyd counterpart before going to GA, aka “known unknowns”.
- In red we marked flows that we missed by mistake, unknown unknowns.

So we need some kind of tooling to help us find such call sites marked as red.

### Observability for dark shipping notifications

Another problem that we need to consider is strategy to dark ship notifications.
Let’s say we assume that we reached a certain level of confidence about syncing subscribe and unsubscribe notifications for certain subject type.

But then final metric that should give us confidence is tracking of actual deliveries from Notifyd vs Newsies side:

![image](https://user-images.githubusercontent.com/5173831/185894000-f88949ac-c387-4901-9f28-1570e8fa4f76.png)

If 2 systems are in sync then:

- They will produce same number of subscribers
- They will produce same number of notifications

This can be considered as another way to ensure quality of subscription migration.

### Disable auto subscriptions discussion

There is a discussion not to copy Newsies behaviour 100% to Notifyd but rather try to simplify subscriptions logic. It means that the statement from above about producing the same output between 2 systems isn’t going to be true any more.

It also means that assessing the quality of synced data is going to be more difficult.

## Proposal

Current proposal contains several measures we can apply to ensure the quality of migrated data.

### Attribute Notifyd subscriptions to Newsies records

If we want to easily compare migrated data between 2 systems we need to sync/migrate subscriptions/routing settings records that are attributed to records that exist in Newsies.

We have talked about this in the migration proposal – add link.
As part of data sync/migration we suggest including Newsies related information to `custom_fields` of migrated subscription/routing setting:

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

Also, we can consider writing some data alongside a **Notifyd** subscription that will indicate when this snapshot was taken from Newsies DB (checking `updated_at` fields).
Then we should set up an airflow process that will take **Notifyd** database snapshots as it does snapshots of **Newsies** database right now. This process is well documented, and we just need to set up the right configuration for that.

Such an approach will enable us to join records between 2 databases in the data warehouse. Pseudocode query:

```sql
SELECT * FROM meta_subscriptions
JOIN subscriptions_custom_fields AS scs on id=scs.id
WHERE scs.newsies_list_subscription in (
    SELECT id FROM list_subscriptions WHERE ignored=false AND list_type=’Repository’
) AND updated_at BETWEEN (a AND b);
```

**Pros:**

- We can build quite sophisticated queries to compare snapshots of records between 2 databases
  We can compare records

**Cons:**

- There is a risk that 2 databases will make snapshots at different times which can lead to results diff
  - This can be mitigated though by making sure we only compare data up to the moment of the first snapshot.

## Emit Correlation events on CUD subscriptions calls

Proposal here is to emit correlation events to a Hydro topic that will describe when subscriptions were created/deleted/modified on **Newsies** side or on **Notifyd** side.
We will send this event to Hydro every time we attempt to create a subscription/routing setting in each corresponding system.
Such correlation events will contain information to assess, we match creation of subscriptions between **Newsies** and **Notifyd** find gaps in this process.

### Correlation event schema

Here what `CorrelationEvent` schema should include:

- What system Newsies or Notifyd this event is related to?
- correlation vector - something that will help us to match subscription modification between 2 systems Newsies and Notifyd
- Newsies attributes – list type, list id, thread type, thread id, comment type/id if applicable.
- Notifyd attributes – ID of created subscription/routing setting.
- Status – `success` or `failure`
- Elapsed time.
- TBD – list isn't comprehensive.

Here is diagram how emitting of those notification events would work:
![image](https://user-images.githubusercontent.com/5173831/185900162-86878dc3-0b88-4744-8667-42bea6831738.png)

### Where to emit correlation events?

There are a couple of options.
We have client code that calls into `GitHub.newsies.subscribe/unsubscribe` code and also some background jobs that plain delete subscriptions records.
From Notifyd side we will have some code that will make API calls to Notifyd.

The first approach would be to emit events in the client code that modifies subscriptions:
![image](https://user-images.githubusercontent.com/5173831/185902087-49f6547c-51b7-4936-ae8f-656471c15740.png)

**Pros:**

- Easier to capture context - like name of the callsite, extra variables

**Cons:**

- Again risk of not covering all callsites

Second approach - relying on AR hooks or capturing modification events on Notifyd API side.

![image](https://user-images.githubusercontent.com/5173831/185901813-717d784b-4cb8-4ea8-a8ea-fc288e871fdb.png)

**Pros:**

- With AR hooks no callsites would be missed

**Cons:**

- Inside of AR hook less information is available.
- Not all of the newsies models operate through AR for write operations.
  - This particular con discards this method as it is not available for all models.

### Observability

While we're certainly limited in order to pick a place to emit correlation events, we're can cover up by providing an extra layer of observability that:

- Covers a bigger surface by going as low level as possible and providing us a comparison point.
- Prepares the ground to be able to debug any discordance that appears.
- Gives us a much better understanding of how notifyd and notifications in general work.

The canonical entry point for newsies is `lib/newsies/service.rb`, which provides a public set of methods that any integrator can use to hook into newsies. Many of the subscription CUD operations there are already instrumented at a high level, which can give us a swift understanding of their behavior.

The proposal in this case is to:

- Complete that instrumentation with low level coverage that goes into lower layers of the code (namely database access).
- Cover such layers and the previous with a trio of:
  - Metrics
  - Tracing
  - Logs

In addition to that, cover the relevant notifyd endpoints similarly. Most of the migration will happen through the `Replace` endpoint for subscriptions, so we should, at least, make sure that the calls to this endpoint are:

- Properly tagged.
- Properly correlated in terms of Tracing.
- Sufficiently logged (i.e. what has the replace operation done? What has been removed?)

This would allow us to create a set of control dashboard to monitor the migration process until the very end of newsies. The goal of this dashboard is to help us debug things like:

- Missing callsites
- Failed calls
- Uncovered edge cases

### Open questions?

- What to select as correlation vector? Can it be request Id or something newly generated?
