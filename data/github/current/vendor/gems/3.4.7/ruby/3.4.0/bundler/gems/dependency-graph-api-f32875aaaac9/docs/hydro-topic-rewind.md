## Hydro Topic Rewind

One of the many advantages of event consumption vs. request-based communication between services at GitHub is the ability to rewind topic consumption and reprocess events that may have been skipped during an extended availability incident, or due to logic changes that can make better use of previously seen data. However, in any Kafka-based eventing system like Hydro, the process is a bit convoluted.

This doc is intended to clear up the general mysteries, and call out some DG-API specific patterns in place to enable topic rewinds as needed.

### General Info
In the beginning, when Kafka was young, the world was innocent. Donald Trump was just a harmless TV personality, interest rates were low, and your grandma didn't have a Facebook account yet.

Back in those days, a developer like you had to track your own topic partition offsets to manage how much Kafka data your service had consumed, and resume from where you left off between deploys. Kafka had (very) rough plumbing to do this using a Zookeeper deployment, and some folks solved this client-side using a good ol' database. Later, Kafka began to handle consumer group tracking by _dogfooding_: consumer group's offsets into each partition is now tracked via a special, internal Kafka topic.

When a Kafka broker (server) receives consumer group registration requests associated with a _previously unknown group name_ it consults (once and only once!) a related client-supplied configuration parameter that tells it whether to initiate _topic consumption_ and _consumer offset tracking_ from the _earliest known records_ in the topic (oldest, first-written) or the _most recent_.

After this point, whenever the (known) consumer group is registered to by a client, the topic consumption just picks up from the last recorded offsets already seen by the broker hosting each partition, and the earliest/latest client config is ignored from then on.


### Playbook

#### Partial Rewind
Example: there is an availability incident with repository deleted event consumption. Because the DG-API consumer is currently "best effort" and the oncall First Responder did not pause the consumer (deploy 0 sized replica set temporarily, etc.) data was consumed and dropped during this window.

In order to repair the missing data without permanent loss, the topic will be rewound and replayed from an earlier point. This will not involve resetting the consumer group to the beginning of the topic, just running it back to before the incident and reprocessing until the topic is caught up to most-recent submissions again.

1. Temporarily deploy the affected consumer process from a branch PR with `replicas` (replica set size) set to 0. Example: [link](https://github.com/github/dependency-graph-api/blob/master/config/kustomize/base/workers/deployments/repository_deleted.yaml#L10)
1. Watch DataDog to see the topic consumption go idle as the deploy completes: [link](https://app.datadoghq.com/dashboard/f5h-jdw-kzi/hydroconsumer?tpl_var_consumer%5B0%5D=dependency_graph_repo_deleted&tpl_var_topic%5B0%5D=cp1-iad_ingest_github_v1_repositorydeleted&from_ts=1687960114875&to_ts=1687974514875&live=true). **Remember** you should see consumer lag increase, and `#dg-alerts` topic monitors may trigger. This is expected.
1. Visit the [Hydro Admin Page](https://hydro.githubapp.com/kafka/clusters/potomac/consumer_group?group_id=dependency_graph_repo_deleted&tab=assignments) and locate the target consumer group
1. Select the `Reset Offsets` tab, and select the time window or hardcoded offsets/partitions you wish to rewind. In this call _all Partitions_ and a _time window_ prior to the incident would be appropriate
1. After applying the update, redeploy `master` to resume consumption. **Optional**: deploy a _2nd temporary PR with code changes relevant to the backfill_
1. Watch DD graphs, Splunk, and Sentry to ensure your rewound consumer is behaving as expected
1. Close out the temporary PRs and redeploy `master` (if not done earlier) when the backfill is caught up and completed


#### Full Rewind
Example 1: New logic is added to a topic consumer that requires full reconsumption of the source data to backfill. Example 2: The addition and dry-run testing of the new OSPO Package License Gateway data, which was never consumed by DG-API before.

1. Deploy a temporary PR to set a Hydro sentinel env var to reconfigure the client to consume _new consumer group names_ from the _earliest known offset_ for the target consumer, and _rename it's group_: [example here](https://github.com/github/dependency-graph-api/pull/3665/files)
1. Observe DataDog, Splunk, and Sentry during the deploy to ensure the backfill is progressing as expected
1. **Optional** (to unblock deploys during the backfill): merge the temporarily PR until the backfill is completed
1. Redeploy `master` (or revert the temp PR) when the backfill is completed


#### Other Backfill Methods
When shipping a new Manifest Adapter and ecosystem, we usually just seed the source topic with a full set of new events, one for each affected repository we wish to reprocess. This is a fine way to proceed, when it's practical. In fact, for a non-compacted topic, only the most recent weeks/months of event history will be available, so there is no good alternative if the data you require has "aged out" of the topic, or in the case of a new ecosystem for DG that may have never been in the topic to start with.

