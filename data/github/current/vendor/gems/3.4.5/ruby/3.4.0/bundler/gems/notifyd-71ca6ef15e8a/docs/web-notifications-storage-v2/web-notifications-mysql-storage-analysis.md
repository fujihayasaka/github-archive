# Web notifications storage analysis

## Intro

In this analysis I will concentrate on usage pattern and limitations of mainly two tables that power most of the functionality of web notifications:

1. `rollup_summaries` in `mysql2` cluster. This table stores denormalized data (in blob) of the notification thread.
2. `notification_entries`, `saved_notification_entries` in `notifications_entries` cluster.
`notification_entries` table saves a web notification entries displayed on `/notifications` page. It links a denormalized thread information from rollup_summaries to a user and stores read/unread status of the notification for a particular user. This table has many-to-one relation to `rollup_summaries`.

**NOTE:** `saved_notification_entries` schema fully repeates the schema of `notification_entries`. Saved (starred) entries have been extracted to a separate table due to time constraints. Running migrations on `notification_entries` was an availability risk and took a long time and at the time it was topping out at a month to run a migration. It was a business decision to add this table as it was a quicker solution. Additionally, by adding `saved_notification_entries` we risked this table growing even more because these records would not be cleaned up by `pt-archiver`.

Historical context can be found here: https://github.com/github/github/pull/88254#issue-312687499


