# Research into rollup summaries cleanup

originally posted as a comment on https://github.com/github/notifyd/issues/2954


The analysis here mostly focuses on the 2 biggest tables `rollup_summaries` and `notification_thread_subscriptions`:

<img width="1468" alt="Screenshot_2023-06-21_at_13 06 23" src="https://github.com/github/notifyd/assets/68183/07d7f3ba-9266-42e8-bd32-1bdc5fe222a0">

## Current Cleanup strategies

### `rollup_summaries`: when a thread is deleted via `DeleteAllForThreadJob`

Generally there is nothing pointing towards that job not properly cleaning up
rollup summaries for threads that don't exist anymore ([DD graph](https://app.datadoghq.com/dashboard/u5j-g26-scy/github-jobs?fullscreen_end_ts=1687875063444&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1685283063444&fullscreen_widget=219773423&tpl_var_class%5B0%5D=newsies%2Fdelete_all_for_thread_job&from_ts=1687270187074&to_ts=1687874987074&live=true)):

<img width="1461" alt="Screenshot_2023-06-27_at_16 11 38" src="https://github.com/github/notifyd/assets/68183/4916f373-71c9-4eb2-892a-f113f59da316">

### `notification_thread_subscriptions`: on unsubscribe, user deletion, list deletion


Notification thread subscriptions are also generally being cleaned up ([DD
graph](https://app.datadoghq.com/dashboard/u5j-g26-scy/github-jobs?fullscreen_end_ts=1687875579837&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1685283579837&fullscreen_widget=219773423&tpl_var_class%5B0%5D=newsies%2Fdelete_all_for_user_and_repository_owner_job&tpl_var_class%5B1%5D=newsies%2Fdelete_all_for_thread_job&tpl_var_class%5B2%5D=newsies%2Fdelete_all_for_user_job&tpl_var_class%5B3%5D=newsies%2Fdelete_all_for_list_job&tpl_var_class%5B4%5D=newsies%2Fdelete_all_for_list_and_users_job&tpl_var_class%5B5%5D=newsies%2Fdelete_all_for_user_and_lists_job&tpl_var_class%5B6%5D=newsies%2Fdelete_for_user_and_all_repositories_job&tpl_var_class%5B7%5D=newsies%2Fdelete&from_ts=1687270187074&to_ts=1687874987074&live=true)):

<img width="1472" alt="Screenshot_2023-06-27_at_16 19 52" src="https://github.com/github/notifyd/assets/68183/051aa70e-d0ab-43f6-a043-0780337bbcdf">


## Potential for additional cleanup

This is mostly focusing on `rollup_summaries` as it's the most pressing table that needs cleanup. `notification_thread_subscriptions` still is fairly big but is also slowly being phased out anyways with the notifyd migration work and thus less pressing.


### `rollup_summaries`

```
console_ro2 05:48:32 mysql2: github_production> describe rollup_summaries;
+------------+-----------------+------+-----+------------+----------------+
| Field      | Type            | Null | Key | Default    | Extra          |
+------------+-----------------+------+-----+------------+----------------+
| id         | bigint unsigned | NO   | PRI | NULL       | auto_increment |
| list_type  | varchar(64)     | NO   | MUL | Repository |                |
| list_id    | bigint unsigned | YES  |     | NULL       |                |
| raw_data   | blob            | YES  |     | NULL       |                |
| thread_key | varchar(80)     | NO   |     | NULL       |                |
+------------+-----------------+------+-----+------------+----------------+
5 rows in set (0.00 sec)
```

The table doesn't have any notion of age of a row (like an `updated_at`
column) which makes it really hard to impossible to age out rows that aren't
likely to be retrieved again.


```
console_ro2 06:38:44 mysql2: github_production> SELECT id,list_type,list_id,thread_key FROM rollup_summaries LIMIT 5;
+------------+--------------+---------+-------------------------+
| id         | list_type    | list_id | thread_key              |
+------------+--------------+---------+-------------------------+
| 3992016447 | Organization |      81 | SecurityAdvisory;110088 |
| 3098929717 | Organization |      81 | SecurityAdvisory;11023  |
| 3180695451 | Organization |      81 | SecurityAdvisory;11988  |
| 3237350865 | Organization |      81 | SecurityAdvisory;12481  |
| 3645759701 | Organization |      81 | SecurityAdvisory;132711 |
+------------+--------------+---------+-------------------------+
5 rows in set (0.00 sec)

console_ro2 06:39:05 mysql2: github_production> SELECT id,list_type,list_id,thread_key FROM rollup_summaries WHERE list_type = 'Repository' LIMIT 5;
+-----------+------------+---------+-------------------------------------------------------+
| id        | list_type  | list_id | thread_key                                            |
+-----------+------------+---------+-------------------------------------------------------+
| 186752351 | Repository |       1 | Grit::Commit;634396b2f541a9f2d58b00be1a07f0c358b999b3 |
|   7602579 | Repository |       1 | Grit::Commit;b49a6ff4ccd169eef6671263ccb29d3ead957697 |
|   6106440 | Repository |       1 | Issue;10006413                                        |
|   6228474 | Repository |       1 | Issue;10114588                                        |
|   6760481 | Repository |       1 | Issue;10580777                                        |
+-----------+------------+---------+-------------------------------------------------------+
5 rows in set (0.01 sec)

```

The table has almost 7 billion rows:

```
console_ro2 00:06:17 mysql2-analytics: github_production> SELECT COUNT(*) FROM rollup_summaries;
+------------+
| COUNT(*)   |
+------------+
| 6768087574 |
+------------+

```

The main usage as explained [in the Newsies `README`](https://github.com/github/github/blob/master/lib/newsies/README.md#rollupsummaries) is to provide a denormalized view on notifications content to minimize reads on (back then) the `mysql1` cluster. This means the main reference entity for rollup summaries that is relevant for cleanup is web notifications coming from the `notification_entries` cluster. The main relevance for cleanup here is that notification entries have a longer (potential) delay between the creation/update of a rollup summary and the presentation to the user. We e.g. also use rollup summaries for content of email deliveries. However that happens close to the notification event being created and not necessarily days/weeks/months later.

Taking into account `notification_entries` as the main reference point for rollup summaries we find out from https://data.githubapp.com that entries in that table reference about 258 523 272 unique rollup summary rows by ID:

```
SELECT COUNT(DISTINCT summary_id)
FROM hive.snapshots_presto.github_notifications_entries_notification_entries;
```

<img width="1137" alt="Screenshot_2023-06-23_at_08 00 00" src="https://github.com/github/notifyd/assets/68183/41e69a16-2660-43bc-88c7-d24cef8dece9">

From [some research from a couple of weeks ago](https://github.com/github/notifyd/issues/2895) we have a rough idea about the distribution of rollup summaries by thread type based on [this data SQL](https://data.githubapp.com/sql/share/f4ec7f89):

```
SELECT thread_type,
       count(*) AS COUNT
FROM
  (SELECT DISTINCT summary_id,
                   split(thread_key, ';')[2] AS thread_type
   FROM hive.snapshots_presto.github_notifications_entries_notification_entries)
GROUP BY 1
ORDER BY 2 DESC
```

<img width="1137" alt="Screenshot_2023-06-23_at_11 45 36" src="https://github.com/github/notifyd/assets/68183/e5acdc90-28f0-4fa1-9e73-6ca2f5a9da59">

This means we reference about 3.6% of all rows in `rollup_summaries`:

```
# Number of distinct rollup summary IDs by thread
Issue	= 149265788 = 149.265.788
CheckSuite	= 63569081 = 63.569.081
Grit::Commit	= 10240026 = 10.240.026
SecurityAdvisory	= 10002231 = 10.002.231
Release	= 8006799 = 8.006.799
RepositoryDependabotAlertsThread	= 2951114 = 2.951.114
Actions::WorkflowRun	= 1887409 = 1.887.409
Discussion	= 442215 = 442.215
RepositoryInvitation =	378785 = 378.785
Gist	= 24925 = 24.925
DiscussionPost = 15647 = 15.647
RepositoryAdvisory = 2802 = 2.802
AdvisoryCredit =	 404 = 404
referenced_rows_total = sum = 246.787.226

rollup_summary_rows = 6768087574 = 6.768.087.574


percentage_referenced_rows = referenced_rows_total / rollup_summary_rows = 0,0364633618

current_table_size_GB = 5 000 = 5.000
new_storage_GB = current_table_size_GB * percentage_referenced_rows  = 182,3168090703
```

<img width="1076" alt="Screenshot_2023-06-27_at_16 34 02" src="https://github.com/github/notifyd/assets/68183/53bccd1c-8676-4dbe-b72f-dc9ea9baf5eb">


This means roughly by getting rid of any rollup summary that isn't referenced
in the `notification entries` table, we would be able to reduce storage size
for `rollup_summaries` to just under 200G. This can be done slowly with a
transition and once we have shrunken the table we can add an `updated_at`
column and use it for periodic cleanup in sync with `notification_entries`
which are valid for 5 months ([pt-archiver definition in
Puppet](https://github.com/github/puppet/blob/master/hieradata/mysql/cluster/notifications_entries/master.yaml)). Doing it that way would also mean we don't have to run a month long migration (which is how long it would likely take to run a
column addition change on the current sized cluster) on data we know
we will delete anyways. And we don't need to wait months for the `updated_at`
column to be populated before we can benefit from it.

## Caveat: Graceful Degradation of Rollup Summaries
As mentioned, the `notification_entries` relation is our main reference point
for rollup summaries. And while this is true, we also use rollup summaries all
over the place for example when showing timeline markers or whenever an entity
(e.g. issue, pull request, discussion) is updated and thus updates its
corresponding summary. Currently these are almost always available, although
there is a [steady trickle of `missing_summary`
"errors"](https://app.datadoghq.com/dashboard/99i-4kb-q8g/newsiesnotifications?fullscreen_end_ts=1687525286556&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1684933286556&fullscreen_widget=1694693796754406&from_ts=1684932345079&to_ts=1687524345079&live=false)
on summary updates and it's generally fine:

<img width="1228" alt="Screenshot_2023-06-23_at_15 09 08" src="https://github.com/github/notifyd/assets/68183/542e1eec-43d8-4c6c-a99e-bc3b6f4236ac">


But this also means we have to do some investigation first to see what
graceful degradation looks like in more places than just the
`UpdateNotificationRollup` job to understand what situation we would be
triggering with such a mass deletion of old data.

I'm currently working on investigation these degradation paths and will update once I have results.


