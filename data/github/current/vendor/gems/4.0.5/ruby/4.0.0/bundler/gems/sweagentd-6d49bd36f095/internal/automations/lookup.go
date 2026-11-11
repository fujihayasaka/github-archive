// Package automations defines the runtime lookup seam for triggered CCA
// automations.
package automations

import (
	"context"

	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// EventName identifies the repository event namespace used for automation
// matching.
type EventName string

const (
	// EventIssues is the GitHub issues event namespace.
	EventIssues EventName = "issues"
	// EventInterval identifies time-driven automations.
	EventInterval EventName = "interval"
	// EventWorkflowRun is the GitHub Actions workflow_run event namespace.
	EventWorkflowRun EventName = "workflow_run"
	// EventPullRequest is the GitHub pull_request event namespace.
	EventPullRequest EventName = "pull_request"
	// EventPullRequestOpened is the CMC catalog event name for pull_request.opened automations.
	EventPullRequestOpened EventName = "pull_request_opened"
	// EventPullRequestSynchronize is the CMC catalog event name for pull_request.synchronize automations.
	EventPullRequestSynchronize EventName = "pull_request_synchronize"
	// EventPullRequestMerged is the CMC catalog event name for pull_request.merged automations.
	EventPullRequestMerged EventName = "pull_request_merged"
	// EventManual identifies user-initiated runs with no event context.
	EventManual EventName = "manual"
)

const (
	// ActivityIssueOpened matches issues.opened events.
	ActivityIssueOpened = "opened"
	// ActivityWorkflowRunCompleted matches workflow_run.completed events.
	ActivityWorkflowRunCompleted = "completed"
	// ActivityWorkflowRunFailed matches the legacy workflow_run failed trigger.
	ActivityWorkflowRunFailed = "failed"
	// ActivityPullRequestOpened matches pull_request.opened events.
	ActivityPullRequestOpened = "opened"
	// ActivityPullRequestMerged matches pull_request.merged events.
	ActivityPullRequestMerged = "merged"
	// ActivityPullRequestSynchronize matches pull_request.synchronize events.
	ActivityPullRequestSynchronize = "synchronize"
)

// WorkflowConclusion identifies a completed workflow run's conclusion.
type WorkflowConclusion string

const (
	// WorkflowConclusionFailure matches failed workflow run conclusions.
	WorkflowConclusionFailure WorkflowConclusion = "failure"
)

// EventMatchRequest describes the repository event query used to find matching
// automations.
type EventMatchRequest struct {
	OwnerID            int64
	RepoID             int64
	EventName          EventName
	ActivityType       string
	WorkflowName       string
	WorkflowConclusion WorkflowConclusion
}

// RepoInfo provides repository names needed to construct legacy custom-agent
// runtime configuration. Automation lookup itself is based on owner/repo IDs.
type RepoInfo struct {
	OwnerLogin string
	RepoName   string
}

// ListForEventRequest describes the repository event and any additional
// metadata needed to construct launch-time runtime configuration.
type ListForEventRequest struct {
	Event EventMatchRequest
	Repo  RepoInfo

	// AutomationID, when set, restricts the lookup to a single automation by ID.
	// This is used for on-demand automation run requests where the caller already
	// knows which automation to execute. When set, trigger matching is skipped.
	AutomationID string
}

// RuntimeConfig is the launch-time configuration for a matched automation.
// Today this is backed by a custom agent; CMC-backed automations will fill this
// from first-class automation records.
type RuntimeConfig struct {
	CustomAgent sweagentd.CustomAgent

	AutomationID string
	// AutomationOwnerID is the GitHub user ID that owns the automation.
	AutomationOwnerID           int64
	RequireActorWritePermission bool
}

// Lookup finds active automations for repository events.
type Lookup interface {
	HasActiveForEvent(ctx context.Context, req EventMatchRequest) (bool, error)
	ListForEvent(ctx context.Context, req ListForEventRequest) ([]RuntimeConfig, error)
	AutomationsDisabledFromConfig(ctx context.Context, cfg *sweagentdtwirp.ConfigurationForRepositoryResponse, repoID int64, triggerType string) bool
}