[MySQL clusters topology](https://github.com/github/notifications/blob/master/docs/notifications-topology.png)


As you may see in the schema above, `notification_entries` table is moved to a separate cluster and sharded to 4 parts because of its size (detailed analysis below).


## /notifications page storage performance 

I decided to start looking into web notifications storage by having a quick look over the performance of `/notifications` page.

According to the [flamegraph](https://github.com/stafftools/graphs/flamegraph?url=%2Fnotifications&flamegraph_interval=1112) for `/notifications` page the most time is spent in CAP checks and not in storage.

As for the most time consuming parts of `/notifications` page, [repo notification counts](https://github.com/github/github/blob/master/packages/notifications/app/models/user/notifications_dependency.rb#L27) obviously stands out.

This method is used to calculate numbers of unread notifications per repo:

![image](https://user-images.githubusercontent.com/1885174/222145844-7fe15005-5d47-4065-9566-d8f0e5b57bad.png)


Most of the time however is spent [filtering out repositories](https://github.com/github/github/blob/master/packages/notifications/app/models/user/notifications_dependency.rb#L39-L43) and not fetching data from `notification_entries` table.


## Tables analysis


Number of rows in `notification_entries` table is over 2.5 billions.
Compared to this `saved_notification_entries` is relatively small with only over 3.7 millions of rows.


Volume of the stored data:

```
SELECT
  TABLE_NAME AS `Table`,
  ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024) AS `Size (MB)`
FROM
  information_schema.TABLES
WHERE
  TABLE_SCHEMA = "notifications_entries"
ORDER BY
  (DATA_LENGTH + INDEX_LENGTH)
DESC;

+-----------------------------+-----------+
| Table                       | Size (MB) |
+-----------------------------+-----------+
| notification_entries        |    740072 |
| spammy_notification_entries |       463 |
| saved_notification_entries  |        35 |
+-----------------------------+-----------+
```


```
SELECT
  TABLE_NAME AS `Table`,
  ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024) AS `Size (MB)`
FROM
  information_schema.TABLES
WHERE
  TABLE_SCHEMA = "github_production"
ORDER BY
  (DATA_LENGTH + INDEX_LENGTH)
DESC;

+----------------------------------------+-----------+
| Table                                  | Size (MB) |
+----------------------------------------+-----------+
| rollup_summaries                       |   2224793 |
| notification_thread_subscriptions      |   1615323 |
| notification_subscriptions             |    173987 |
| notification_user_settings             |      3822 |
| mobile_device_tokens                   |      2224 |
| notification_thread_type_subscriptions |       886 |
| hidden_users                           |       618 |
| mobile_push_notification_settings      |       210 |
| mobile_push_notification_schedules     |        54 |
| notification_subscription_events       |        25 |
| custom_inboxes                         |         4 |
+----------------------------------------+-----------+
11 rows in set (0.00 sec)
```

`notification_entries` size is around 740 Gb and for `rollup_summaries` it's over 2 Tb.

Most of the space occupied by `notification_entries` table (84%) is consumed by secondary indexes:

```
SELECT database_name, table_name,
SUM(ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2)) all_idx_size
FROM mysql.innodb_index_stats
WHERE table_name = 'notification_entries'
AND stat_name = 'size' AND index_name != 'PRIMARY'
GROUP BY table_name;

+-----------------------+----------------------+--------------+
| database_name         | table_name           | all_idx_size |
+-----------------------+----------------------+--------------+
| notifications_entries | notification_entries |    622037.87 |
+-----------------------+----------------------+--------------+
```

```
+-----------------------+----------------------+-------------------------------------------------------------+------------+
| database_name         | table_name           | index_name                                                  | size_in_mb |
+-----------------------+----------------------+-------------------------------------------------------------+------------+
| notifications_entries | notification_entries | user_id_and_unread_and_thread_key_and_list_type_and_list_id |   66170.39 |
| notifications_entries | notification_entries | index_notification_entries_for_user_by_thread               |   63794.42 |
| notifications_entries | notification_entries | index_notification_entries_for_list_by_thread               |   59566.42 |
| notifications_entries | notification_entries | index_notification_entries_for_user_by_unread_list          |   49717.48 |
| notifications_entries | notification_entries | index_notification_entries_for_user_by_list                 |   48072.44 |
| notifications_entries | notification_entries | user_id_and_unread_and_list_type_and_updated_at             |   39201.06 |
| notifications_entries | notification_entries | user_id_and_list_type_and_updated_at                        |   38265.11 |
| notifications_entries | notification_entries | user_id_and_owner_id_and_updated_at                         |   35220.05 |
| notifications_entries | notification_entries | user_id_and_author_id_and_updated_at                        |   34444.33 |
| notifications_entries | notification_entries | by_unread_user                                              |   29949.34 |
| notifications_entries | notification_entries | user_id_and_unread_and_updated_at                           |   28107.03 |
| notifications_entries | notification_entries | by_user                                                     |   27750.59 |
| notifications_entries | notification_entries | index_notification_entries_on_user_id_and_updated_at        |   27243.03 |
| notifications_entries | notification_entries | by_summary                                                  |   26574.33 |
| notifications_entries | notification_entries | index_notification_entries_on_unread_and_updated_at         |   21499.08 |
| notifications_entries | notification_entries | index_notification_entries_on_updated_at                    |   20823.11 |
+-----------------------+----------------------+-------------------------------------------------------------+------------+
```

Those are used for various querying combinations and custom searches. 

For `rollup_summaries` however it is not the case:

```
SELECT database_name, table_name, index_name,
ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) size_in_mb
FROM mysql.innodb_index_stats
WHERE table_name = 'rollup_summaries'
AND stat_name = 'size' AND index_name != 'PRIMARY'
ORDER BY size_in_mb DESC;
+-------------------+------------------+----------------------------------------------------------------+------------+
| database_name     | table_name       | index_name                                                     | size_in_mb |
+-------------------+------------------+----------------------------------------------------------------+------------+
| github_production | rollup_summaries | index_rollup_summaries_on_list_type_and_list_id_and_thread_key |  260024.88 |
+-------------------+------------------+----------------------------------------------------------------+------------+
```

Only about 10% is occupied by the single existing secondary index. Most of the space is taken by a denormalized thread data.
According to [this dashboard](https://app.datadoghq.com/dashboard/e6j-xz7-e48/large-tables?tpl_var_cluster%5B0%5D=mysql2&from_ts=1675433858432&to_ts=1678112258432&live=true) we have about 14 months left till mysql2 cluster where `rollup_summaries` is currently located, will run out of space. What we also need to take into account is that `rollup_summaries` table, unlike `notification_entries` is not being cleaned up.


## Load overview

[This dashboard](https://app.datadoghq.com/dashboard/jhe-xsz-pnw?from_ts=1677583787837&to_ts=1677670187837&live=true) shows `notification_entries` and `rollup_summaries` table statistics. 

Though select queries are prevalent according to Vivid Cortex [1](https://githubinc.app.vividcortex.com/default/profiler?hosts=&from=-3600&until=0&limit=20&rank=queries&by=time&orderBy=-throughput&filterByQueryTags=&filterByQueryText=notification_entries&filterByTagName=&filterByTagValue=&filterByTableCollections=&filterByDatabases=&advancedQueryTagFilter=false&compareOffset=0&hideVCQueries=false&cols=rank&cols=description&cols=change&cols=time&cols=throughput&cols=latency&cols=action&cols=queryNotifications&cols=userCpu&cols=systemCpu&cols=residentMemory&cols=virtualMemory&cols=bytesRead&cols=bytesWritten&cols=fileHandlers&cols=syscallsWrite&cols=syscallsRead&cols=count&cols=dataSize&cols=indexSize&cols=totalSize&cols=dataFree&cols=rowCount&cols=mplQueryCount&cols=mplQueryLocks&cols=mplQueryLocked&cols=pgLocksWaitTime&cols=pgLocksCount&cols=gCount&cols=blocked&cols=waitTime&cols=mongoTimeAcquiring&cols=mongoAcquireCount&cols=mongoAcquireWaitCount&cols=mongoDeadlockCount&cols=queryWaitTime&markersEnabled), [2](https://githubinc.app.vividcortex.com/default/profiler?hosts=&from=-3600&until=0&limit=20&rank=queries&by=time&orderBy=-throughput&filterByQueryTags=&filterByQueryText=rollup_summaries&filterByTagName=&filterByTagValue=&filterByTableCollections=&filterByDatabases=&advancedQueryTagFilter=false&compareOffset=0&hideVCQueries=false&cols=rank&cols=description&cols=change&cols=time&cols=throughput&cols=latency&cols=action&cols=queryNotifications&cols=userCpu&cols=systemCpu&cols=residentMemory&cols=virtualMemory&cols=bytesRead&cols=bytesWritten&cols=fileHandlers&cols=syscallsWrite&cols=syscallsRead&cols=count&cols=dataSize&cols=indexSize&cols=totalSize&cols=dataFree&cols=rowCount&cols=mplQueryCount&cols=mplQueryLocks&cols=mplQueryLocked&cols=pgLocksWaitTime&cols=pgLocksCount&cols=gCount&cols=blocked&cols=waitTime&cols=mongoTimeAcquiring&cols=mongoAcquireCount&cols=mongoAcquireWaitCount&cols=mongoDeadlockCount&cols=queryWaitTime&markersEnabled) the amount of select vs insert/update are comparable.

Both tables have high read and write load. `notification_entries` is updated every time web notification is delivered to a particular user.

`rollup_summaries` is updated every time there's a change to a notification thread (include events on notifiable threads, i.e. Issue, Pull Requests, Discussions etc).

The write load and size of the `notification_entries` table was the reason why [it had to be sharded and moved to a separate cluster](https://github.com/github/notifications/issues/235).

Sharding helped with isolating replication lag caused by large amount of writes to a single shard instead of the whole `mysql2` cluster. It also helped tu run migrations much more quickly than on mysql2 cluster.

## Queries overview

### rollup_summaries

The most frequent queries executed on `rollup_summaries` are the following:

1. Query to lookup rollup summary by thread:

```sql
select `rollup_summaries`.* from `rollup_summaries` where `rollup_summaries`.`list_type`=? and `rollup_summaries`.`list_id`=? and `rollup_summaries`.`thread_key`=? limit ?
```
This query is executed every time notification is dispatched.


2. Query to fetch rollup summary by its id:

```sql
select `rollup_summaries`.* from `rollup_summaries` where `rollup_summaries`.`id`=?
```

This query is executed every time notification is delivered.


3. Query to update rollup summary by its id:

```sql
update `rollup_summaries` set `rollup_summaries`.`raw_data`=? where `rollup_summaries`.`id`=?
```


**All queries average latency is below 1ms.**


### notification_entries

1. Query to check if the counter of unread notifications exceeds 1000 (used to display counters on `/notifications` page):

```sql
select ? as one from `notification_entries` where `notification_entries`.`user_id`=? and `notification_entries`.`unread`=? limit ?
```

2. Query to insert notification entry (happens when notification gets delivered):

```sql
insert into `notification_entries` (`user_id` , `author_id` , `owner_id` , `summary_id` , `list_type` , `list_id` , `thread_key` , `unread` , `reason` , `updated_at` , `id`) values (?) on duplicate key update `reason`=if (?<=`updated_at` , `reason` , ?) , `unread`=if (?<=`updated_at` , `unread` , ?) , `updated_at`=if (?<=`updated_at` , `updated_at` , ?)
```

3. Query to display `IsReadByViewer` GraphQL attribute on Issues/PullRequests

```sql
select `id` , `user_id` , `summary_id` , `list_type` , `list_id` , `thread_key` , `unread` , `reason` , `updated_at` , `last_read_at` , `owner_id` , `author_id` from `notification_entries` where `notification_entries`.`user_id`=? and `notification_entries`.`list_type`=? and `notification_entries`.`list_id`=? and `thread_key` in (...) limit ?
```

**Average latency for the most frequent queries is below 1ms.**

The slowest query serves batch delete notifications from the UI, but even this is not terribly slow averaging at 65ms:

```sql
delete from `notification_entries` where `notification_entries`.`list_type`=? and `notification_entries`.`list_id`=? and `notification_entries`.`thread_key`=? and `notification_entries`.`id` in (...) limit ?
```

## Conclusion

To summarize findings from this document, current storage approach has several pain points:

1. We have a heavy write load on web notifications and a requirement to quickly retrieve the data while having minimum to none time lag between updates and retrievals (because user wants to see their notifications up to date). This access pattern makes it more challenging to design an appropriate storage solution. 
1. The heavy write load result in big size of `notification_entries` and `rollup_summaries` tables that need to be distributed and MySQL without Vitess offer no tools for that. 
1. `rollup_summaries` table is a key-value store and stores blobs of denormalized thread data. This does not look like the case for a relational database.
1. `notification_entries` table plays indexing role for notification threads (`rollup_summaries`). Because of the overwhelming amount of secondary indexes on this table we're able to quickly select notifications using limited amount of criteria like list and thread. `notification_entries` joins with the `rollup_summary` that provides denormalized data we use to render web notifications. This limits the flexibility of our search queries because we can search only by the columns defined in `notification_entries`. Therefore `notification_entries` looks like a secondary index for the data stored in `rollup_summaries`.
1. For `notification_entries` size is especially critical because this table has many secondary indexes that may not fit in memory which will result in a degraded read performance. Therefore adding more indexing criteria and as a result more indexes to `notification_entries` is a bad idea so for now our searching capabilities are limited.
1. The index size in `notification entries` is much larger than the data size. This is an anti-pattern and [the suggestion is to use a different database, like ElasticSearch](https://docs.google.com/document/d/1apRdgaENc3-eCKXZRMx54Z9ZWlGZIvyKjK8ON_fgWVs/edit#heading=h.pyj73y52wq8f).
**NOTE**: I found an [interesting investigation](https://github.com/github/project-nova/issues/5#issuecomment-505438004) regarding search limitations and a possibility to use ElasticSearch. To summarize, as the tables for web notifications are write heavy that will result in too many updates to Elasticsearch indexes. We need to take this into account when choosing new solutions.

1. Despite `notification_entries` references `rollup_summaries` we do not use advantages of a relational database to perform joins on these tables because they are located in separate clusters.




