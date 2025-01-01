package types

import "time"

// PartialAbuseTriggerInfo context required by MMS to make decisions about abusive builds. Partial is required as we want to determine this
// in workflow_invoker and won't know about workflow execution ID, workflow file path, and repoTier until later in the process.
// Documentation: https://github.com/github/c2c-actions-abuse/blob/main/Signals.md
type PartialAbuseTriggerInfo struct {
	TriggerEvent       string                  `json:"triggerEvent"`
	TriggerEventAction string                  `json:"triggerEventAction"`
	Actor              *ActionsAbuseUser       `json:"actor,omitempty"`
	TargetRepoOwner    *ActionsAbuseUser       `json:"targetRepoOwner,omitempty"`
	HeadRepoOwner      *ActionsAbuseUser       `json:"headRepoOwner,omitempty"`
	BillingPlanOwner   *ActionsAbuseUser       `json:"billingPlanOwner,omitempty"`
	TargetRepository   *ActionsAbuseRepository `json:"targetRepository,omitempty"`
	HeadRepository     *ActionsAbuseRepository `json:"headRepository,omitempty"`
}

// ActionsAbuseTriggerInfo context required by MMS to make decisions about abusive builds
// Documentation: https://github.com/github/c2c-actions-abuse/blob/main/Signals.md
type ActionsAbuseTriggerInfo struct {
	// Keep this struct in sync with MMS's ActionsAbuseTriggerInfo class. https://dev.azure.com/mseng/AzureDevOps/_git/AzDevNext?path=%2FMms%2FClient%2FWebApi%2FActionsAbuseTriggerInfo.cs
	WorkflowExecutionID string `json:"workflowExecutionId"`
	WorkflowFilePath    string `json:"workflowFilePath"`

	// The database ID of the run in the `workflow_runs` table
	WorkflowRunID int64 `json:"workflowRunId"`

	// WorkflowJobId intentionally skipped - populated by MMS
	TargetRepositoryTier int `json:"targetRepositoryTier"`
	PartialAbuseTriggerInfo
}

// ActionsAbuseUser context about Actors (Users, Orgs, Enterprises) required by MMS to make decisions about abusive builds
// Documentation: https://github.com/github/c2c-actions-abuse/blob/main/Signals.md
type ActionsAbuseUser struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Type      string    `json:"type"`
	Plan      string    `json:"plan"`
	CreatedAt time.Time `json:"createdAt"`
	IsHammy   bool      `json:"isHammy"`
}

// ActionsAbuseRepository context about Repositories required by MMS to make decisions about abusive builds
// Documentation: https://github.com/github/c2c-actions-abuse/blob/main/Signals.md
type ActionsAbuseRepository struct {
	ID         string    `json:"id"`
	DatabaseID int64     `json:"databaseId"`
	Private    bool      `json:"private"`
	NWO        string    `json:"nwo"`
	CreatedAt  time.Time `json:"createdAt"`
}
