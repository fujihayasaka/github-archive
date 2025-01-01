# Protocol Documentation
<a name="top"></a>

## Table of Contents

- [proto/usage.proto](#proto_usage-proto)
    - [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField)
    - [DateRange](#actions_usage_metrics-api-v1-DateRange)
    - [ExportHeader](#actions_usage_metrics-api-v1-ExportHeader)
    - [Filter](#actions_usage_metrics-api-v1-Filter)
    - [GetAutoCompleteRequest](#actions_usage_metrics-api-v1-GetAutoCompleteRequest)
    - [GetAutoCompleteResponse](#actions_usage_metrics-api-v1-GetAutoCompleteResponse)
    - [GetExportStatusRequest](#actions_usage_metrics-api-v1-GetExportStatusRequest)
    - [GetExportStatusResponse](#actions_usage_metrics-api-v1-GetExportStatusResponse)
    - [GetJobUsageRequest](#actions_usage_metrics-api-v1-GetJobUsageRequest)
    - [GetJobUsageResponse](#actions_usage_metrics-api-v1-GetJobUsageResponse)
    - [GetJobsRequest](#actions_usage_metrics-api-v1-GetJobsRequest)
    - [GetJobsResponse](#actions_usage_metrics-api-v1-GetJobsResponse)
    - [GetOrgUsageRequest](#actions_usage_metrics-api-v1-GetOrgUsageRequest)
    - [GetOrgUsageResponse](#actions_usage_metrics-api-v1-GetOrgUsageResponse)
    - [GetPerformanceSummaryRequest](#actions_usage_metrics-api-v1-GetPerformanceSummaryRequest)
    - [GetPerformanceSummaryResponse](#actions_usage_metrics-api-v1-GetPerformanceSummaryResponse)
    - [GetRepoUsageRequest](#actions_usage_metrics-api-v1-GetRepoUsageRequest)
    - [GetRepoUsageResponse](#actions_usage_metrics-api-v1-GetRepoUsageResponse)
    - [GetRunnerLabelsRequest](#actions_usage_metrics-api-v1-GetRunnerLabelsRequest)
    - [GetRunnerLabelsResponse](#actions_usage_metrics-api-v1-GetRunnerLabelsResponse)
    - [GetRunnerRuntimeUsageRequest](#actions_usage_metrics-api-v1-GetRunnerRuntimeUsageRequest)
    - [GetRunnerRuntimeUsageResponse](#actions_usage_metrics-api-v1-GetRunnerRuntimeUsageResponse)
    - [GetRunnerTypeUsageRequest](#actions_usage_metrics-api-v1-GetRunnerTypeUsageRequest)
    - [GetRunnerTypeUsageResponse](#actions_usage_metrics-api-v1-GetRunnerTypeUsageResponse)
    - [GetUsageByRepoWorkflowRunnerRequest](#actions_usage_metrics-api-v1-GetUsageByRepoWorkflowRunnerRequest)
    - [GetUsageByRepoWorkflowRunnerResponse](#actions_usage_metrics-api-v1-GetUsageByRepoWorkflowRunnerResponse)
    - [GetUsageSummaryRequest](#actions_usage_metrics-api-v1-GetUsageSummaryRequest)
    - [GetUsageSummaryResponse](#actions_usage_metrics-api-v1-GetUsageSummaryResponse)
    - [GetWorkflowPerformanceRequest](#actions_usage_metrics-api-v1-GetWorkflowPerformanceRequest)
    - [GetWorkflowPerformanceResponse](#actions_usage_metrics-api-v1-GetWorkflowPerformanceResponse)
    - [GetWorkflowsRequest](#actions_usage_metrics-api-v1-GetWorkflowsRequest)
    - [GetWorkflowsResponse](#actions_usage_metrics-api-v1-GetWorkflowsResponse)
    - [Job](#actions_usage_metrics-api-v1-Job)
    - [JobUsageItem](#actions_usage_metrics-api-v1-JobUsageItem)
    - [OrderBy](#actions_usage_metrics-api-v1-OrderBy)
    - [OrgUsageItem](#actions_usage_metrics-api-v1-OrgUsageItem)
    - [ProjectionOptions](#actions_usage_metrics-api-v1-ProjectionOptions)
    - [RepoUsageItem](#actions_usage_metrics-api-v1-RepoUsageItem)
    - [RepoWorkflowRunnerUsageItem](#actions_usage_metrics-api-v1-RepoWorkflowRunnerUsageItem)
    - [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions)
    - [RunnerLabel](#actions_usage_metrics-api-v1-RunnerLabel)
    - [RunnerRuntimeUsageItem](#actions_usage_metrics-api-v1-RunnerRuntimeUsageItem)
    - [RunnerTypeUsageItem](#actions_usage_metrics-api-v1-RunnerTypeUsageItem)
    - [Scope](#actions_usage_metrics-api-v1-Scope)
    - [StartExportRequest](#actions_usage_metrics-api-v1-StartExportRequest)
    - [StartExportResponse](#actions_usage_metrics-api-v1-StartExportResponse)
    - [Workflow](#actions_usage_metrics-api-v1-Workflow)
    - [WorkflowPerformanceItem](#actions_usage_metrics-api-v1-WorkflowPerformanceItem)
  
    - [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType)
    - [ExportStatus](#actions_usage_metrics-api-v1-ExportStatus)
    - [ExportType](#actions_usage_metrics-api-v1-ExportType)
    - [FilterOperator](#actions_usage_metrics-api-v1-FilterOperator)
    - [MetricsType](#actions_usage_metrics-api-v1-MetricsType)
    - [OrderByDirection](#actions_usage_metrics-api-v1-OrderByDirection)
    - [RequestType](#actions_usage_metrics-api-v1-RequestType)
    - [RunnerRuntime](#actions_usage_metrics-api-v1-RunnerRuntime)
    - [RunnerType](#actions_usage_metrics-api-v1-RunnerType)
    - [ScopeType](#actions_usage_metrics-api-v1-ScopeType)
  
    - [UsageApi](#actions_usage_metrics-api-v1-UsageApi)
  
- [Scalar Value Types](#scalar-value-types)



<a name="proto_usage-proto"></a>
<p align="right"><a href="#top">Top</a></p>

## proto/usage.proto



<a name="actions_usage_metrics-api-v1-CardinalityField"></a>

### CardinalityField



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| count | [uint64](#uint64) |  |  |
| approximate | [bool](#bool) |  |  |






<a name="actions_usage_metrics-api-v1-DateRange"></a>

### DateRange



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| start | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional |  |
| end | [google.protobuf.Timestamp](#google-protobuf-Timestamp) | optional |  |






<a name="actions_usage_metrics-api-v1-ExportHeader"></a>

### ExportHeader



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| display | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-Filter"></a>

### Filter



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| key | [string](#string) |  |  |
| operator | [FilterOperator](#actions_usage_metrics-api-v1-FilterOperator) |  |  |
| values | [string](#string) | repeated |  |






<a name="actions_usage_metrics-api-v1-GetAutoCompleteRequest"></a>

### GetAutoCompleteRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetAutoCompleteResponse"></a>

### GetAutoCompleteResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [string](#string) | repeated |  |






<a name="actions_usage_metrics-api-v1-GetExportStatusRequest"></a>

### GetExportStatusRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| export_id | [string](#string) |  |  |
| scope | [Scope](#actions_usage_metrics-api-v1-Scope) | optional |  |






<a name="actions_usage_metrics-api-v1-GetExportStatusResponse"></a>

### GetExportStatusResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| status | [ExportStatus](#actions_usage_metrics-api-v1-ExportStatus) |  |  |
| download_url | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-GetJobUsageRequest"></a>

### GetJobUsageRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetJobUsageResponse"></a>

### GetJobUsageResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [JobUsageItem](#actions_usage_metrics-api-v1-JobUsageItem) | repeated |  |
| offset | [uint64](#uint64) |  |  |
| total_items | [uint64](#uint64) |  |  |
| date_range | [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType) |  |  |
| start_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| end_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |






<a name="actions_usage_metrics-api-v1-GetJobsRequest"></a>

### GetJobsRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetJobsResponse"></a>

### GetJobsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| jobs | [Job](#actions_usage_metrics-api-v1-Job) | repeated |  |






<a name="actions_usage_metrics-api-v1-GetOrgUsageRequest"></a>

### GetOrgUsageRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetOrgUsageResponse"></a>

### GetOrgUsageResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [OrgUsageItem](#actions_usage_metrics-api-v1-OrgUsageItem) | repeated |  |
| total_items | [uint64](#uint64) |  |  |
| start_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| end_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |






<a name="actions_usage_metrics-api-v1-GetPerformanceSummaryRequest"></a>

### GetPerformanceSummaryRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |
| metrics_type | [MetricsType](#actions_usage_metrics-api-v1-MetricsType) | optional |  |






<a name="actions_usage_metrics-api-v1-GetPerformanceSummaryResponse"></a>

### GetPerformanceSummaryResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| average_job_run_time | [int64](#int64) |  |  |
| average_job_queue_time | [int64](#int64) |  |  |
| job_failure_rate | [float](#float) |  |  |
| total_failure_minutes | [int64](#int64) |  |  |






<a name="actions_usage_metrics-api-v1-GetRepoUsageRequest"></a>

### GetRepoUsageRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetRepoUsageResponse"></a>

### GetRepoUsageResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [RepoUsageItem](#actions_usage_metrics-api-v1-RepoUsageItem) | repeated |  |
| offset | [uint64](#uint64) |  |  |
| total_items | [uint64](#uint64) |  |  |
| date_range | [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType) |  |  |
| start_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| end_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |






<a name="actions_usage_metrics-api-v1-GetRunnerLabelsRequest"></a>

### GetRunnerLabelsRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetRunnerLabelsResponse"></a>

### GetRunnerLabelsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| runner_labels | [RunnerLabel](#actions_usage_metrics-api-v1-RunnerLabel) | repeated |  |






<a name="actions_usage_metrics-api-v1-GetRunnerRuntimeUsageRequest"></a>

### GetRunnerRuntimeUsageRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetRunnerRuntimeUsageResponse"></a>

### GetRunnerRuntimeUsageResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [RunnerRuntimeUsageItem](#actions_usage_metrics-api-v1-RunnerRuntimeUsageItem) | repeated |  |
| offset | [uint64](#uint64) |  |  |
| total_items | [uint64](#uint64) |  |  |
| date_range | [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType) |  |  |
| start_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| end_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |






<a name="actions_usage_metrics-api-v1-GetRunnerTypeUsageRequest"></a>

### GetRunnerTypeUsageRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetRunnerTypeUsageResponse"></a>

### GetRunnerTypeUsageResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [RunnerTypeUsageItem](#actions_usage_metrics-api-v1-RunnerTypeUsageItem) | repeated |  |
| offset | [uint64](#uint64) |  |  |
| total_items | [uint64](#uint64) |  |  |
| date_range | [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType) |  |  |
| start_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| end_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |






<a name="actions_usage_metrics-api-v1-GetUsageByRepoWorkflowRunnerRequest"></a>

### GetUsageByRepoWorkflowRunnerRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetUsageByRepoWorkflowRunnerResponse"></a>

### GetUsageByRepoWorkflowRunnerResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [RepoWorkflowRunnerUsageItem](#actions_usage_metrics-api-v1-RepoWorkflowRunnerUsageItem) | repeated |  |
| offset | [uint64](#uint64) |  |  |
| total_items | [uint64](#uint64) |  |  |
| date_range | [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType) |  |  |
| start_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| end_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |






<a name="actions_usage_metrics-api-v1-GetUsageSummaryRequest"></a>

### GetUsageSummaryRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |
| metrics_type | [MetricsType](#actions_usage_metrics-api-v1-MetricsType) | optional |  |






<a name="actions_usage_metrics-api-v1-GetUsageSummaryResponse"></a>

### GetUsageSummaryResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| total_minutes | [int64](#int64) |  |  |
| job_executions | [int64](#int64) |  |  |






<a name="actions_usage_metrics-api-v1-GetWorkflowPerformanceRequest"></a>

### GetWorkflowPerformanceRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetWorkflowPerformanceResponse"></a>

### GetWorkflowPerformanceResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| items | [WorkflowPerformanceItem](#actions_usage_metrics-api-v1-WorkflowPerformanceItem) | repeated |  |
| offset | [uint64](#uint64) |  |  |
| total_items | [uint64](#uint64) |  |  |
| date_range | [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType) |  |  |
| start_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |
| end_time | [google.protobuf.Timestamp](#google-protobuf-Timestamp) |  |  |






<a name="actions_usage_metrics-api-v1-GetWorkflowsRequest"></a>

### GetWorkflowsRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) | optional |  |






<a name="actions_usage_metrics-api-v1-GetWorkflowsResponse"></a>

### GetWorkflowsResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| workflows | [Workflow](#actions_usage_metrics-api-v1-Workflow) | repeated |  |






<a name="actions_usage_metrics-api-v1-Job"></a>

### Job



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| job_name | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-JobUsageItem"></a>

### JobUsageItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository_id | [int64](#int64) |  |  |
| workflow_file_path | [string](#string) |  |  |
| job_user_identifier | [string](#string) |  |  |
| job_name | [string](#string) |  |  |
| runner_type | [RunnerType](#actions_usage_metrics-api-v1-RunnerType) |  |  |
| runner_runtime | [RunnerRuntime](#actions_usage_metrics-api-v1-RunnerRuntime) |  |  |
| total_minutes | [int64](#int64) |  |  |
| job_executions | [int64](#int64) |  |  |
| average_run_time | [uint64](#uint64) |  |  |
| average_queue_time | [uint64](#uint64) |  |  |
| failure_rate | [float](#float) |  |  |
| owner_id | [int64](#int64) |  |  |
| runner_labels | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-OrderBy"></a>

### OrderBy



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| field | [string](#string) |  |  |
| direction | [OrderByDirection](#actions_usage_metrics-api-v1-OrderByDirection) |  |  |






<a name="actions_usage_metrics-api-v1-OrgUsageItem"></a>

### OrgUsageItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| owner_id | [int64](#int64) |  |  |
| total_minutes | [int64](#int64) |  |  |
| workflow_executions | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| workflows | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| average_run_time | [uint64](#uint64) |  |  |
| average_queue_time | [uint64](#uint64) |  |  |
| failure_rate | [float](#float) |  |  |
| job_executions | [int64](#int64) |  |  |






<a name="actions_usage_metrics-api-v1-ProjectionOptions"></a>

### ProjectionOptions



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| version_override | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-RepoUsageItem"></a>

### RepoUsageItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository_id | [int64](#int64) |  |  |
| total_minutes | [int64](#int64) |  |  |
| workflow_executions | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| workflows | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| average_run_time | [uint64](#uint64) |  |  |
| average_queue_time | [uint64](#uint64) |  |  |
| failure_rate | [float](#float) |  |  |
| job_executions | [int64](#int64) |  |  |
| owner_id | [int64](#int64) |  |  |






<a name="actions_usage_metrics-api-v1-RepoWorkflowRunnerUsageItem"></a>

### RepoWorkflowRunnerUsageItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository_id | [int64](#int64) |  |  |
| workflow_file_path | [string](#string) |  |  |
| runner_type | [RunnerType](#actions_usage_metrics-api-v1-RunnerType) |  |  |
| runner_runtime | [RunnerRuntime](#actions_usage_metrics-api-v1-RunnerRuntime) |  |  |
| total_minutes | [int64](#int64) |  |  |
| workflow_executions | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| jobs | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| owner_id | [int64](#int64) |  |  |






<a name="actions_usage_metrics-api-v1-RequestOptions"></a>

### RequestOptions



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| offset | [uint64](#uint64) | optional |  |
| limit | [uint64](#uint64) | optional |  |
| date_range | [DateRangeType](#actions_usage_metrics-api-v1-DateRangeType) | optional |  |
| filters | [Filter](#actions_usage_metrics-api-v1-Filter) | repeated |  |
| search | [string](#string) | optional |  |
| projection_options | [ProjectionOptions](#actions_usage_metrics-api-v1-ProjectionOptions) | optional |  |
| order_by | [OrderBy](#actions_usage_metrics-api-v1-OrderBy) | optional |  |
| search_field | [string](#string) | optional |  |
| request_type | [RequestType](#actions_usage_metrics-api-v1-RequestType) | optional |  |
| scope | [Scope](#actions_usage_metrics-api-v1-Scope) | optional |  |
| custom_date_range | [DateRange](#actions_usage_metrics-api-v1-DateRange) | optional |  |






<a name="actions_usage_metrics-api-v1-RunnerLabel"></a>

### RunnerLabel



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| runner_label | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-RunnerRuntimeUsageItem"></a>

### RunnerRuntimeUsageItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| runner_runtime | [RunnerRuntime](#actions_usage_metrics-api-v1-RunnerRuntime) |  |  |
| total_minutes | [int64](#int64) |  |  |
| workflow_executions | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| workflows | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| average_run_time | [uint64](#uint64) |  |  |
| average_queue_time | [uint64](#uint64) |  |  |
| failure_rate | [float](#float) |  |  |
| job_executions | [int64](#int64) |  |  |






<a name="actions_usage_metrics-api-v1-RunnerTypeUsageItem"></a>

### RunnerTypeUsageItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| runner_type | [RunnerType](#actions_usage_metrics-api-v1-RunnerType) |  |  |
| total_minutes | [int64](#int64) |  |  |
| workflow_executions | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| workflows | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| average_run_time | [uint64](#uint64) |  |  |
| average_queue_time | [uint64](#uint64) |  |  |
| failure_rate | [float](#float) |  |  |
| job_executions | [int64](#int64) |  |  |






<a name="actions_usage_metrics-api-v1-Scope"></a>

### Scope



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| owner_id | [int64](#int64) | optional |  |
| repository_id | [int64](#int64) | optional |  |
| enterprise_orgs | [int64](#int64) | repeated |  |
| scope_type | [ScopeType](#actions_usage_metrics-api-v1-ScopeType) |  |  |
| hash | [string](#string) | optional |  |
| enterprise_id | [int64](#int64) | optional |  |






<a name="actions_usage_metrics-api-v1-StartExportRequest"></a>

### StartExportRequest



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| request_options | [RequestOptions](#actions_usage_metrics-api-v1-RequestOptions) |  |  |
| export_type | [ExportType](#actions_usage_metrics-api-v1-ExportType) |  |  |
| headers | [ExportHeader](#actions_usage_metrics-api-v1-ExportHeader) | repeated |  |






<a name="actions_usage_metrics-api-v1-StartExportResponse"></a>

### StartExportResponse



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| export_id | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-Workflow"></a>

### Workflow



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| file_name | [string](#string) |  |  |






<a name="actions_usage_metrics-api-v1-WorkflowPerformanceItem"></a>

### WorkflowPerformanceItem



| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository_id | [int64](#int64) |  |  |
| workflow_file_path | [string](#string) |  |  |
| jobs | [CardinalityField](#actions_usage_metrics-api-v1-CardinalityField) |  |  |
| workflow_executions | [uint64](#uint64) |  |  |
| average_run_time | [uint64](#uint64) |  |  |
| failure_rate | [float](#float) |  |  |
| owner_id | [int64](#int64) |  |  |





 


<a name="actions_usage_metrics-api-v1-DateRangeType"></a>

### DateRangeType


| Name | Number | Description |
| ---- | ------ | ----------- |
| DATE_RANGE_TYPE_UNKNOWN | 0 |  |
| DATE_RANGE_TYPE_LATEST_MONTH | 1 |  |
| DATE_RANGE_TYPE_PREVIOUS_MONTH | 2 |  |
| DATE_RANGE_TYPE_CURRENT_WEEK | 3 |  |
| DATE_RANGE_TYPE_LAST_30_DAYS | 4 |  |
| DATE_RANGE_TYPE_LAST_90_DAYS | 5 |  |
| DATE_RANGE_TYPE_LAST_YEAR | 6 |  |
| DATE_RANGE_TYPE_CUSTOM | 7 |  |



<a name="actions_usage_metrics-api-v1-ExportStatus"></a>

### ExportStatus


| Name | Number | Description |
| ---- | ------ | ----------- |
| EXPORT_STATUS_UNKNOWN | 0 |  |
| EXPORT_STATUS_PENDING | 1 |  |
| EXPORT_STATUS_COMPLETE | 2 |  |
| EXPORT_STATUS_FAILED | 3 |  |



<a name="actions_usage_metrics-api-v1-ExportType"></a>

### ExportType


| Name | Number | Description |
| ---- | ------ | ----------- |
| EXPORT_TYPE_UNKNOWN | 0 |  |
| EXPORT_TYPE_JOB_USAGE | 1 |  |
| EXPORT_TYPE_REPO_USAGE | 2 |  |
| EXPORT_TYPE_RUNNER_RUNTIME_USAGE | 3 |  |
| EXPORT_TYPE_RUNNER_TYPE_USAGE | 4 |  |
| EXPORT_TYPE_WORKFLOW_USAGE | 5 |  |
| EXPORT_TYPE_WORKFLOW_PERFORMANCE | 6 |  |
| EXPORT_TYPE_ORG_USAGE | 7 |  |



<a name="actions_usage_metrics-api-v1-FilterOperator"></a>

### FilterOperator


| Name | Number | Description |
| ---- | ------ | ----------- |
| FILTER_OPERATOR_UNKNOWN | 0 |  |
| FILTER_OPERATOR_EQUALS | 1 |  |
| FILTER_OPERATOR_NOT_EQUALS | 2 |  |
| FILTER_OPERATOR_CONTAINS | 3 |  |
| FILTER_OPERATOR_GREATER_THAN | 4 |  |
| FILTER_OPERATOR_LESS_THAN | 5 |  |
| FILTER_OPERATOR_GREATER_THAN_OR_EQUAL | 6 |  |
| FILTER_OPERATOR_LESS_THAN_OR_EQUAL | 7 |  |
| FILTER_OPERATOR_BETWEEN | 8 |  |
| FILTER_OPERATOR_LIST_CONTAINS | 9 | e.g column value in kusto is [&#34;label1&#34;, &#34;label2&#34;] |
| FILTER_OPERATOR_NOT_LIST_CONTAINS | 10 | e.g column value in kusto is [&#34;label1&#34;, &#34;label2&#34;] |



<a name="actions_usage_metrics-api-v1-MetricsType"></a>

### MetricsType


| Name | Number | Description |
| ---- | ------ | ----------- |
| METRICS_TYPE_UNKNOWN | 0 |  |
| METRICS_TYPE_JOB | 1 |  |
| METRICS_TYPE_REPO | 2 |  |
| METRICS_TYPE_RUNNER_RUNTIME | 3 |  |
| METRICS_TYPE_RUNNER_TYPE | 4 |  |
| METRICS_TYPE_WORKFLOW | 5 |  |
| METRICS_TYPE_ORG | 6 |  |



<a name="actions_usage_metrics-api-v1-OrderByDirection"></a>

### OrderByDirection


| Name | Number | Description |
| ---- | ------ | ----------- |
| ORDER_BY_DIRECTION_UNKNOWN | 0 |  |
| ORDER_BY_DIRECTION_ASC | 1 |  |
| ORDER_BY_DIRECTION_DESC | 2 |  |



<a name="actions_usage_metrics-api-v1-RequestType"></a>

### RequestType


| Name | Number | Description |
| ---- | ------ | ----------- |
| REQUEST_TYPE_UNKNOWN | 0 |  |
| REQUEST_TYPE_USAGE | 1 |  |
| REQUEST_TYPE_PERFORMANCE | 2 |  |



<a name="actions_usage_metrics-api-v1-RunnerRuntime"></a>

### RunnerRuntime


| Name | Number | Description |
| ---- | ------ | ----------- |
| RUNNER_RUNTIME_UNKNOWN | 0 |  |
| RUNNER_RUNTIME_LINUX | 1 |  |
| RUNNER_RUNTIME_WINDOWS | 2 |  |
| RUNNER_RUNTIME_MACOS | 3 |  |



<a name="actions_usage_metrics-api-v1-RunnerType"></a>

### RunnerType


| Name | Number | Description |
| ---- | ------ | ----------- |
| RUNNER_TYPE_UNKNOWN | 0 |  |
| RUNNER_TYPE_SELF_HOSTED | 1 |  |
| RUNNER_TYPE_HOSTED | 2 |  |
| RUNNER_TYPE_HOSTED_LARGER | 3 |  |



<a name="actions_usage_metrics-api-v1-ScopeType"></a>

### ScopeType


| Name | Number | Description |
| ---- | ------ | ----------- |
| SCOPE_TYPE_UNKNOWN | 0 |  |
| SCOPE_TYPE_ORG | 1 |  |
| SCOPE_TYPE_REPO | 2 |  |
| SCOPE_TYPE_ENTERPRISE | 3 |  |


 

 


<a name="actions_usage_metrics-api-v1-UsageApi"></a>

### UsageApi


| Method Name | Request Type | Response Type | Description |
| ----------- | ------------ | ------------- | ------------|
| GetUsageByRepoWorkflowRunner | [GetUsageByRepoWorkflowRunnerRequest](#actions_usage_metrics-api-v1-GetUsageByRepoWorkflowRunnerRequest) | [GetUsageByRepoWorkflowRunnerResponse](#actions_usage_metrics-api-v1-GetUsageByRepoWorkflowRunnerResponse) |  |
| GetWorkflowPerformance | [GetWorkflowPerformanceRequest](#actions_usage_metrics-api-v1-GetWorkflowPerformanceRequest) | [GetWorkflowPerformanceResponse](#actions_usage_metrics-api-v1-GetWorkflowPerformanceResponse) |  |
| GetJobUsage | [GetJobUsageRequest](#actions_usage_metrics-api-v1-GetJobUsageRequest) | [GetJobUsageResponse](#actions_usage_metrics-api-v1-GetJobUsageResponse) |  |
| GetRepoUsage | [GetRepoUsageRequest](#actions_usage_metrics-api-v1-GetRepoUsageRequest) | [GetRepoUsageResponse](#actions_usage_metrics-api-v1-GetRepoUsageResponse) |  |
| GetOrgUsage | [GetOrgUsageRequest](#actions_usage_metrics-api-v1-GetOrgUsageRequest) | [GetOrgUsageResponse](#actions_usage_metrics-api-v1-GetOrgUsageResponse) |  |
| GetRunnerRuntimeUsage | [GetRunnerRuntimeUsageRequest](#actions_usage_metrics-api-v1-GetRunnerRuntimeUsageRequest) | [GetRunnerRuntimeUsageResponse](#actions_usage_metrics-api-v1-GetRunnerRuntimeUsageResponse) |  |
| GetRunnerTypeUsage | [GetRunnerTypeUsageRequest](#actions_usage_metrics-api-v1-GetRunnerTypeUsageRequest) | [GetRunnerTypeUsageResponse](#actions_usage_metrics-api-v1-GetRunnerTypeUsageResponse) |  |
| GetWorkflows | [GetWorkflowsRequest](#actions_usage_metrics-api-v1-GetWorkflowsRequest) | [GetWorkflowsResponse](#actions_usage_metrics-api-v1-GetWorkflowsResponse) |  |
| GetJobs | [GetJobsRequest](#actions_usage_metrics-api-v1-GetJobsRequest) | [GetJobsResponse](#actions_usage_metrics-api-v1-GetJobsResponse) |  |
| GetRunnerLabels | [GetRunnerLabelsRequest](#actions_usage_metrics-api-v1-GetRunnerLabelsRequest) | [GetRunnerLabelsResponse](#actions_usage_metrics-api-v1-GetRunnerLabelsResponse) |  |
| GetUsageSummary | [GetUsageSummaryRequest](#actions_usage_metrics-api-v1-GetUsageSummaryRequest) | [GetUsageSummaryResponse](#actions_usage_metrics-api-v1-GetUsageSummaryResponse) |  |
| GetPerformanceSummary | [GetPerformanceSummaryRequest](#actions_usage_metrics-api-v1-GetPerformanceSummaryRequest) | [GetPerformanceSummaryResponse](#actions_usage_metrics-api-v1-GetPerformanceSummaryResponse) |  |
| StartExport | [StartExportRequest](#actions_usage_metrics-api-v1-StartExportRequest) | [StartExportResponse](#actions_usage_metrics-api-v1-StartExportResponse) |  |
| GetExportStatus | [GetExportStatusRequest](#actions_usage_metrics-api-v1-GetExportStatusRequest) | [GetExportStatusResponse](#actions_usage_metrics-api-v1-GetExportStatusResponse) |  |

 



## Scalar Value Types

| .proto Type | Notes | C++ | Java | Python | Go | C# | PHP | Ruby |
| ----------- | ----- | --- | ---- | ------ | -- | -- | --- | ---- |
| <a name="double" /> double |  | double | double | float | float64 | double | float | Float |
| <a name="float" /> float |  | float | float | float | float32 | float | float | Float |
| <a name="int32" /> int32 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint32 instead. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="int64" /> int64 | Uses variable-length encoding. Inefficient for encoding negative numbers – if your field is likely to have negative values, use sint64 instead. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="uint32" /> uint32 | Uses variable-length encoding. | uint32 | int | int/long | uint32 | uint | integer | Bignum or Fixnum (as required) |
| <a name="uint64" /> uint64 | Uses variable-length encoding. | uint64 | long | int/long | uint64 | ulong | integer/string | Bignum or Fixnum (as required) |
| <a name="sint32" /> sint32 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int32s. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="sint64" /> sint64 | Uses variable-length encoding. Signed int value. These more efficiently encode negative numbers than regular int64s. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="fixed32" /> fixed32 | Always four bytes. More efficient than uint32 if values are often greater than 2^28. | uint32 | int | int | uint32 | uint | integer | Bignum or Fixnum (as required) |
| <a name="fixed64" /> fixed64 | Always eight bytes. More efficient than uint64 if values are often greater than 2^56. | uint64 | long | int/long | uint64 | ulong | integer/string | Bignum |
| <a name="sfixed32" /> sfixed32 | Always four bytes. | int32 | int | int | int32 | int | integer | Bignum or Fixnum (as required) |
| <a name="sfixed64" /> sfixed64 | Always eight bytes. | int64 | long | int/long | int64 | long | integer/string | Bignum |
| <a name="bool" /> bool |  | bool | boolean | boolean | bool | bool | boolean | TrueClass/FalseClass |
| <a name="string" /> string | A string must always contain UTF-8 encoded or 7-bit ASCII text. | string | String | str/unicode | string | string | string | String (UTF-8) |
| <a name="bytes" /> bytes | May contain any arbitrary sequence of bytes. | string | ByteString | str | []byte | ByteString | string | String (ASCII-8BIT) |

