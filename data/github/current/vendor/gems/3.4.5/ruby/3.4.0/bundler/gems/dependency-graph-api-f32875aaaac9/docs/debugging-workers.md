# Debugging Workers
## Table of Contents
- [Potential Issues](#potential-issues)
  - [Manifest File Ingest Stops / Slows](#manifest-file-ingest-stops--slows)
  - [Package to repo mapping taking too long](#package-to-repo-mapping-taking-too-long)
  - [Aqueduct Workers are not processing jobs](#aqueduct-workers-are-not-processing-jobs)

## Quick Links
- [Simple Ingest Dashboard][simple-ingest-dash] - Displays activity overview of most of our Kafka+Aqueduct ingest processes

## Proxima Note

For all of these issues, make sure you are looking at the metrics and logs associated with the correct stamp.
For most production issues, that will be the `dotcom` stamp. For Proxima stamps, that could look like `staff-wus2-01`.

# Potential Issues
## Manifest File Ingest Stops / Slows
### How to tell if it's happening:
- **SLO:** github/dependency-graph-api-manifest-ingest ([Datadog][monitor-manifest-ingest])
- **Monitors:**
  - [ManifestFileChanges lag grew over the last 30 minutes][monitor-manifestfilechanges-lag]
  - [github/dependency-graph-api-manifest-ingest][monitor-manifest-ingest]

### Potential Cause: Head of Line Blocking
#### How to tell if it's happening:
- The [dependency-graph-api][dg-api-sentry] Sentry bucket has a lot of recurring errors, usually related to text encoding issues.
- The rate of Manifests Processed drops significantly, but doesn't completely stop.
- The `server` listed in the needles are `repo-manifest-file-changes`

#### How to fix it:
- Determine a suspected repository by looking for repeated instances of `repository_nwo` in Splunk logs:
  `index=dependency-graph-api kafka_program="repo-manifest-file-changes" before_parse=true | top repository_nwo`
- Once you identify a problematic repository, add the NWO to the blocklist using this chatop: `.dg blocklist manifest_nwo add <NWO>`
- See if needles calm down and ingest goes back up.
- If adding to the blocklist doesn't work, as a last resort try [manually advancing the offset](https://github.com/github/dependency-graph-api/blob/master/docs/playbooks/advancing-offsets.md).

## Package to repo mapping taking too long
### How to tell if it's happening:
- **Monitor:** [dependency-graph-api/package-stage-duration-anomalies][monitor-package-stage-duration-anomalies]
- 📈 The [package ingestion queue graph][queue-depth-for-package-queue] keeps getting deeper.

### Potential remedies
- One possible cause is that a single package is causing a failure.
  - To verify this, search Splunk for repeated instances of a package_name in the package loader logs: `index=* app=dependency-graph-api job=package_loader | top package_name`
  - If you identify a package name that is taking up a significant percentage of logs
    (anything taking >1% seems suspect) you can blocklist the package.
    - In #dg-ops: `.dg blocklist packages add <PACKAGENAME> <ECOSYSTEM>`

# Splunk Query Cheatsheet
_Some potential queries that might be useful starting points for debugging._

- **Top repeated repository IDs in repo-manifest-file-changes**
  - **What this indicates:** A repository is repeatedly trying to be processed, which can indicate a failure or potential abuse vector.
  - **What to look for:** A single value that represents a significant percentage of activity.
  - **Query:** `index=dependency-graph-api kafka_program="repo-manifest-file-changes" before_parse=true | top github_repository_id`

## 🚨 Splunk Index Gotcha
Most dependency-graph-api worker logs are indexed in `index=dependency-graph-api` - but if you're having a hard time debugging, cast a wide net and try querying `index=*`

[monitor-manifest-ingest]: https://app.datadoghq.com/monitors/12542388
[monitor-manifestfilechanges-lag]: https://app.datadoghq.com/monitors/11690465
[monitor-package-stage-duration-anomalies]: https://app.datadoghq.com/monitors/12820994
[monitor-resque-queue-depth]: https://app.datadoghq.com/monitors/13775933
[queue-depth-for-manifest-queues]: https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?tile_focus=3539099910280348&fullscreen_widget=3539099910280348
[queue-depth-for-package-queue]: https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?tile_focus=4428251665835172&fullscreen_widget=4428251665835172
[simple-ingest-dash]: https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash
[dg-api-sentry]: https://sentry.io/organizations/github/issues/?project=1858608

## Aqueduct Workers are not processing jobs

**Also see [aqueduct.md](../aqueduct.md) for more details on the Aqueduct workers.**

### How to tell if it's happening:

- `ClearDependenciesJob` is not being run when explicitly invoked.
- `SyncVulnerabilitiesJob` is not being run for GHES/GHAE instances where dependency graph and code scanning are enabled.
- [Aqueduct queue depth](https://app.datadoghq.com/s/59fe6c40c/mmc-2hk-arq) is increasing or very high (multiple thousands of jobs for > 15 minutes)

### Potential cause: Aqueduct outage

Since Aqueduct is not managed by us, it might be the case that they are having a service outage. Check the `#aqueduct`, `#data-pipelines`, `#incident-command` or other relevant channels to see if that might be the case.

### Potential cause: Big surge of jobs

If the workers are processing jobs, but very slowly, you'll see the [queue depth increase](https://app.datadoghq.com/s/59fe6c40c/mmc-2hk-arq).

### Diagnostic tools

- [`aqueduct-developer` dashboard](https://app.datadoghq.com/dashboard/vmq-gt6-2h7/aqueductdeveloper?tpl_var_application=dependency-graph-api) (select `dependency-graph-api` as `$application`)
- [Splunk logs for `aqueduct-worker` deployments](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-production%22%20kafka_program%3D%22aqueduct-worker%22&display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=-60m%40m&latest=now&display.general.type=events&display.visualizations.charting.chart=line&display.page.search.tab=events&display.events.fields=%5B%22source%22%2C%22sourcetype%22%2C%22status%22%2C%22host%22%2C%22kafka_program%22%5D)

#### Viewing the Queue

You can use the [Aqueduct API](https://github.com/github/aqueduct/blob/master/docs/api.md) with `curl` to view the contents of the queue.

To see the first entry of the `service-to-service` queue in production (**must be run on a production shell host**):

```bash
curl --header "Content-Type:application/json" \
     --data '{"app": "dependency-graph-api", "queue":"service-to-service", "count": 1}' \
     https://aqueduct-gateway-production.service.iad.github.net/twirp/aqueduct.api.v1.JobQueueService/Peek
```

Job payloads are base64-encoded, so you can decode the payload with a one-liner using `jq` like this:

```bash
# This command won't show any useful output unless there is actually a first entry,
# so it might be good to run the command above first to make sure there is something in the queue.
curl --header "Content-Type:application/json" \
     --data '{"app": "dependency-graph-api", "queue":"service-to-service", "count": 1}' \
     https://aqueduct-gateway-production.service.iad.github.net/twirp/aqueduct.api.v1.JobQueueService/Peek \
     | jq -r .payloads[0] \
     | base64 -d
```

### Potential Remedies

- One potential cause is that the Aqueduct worker did not start correctly.
  - Check for changes to the [aqueduct-worker](https://github.com/github/dependency-graph-api/blob/master/script/aqueduct-worker) script
- Make sure that Aqueduct jobs are being enqueued and dequeued from the same endpoint.
  - For dotcom, _review labs_ use the Aqueduct staging endpoint (`https://aqueduct-staging.service.iad.github.net/`) by default. [However, jobs enqueued for dg-api are supposed to use Aqueduct production](https://github.com/github/github/pull/190484).
- If one particular kind of job is occupying most of the worker time, you can either [throttle a particular queue](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/chatops/#throttling-queues) or [pause it altogether](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/chatops/#pausing-queues) to let the workers catch up on the other jobs.
