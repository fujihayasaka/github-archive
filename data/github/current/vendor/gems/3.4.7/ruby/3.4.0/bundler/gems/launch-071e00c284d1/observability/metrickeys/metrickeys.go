// A package to define metric keys for consistency and ease of reference. Place constants
// in file appropriate to their usage (tags in tags*.go etc).
package metrickeys

// ExternalAPI for metrics over external APIs
const ExternalAPI = "external_api"

// HTTPResult is used for counters over the result of an HTTP request, which are either status codes or NonHTTPError
const HTTPResult = "http_result"

// ResponseTime is used for response times, in milliseconds unless otherwise specified
const ResponseTime = "response_time"

// UserSyntaxError counts how many times we get a workflow-file syntax error
const UserSyntaxError = "user_syntax_error"

// RerunPlanNotFoundError counts how many times we get a rerun plan not found error
const RerunPlanNotFoundError = "rerun_plan_not_found_error"

// TooManyBuildsError counts how often builds cannot be run because Actions Service does not queue them due to too many requests
const TooManyBuildsError = "too_many_builds_error"

// DeadlockRetry counts how many times we retry a deadlocked operation
const DeadlockRetry = "deadlock_retry"

// ServerShutdownRetry counts how many times we retry an operation due to a Server Shutdown (1053) error
const ServerShutdownRetry = "server_shutdown_retry"

// PaginationRequired records a result that requires pagination, in places we didn't support it
const PaginationRequired = "pagination_required"

// WorkflowCreated records when a user pushes something that has the effect of increasing the number of workflow
// files on a branch
const WorkflowCreated = "workflow_created"

// WorkflowDiffAdvisory records a reason a workflow diff filter couldn't run normally
const WorkflowDiffAdvisory = "workflow_diff_advisory"

// SingleGlobTimeout records when we timeout a single glob/path pair
const SingleGlobTimeout = "single_glob_time"

// AggregateDiffGlobTimeout records when we timeout running all globs vs all paths
const AggregateDiffGlobTimeout = "whole_diff_glob_time"

// HTTPRoute is used for tagging the route of HTTP endpoints.
const HTTPRoute = "route"

// HydroEventsQueued records the buffer of unsent hydro messages from our emitter
const HydroEventsQueued = "hydro_events_queued"

// MySQLRetries records the number of time a query was retried
const MySQLRetries = "mysql_retries"

// WorkflowsCancelAll records the number of workflows when attempted to cancel all
const WorkflowsCancelAll = "workflows_cancel_all"

// ReportAdminEvent records everytime we report admin event to Actions Service
const ReportAdminEvent = "report_admin_event"

// WorkflowCallDepthLimitError records when calling workflows exceeds the max depth
const WorkflowCallDepthLimitError = "workflow_call_depth_limit_error"

// WorkflowFilesReferencedLimitError records when number of referenced workflows exceeds the limit
const WorkflowFilesReferencedLimitError = "workflow_files_referenced_limit_error"

// WorkflowFilesReferenced records the number of workflows referenced from caller workflow
const WorkflowFilesReferenced = "workflow_files_referenced"

// ReusableWorkflowSecretsInherit records the number of workflow calls using secrets inherit
const ReusableWorkflowSecretsInherit = "reusable_workflows_secrets_inherit"

// CallableWorkflowsRefs records the number of local and remote called workflows within a workflow run
const CallableWorkflowsRefs = "callable_workflows_refs"

// CallableWorkflowRuns records when a workflow run is queued regardless of using callable workflows or not
const CallableWorkflowRuns = "callable_workflow_runs"

// NestedWorkflowsCallDepth records the call depth in a workflow run
const NestedWorkflowsCallDepth = "nested_workflows_call_depth"

// CallerWorkflowAuthzdAccess records the caller workflow authzd access denied
const CallerWorkflowAuthzdAccess = "caller_workflow_authzd_access"
