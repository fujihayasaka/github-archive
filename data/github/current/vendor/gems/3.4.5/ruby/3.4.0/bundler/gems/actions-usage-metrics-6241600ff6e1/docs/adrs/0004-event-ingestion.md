# Actions Usage Metrics Event Ingestion

> :warning: This has been partially [superseded](./0479-kusto-data-warehouse-followers.md). Read with caution.

## Status
Proposed - 2023-09-12  
[Partially superseded](./0479-kusto-data-warehouse-followers.md) - May 2024

## Context

Actions Usage Metrics needs source data representing job-level information - e.g. workflow, repository, runner type, etc. Currently this information is produced by the `actions-results` service. This ADR describes the events we'll consume and how we'll consume them.

Note: This ADR does not make a decision on what we then *do* with the events (e.g. store in Cosmos, process further, etc).

## Decision

Consume the existing `github.actions.v0.ComputeUsage` event via `aqueduct-bridge`.

### Existing `ComputeUsage` event

The `ComputeUsage` event was [designed specifically for Actions Insights](https://github.slack.com/archives/C05PM068NKC/p1694117366778429). Given that the [Q2/MVP goals](https://github.com/github/c2c-actions/discussions/7581) for rebuilding Actions Usage Metrics has the same / reduced feature set, the event will continue to work for our scenarios.

The `ComputeUsage` event contains the necessary fields to populate the initial experience, e.g. `repository_owner_id`, `repository_id`, `workflow_file_path`, `runner_runtime`, `runner_type`, `usage_mins`, `invoking_user_id`. There are also additional fields that will be useful as we expand feature set, and the ability to correlate with billing usage events will be useful for consistency checking and potentially features to link billing and usage.

As the existing Insights feature did, we eventually will need to consume a workflow-level event (e.g. `WorkflowExecution`) for run metrics such as run duration and run success/failure rates, but don't initially need to consume that event.

<details>
<summary>Example ComputeUsage event</summary>

```
{
  "realm": "dotcom",
  "workflow_job_id": "11801910124",
  "external_job_id": "12345678-040a-526b-2ce8-bdc85f692774",
  "check_run_conclusion": "RESULT_SUCCESS",
  "check_run_id": 16725033724,
  "check_suite_id": 16089791315,
  "invoking_user_id": 87149725,
  "invoking_event_type": "pull_request",
  "workflow_file_path": ".github/workflows/foo.yml",
  "repository_id": 300761835,
  "repository_owner_id": 643070,
  "repository_visibility": "REPOSITORY_VISIBILITY_PUBLIC",
  "runner_runtime": "RUNNER_RUNTIME_LINUX",
  "runner_type": "RUNNER_TYPE_HOSTED",
  "runner_properties": [
    {
      "key": "RequestedLabel",
      "value": "ubuntu-latest"
    },
    {
      "key": "MachineLabel",
      "value": "Ubuntu22"
    }
  ],
  "queued_at": {
    "seconds": 1694539372,
    "nanos": 969992000
  },
  "started_at": {
    "seconds": 1694539379,
    "nanos": 960000000
  },
  "completed_at": {
    "seconds": 1694539741,
    "nanos": 160000000
  },
  "product_sku": "linux",
  "usage_ms": 361200,
  "usage_mins": 7,
  "workflow_name": "",
  "job_name": "Foo",
  "job_user_identifier": "build.__default",
  "workflow_run_id": 6162808001,
  "workflow_run_attempt": 1
}
```

</details>

### Ingestion

> :warning: This section has been [superseded](./0479-kusto-data-warehouse-followers.md) and we no longer consume via aqueduct-bridge or Hydro, as we consume the events from the Data Warehouse.

We'll consume the `ComputeUsage` event (and likely any future events we need) via aqueduct-bridge, because:
* We meet the criteria at https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/bridge - most notably we don't care about publishing order.
* As a team inexperienced with Hydro and Aqueduct, worrying about tuning Kafka partitioning/client batch sizes/timeouts/heartbeating/etc would be a significant and unnecessary distraction from delivering the feature.
* Other teams such as Billing Platform are happily using aqueduct-bridge for very similar scenarios. 
* We can always switch in the future if we decided we needed the complexity of managing Hydro/Kafka consumers.


## Alternatives

### Event

There is no compelling reason to use or design a different job-level event as the `ComputeUsage` event fits our needs and was designed for this exact purpose.

### Ingestion

Rather than consuming the events via aqueduct-bridge, we could consume them directly from Hydro by implementing Kafka consumers. We decide not to take this approach for multiple reasons listed above. The only obvious benefit of directly using Hydro/Kafka consumers would be to take advantage of batching, e.g. partition the topic such that a consumer is likely to process multiple jobs for the same workflow / billing owner at the same time, and thus be able to batch calls to the data store (e.g. Cosmos). But this is a theoretical performance optimization that could be done later if needed.