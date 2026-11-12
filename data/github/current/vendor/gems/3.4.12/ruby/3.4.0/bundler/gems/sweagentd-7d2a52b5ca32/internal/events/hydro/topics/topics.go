package topics

// Hydro topics can be found and verified at
// https://github.com/github/hydro-schemas/blob/main/topic-configuration/production/potomac/github.yaml

const (
	ComputeUsage                     string = "github.actions.v0.ComputeUsage"
	WorkflowRunExecution             string = "github.actions.v0.WorkflowRunExecution"
	IssueUpdateAssignee              string = "github.v1.IssueUpdateAssignee"
	PullRequestTimelineCommentCreate string = "github.v1.PullRequestTimelineCommentCreate"
	PullRequestReviewSubmit          string = "cp1-iad.ingest.github.v1.PullRequestReviewSubmit"
	PullRequestReopen                string = "cp1-iad.ingest.github.v1.PullRequestReopen"
	PullRequestClose                 string = "cp1-iad.ingest.github.v1.PullRequestClose"
	PullRequestMerge                 string = "cp1-iad.ingest.github.v1.PullRequestMerge"
	CodeScanningAlertAssignment      string = "code_scanning.v0.AlertsAssignment"
)

var All = []string{
	ComputeUsage,
	WorkflowRunExecution,
	IssueUpdateAssignee,
	PullRequestTimelineCommentCreate,
	PullRequestReviewSubmit,
	PullRequestReopen,
	PullRequestClose,
	PullRequestMerge,
	CodeScanningAlertAssignment,
}

var PullRequestStateChanged = []string{
	PullRequestReopen,
	PullRequestClose,
	PullRequestMerge,
}
