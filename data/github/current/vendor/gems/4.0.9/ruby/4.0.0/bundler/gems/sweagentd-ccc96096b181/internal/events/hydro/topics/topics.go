// Package topics defines the Hydro event topics used within the sweagentd service.
package topics

// Hydro topics can be found and verified at
// https://github.com/github/hydro-schemas/blob/main/topic-configuration/production/potomac/github.yaml

const (
	// WorkflowRunExecution fires when a workflow run is executed
	WorkflowRunExecution string = "github.actions.v0.WorkflowRunExecution"
	// PullRequestTimelineCommentCreate fires when the actor creates a comment on
	// a pull request timeline
	PullRequestTimelineCommentCreate string = "github.v1.PullRequestTimelineCommentCreate"
	// PullRequestReviewSubmit fires when the actor submits a review on a pull request
	PullRequestReviewSubmit string = "cp1-iad.ingest.github.v1.PullRequestReviewSubmit"
	// PullRequestReopen fires when the actor reopened a closed pull request
	PullRequestReopen string = "cp1-iad.ingest.github.v1.PullRequestReopen"
	// PullRequestClose fires when the actor closed a pull request without merging
	PullRequestClose string = "cp1-iad.ingest.github.v1.PullRequestClose"
	// PullRequestMerge fires when the actor merged a pull request
	PullRequestMerge string = "cp1-iad.ingest.github.v1.PullRequestMerge"
	// CodeScanningAlertAssignment fires when one or more alerts are assigned
	// to Copilot from code scanning security campaigns.
	CodeScanningAlertAssignment string = "code_scanning.v0.AlertsAssignment"
	// IssueCreateTemplate fires when an issue in a repo is created
	IssueCreateTemplate string = "cp1-iad.ingest.github.v1.IssueCreateTemplate"
)

// Service contains all topics that the sweagentd service processes.
//
// IMPORTANT: Topics should only be included in Service OR Worker, not both.
// New topics should be added to Worker. Topics currently in Service will be
// gradually migrated to Worker over time.
var Service = []string{
	WorkflowRunExecution,
	PullRequestTimelineCommentCreate,
	PullRequestReviewSubmit,
	PullRequestReopen,
	PullRequestClose,
	PullRequestMerge,
	CodeScanningAlertAssignment,
}

// Worker contains all topics that the sweagentd worker processes.
//
// IMPORTANT: Topics should only be included in Service OR Worker, not both.
// New topics should be added to Worker. Topics currently in Service will be
// gradually migrated to Worker over time.
var Worker = []string{
	IssueCreateTemplate,
}

// All contains all topics that the sweagentd service and worker process.
var All = append(Service, Worker...)

// PullRequestStateChanged contains topics related to pull request state changes.
// These are currently used to update the state of associated Sessions, but will
// be handled by the sessions service in the near future.
var PullRequestStateChanged = []string{
	PullRequestReopen,
	PullRequestClose,
	PullRequestMerge,
}
