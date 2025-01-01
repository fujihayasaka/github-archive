# RFC: Sharding of Notifyd data storage

## Intro

This documents is a high level description of a sharding approach that we can apply to split Notifyd database.

## Why do we need sharding?

There are several reasons why it's a good idea to split the storage and work with databases smaller in size.

1. Limited capacity of individual DB server that hosts the MySQL instance.
Smaller tables have smaller indexes which would allow to fit them into memory, which will result in faster queries. If there's not enough memory on the server indexes will be partially stored on disk which will slow down the processing.

If the system is growing gradually it might be a premature optimization to think about exhausting capacity of the hardware that runs database instances. In case of Notifyd - though it's a new project, it aims to replace existing Newsies system with all existing notifications-related data for GitHub users.

Below is the stats for current Newsies tables.

```
SELECT
  TABLE_NAME AS `Table`,
  ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024) AS `Size (MB)`
FROM
  information_schema.TABLES
ORDER BY
  (DATA_LENGTH + INDEX_LENGTH)
DESC;
```

```
+------------------------------------------------------+-----------+
| Table                                                | Size (MB) |
+------------------------------------------------------+-----------+
| rollup_summaries                                     |   3137510 |
| notification_thread_subscriptions                    |   1301401 |
| notification_subscriptions                           |    144773 |
| notification_user_settings                           |      3832 |
| mobile_device_tokens                                 |      2475 |
| notification_thread_type_subscriptions               |       954 |
| hidden_users                                         |       656 |
| mobile_push_notification_settings                    |       236 |
| mobile_push_notification_schedules                   |        65 |
| notification_subscription_events                     |        26 |
```

With this amount of data and taking into account the fact that one of the tables already was partitioned we need to think of the flexible solution that would allow us to seamlessly grow the platform.

We got some numbers from database team indicating that database needs to be split:

- single table occupying > 50% cluster space is a big risk
- tables should be < 4TB, ideally < 1TB in size

It would be helpful to create Notifyd [capacity dashboard](https://github.com/github/notifyd/issues/1463) to monitor the state of the db cluster.

2. Datasets we work with in memory may grow too big.
Notify consumer has to process large datasets of subscriptions, recipients and routing settings. Iterating over these datasets has linear time and memory complexity and may slow notifications delivery, which will result in violating our SLOs. Sharding if done in a right way would help to parallelize.

3. Number of simultaneous connections MySQL instance can handle limits scalability of the consumers.
Every MySQL server can handle limited amount of simultaneous connections. Every connection require a separate thread and expensive context switching. At some point increasing the number of consumers will stop bring performance benefits because MySQL will become a bottleneck. Sharding would allow to distribute the load to several instances and increase the scalability of the system.


## Choosing sharding key: user id

Notifications data (subscriptions and settings) are splitted by user so choosing user id as sharding key is an option.

There are two major groups of scenarios we have:

1. UI scenarios: user accesses their notification settings and subscriptions on GitHub. This guarantees that all the queries will contain sharding key (user id) as we're interested only in data related to the user.

2. Notify consumer scenarios: consumer receives a message from queue and matches subscriptions and settings, deriving list of final recipients.

This scenario is more complicated to cover because recipients data may belong to different shards.

To solve this problem we can deploy several groups of notify consumers, each group serves a single shard.

Event is being consumed by all of the consumers but every consumer processes only recipients found in a particular shard.


![image](https://user-images.githubusercontent.com/1885174/182583011-6489f617-ec2a-424b-b5d4-dbefcdc3723e.png)

We do not change the logic of the consumers, instead we're changing configuration of every group of consumers to access a single shard instead of connecting to keyspace.
In this way Vitess will not be trying to search for recipients in all the existing shards (which would defeat the purpose of sharding).

Every consumer group takes care only about the recipients located in a single shard and let other consumer groups process other shards as shown in a diagram below:

![image](https://user-images.githubusercontent.com/52420926/184191660-94793f56-1bcd-440b-a3d3-8ea964b6c388.png)

This algorithm describes how it would work with recipients that are derived from subscriptions.
Another source of recipients for Notifyd is a field Explicit recipients where recipients ids are listed. These users might not have subscriptions in the database that's why we need to have a separate mechanism to distribute them to consumers. For that we need to apply hash function to the ids to find out whether they would fall into the shard current consumer is responsible from. If so we process the recipient and if not we let other consumers to take care of it.


In this way we will reduce the amount of data we work with in memory and parallelize processing which will positively affect delivery time as well.



## Vitess

Vitess is mysql proxy that provides sharding possibilities and de-facto is a standard for GitHub at this moment.

NotifyD is already connected to MySQL not directly but via non-sharded keyspace notifyd_ks. If we shard the data we will have to move to sharded keyspace.

Turboscan has already implemented sharding, details here: https://github.com/github/turboscan#database-sharding

We have multiple sharded keyspaces working in prod already, for example [notifications_entries](https://github.com/github/github/blob/f1b1e40d78ef99d25662f784406f9f88513fb15e/db/vschema/notifications_entries_ks.json)

Vitess supports connections to a selected shard: https://github.com/vitessio/vitess/pull/2646
