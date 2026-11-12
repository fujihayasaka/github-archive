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
	// PullRequestClose fires when the actor closed a pull request without merging
	PullRequestClose string = "cp1-iad.ingest.github.v1.PullRequestClose"
	// PullRequestMerge fires when the actor merged a pull request
	PullRequestMerge string = "cp1-iad.ingest.github.v1.PullRequestMerge"
	// CodeScanningAlertAssignment fires when one or more alerts are assigned
	// to Copilot from code scanning security campaigns.
	CodeScanningAlertAssignment string = "code_scanning.v0.AlertsAssignment"
	// IssueCreateTemplate fires when an issue in a repo is created
	IssueCreateTemplate string = "cp1-iad.ingest.github.v1.IssueCreateTemplate"

	// PullRequestMergeConflict fires when a merge conflict is detected on a pull request
	PullRequestMergeConflict string = "github.pull_requests.v1.MergeConflict"

	// PullRequestCreate fires when the actor opens a pull request.
	// Used to evaluate pull_request.opened automation triggers.
	PullRequestCreate string = "cp1-iad.ingest.github.v1.PullRequestCreate"

	// AutomationRunRequested fires when a user requests an automation run from copilot-mission-control.
	AutomationRunRequested string = "copilot_mission_control.v0.AutomationRunRequested"

	// PullRequestSynchronize fires when commits are pushed to a pull request branch.
	// Used to evaluate pull_request.synchronize automation triggers.
	PullRequestSynchronize string = "github.v1.PullRequestSynchronize"

	// AgentsUpdated fires when files in .github/agents change in a repository
	AgentsUpdated string = "sweagentd.v1.AgentsUpdated"
	// AutomationLifecycleChanged fires when copilot-mission-control creates,
	// updates, enables, disables, or deletes a CCA automation.
	AutomationLifecycleChanged string = "copilot_mission_control.v0.AutomationLifecycleChanged"
	// IntegrationCreate fires when a GitHub App (integration) is created
	IntegrationCreate string = "cp1-iad.ingest.github.v1.IntegrationCreate"
	// IntegrationUpdate fires when a GitHub App (integration) is updated
	IntegrationUpdate string = "github.v1.IntegrationUpdate"
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
	PullRequestClose,
	PullRequestMerge,
	CodeScanningAlertAssignment,
}

// Worker contains all topics that the sweagentd worker processes.
//
// IMPORTANT: Topics should only be included in Service OR Worker, not both.
// New topics should be added to Worker. Topics currently in Service will be
// gradually migrated to Worker over time.
//
// EXCEPTION: WorkflowRunExecution appears in both Service and Worker because it
// serves two distinct purposes: the Service handles agent run completions (job
// finalization) while the Worker handles workflow_run trigger evaluation for
// custom agents. The shouldProcessEvent filter ensures each consumer only
// processes its intended subset via the event's Kind field.
//
// EXCEPTION: PullRequestMerge is dual-listed; Service cancels running jobs on merge, Worker fires pull_request.merged triggers (split via shouldProcessEvent).
var Worker = []string{
	IssueCreateTemplate,
	PullRequestCreate,
	PullRequestMerge,
	PullRequestMergeConflict,
	PullRequestSynchronize,
	WorkflowRunExecution,
	AutomationRunRequested,
}

// Sync contains all topics that the agent config sync consumer processes.
//
// IMPORTANT: Sync topics are processed by a separate Hydro consumer from
// Service and Worker topics. They bypass the standard dispatcher pipeline.
var Sync = []string{
	AgentsUpdated,
}

// All contains all topics that the sweagentd service and worker process via the dispatcher.
// Sync topics are NOT included here as they are handled by a separate consumer.
var All = dedupTopics(append(Service, Worker...))

// dedupTopics removes duplicate topic strings from the slice.
func dedupTopics(topics []string) []string {
	seen := make(map[string]bool, len(topics))
	result := make([]string, 0, len(topics))
	for _, t := range topics {
		if !seen[t] {
			seen[t] = true
			result = append(result, t)
		}
	}
	return result
}
