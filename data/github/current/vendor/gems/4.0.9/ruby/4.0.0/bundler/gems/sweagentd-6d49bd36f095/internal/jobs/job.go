package jobs

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"strconv"
	"strings"

	"errors"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/google/uuid"
)

// randReader is the source of cryptographic randomness used for nonce generation.
// It is a package-level variable to allow replacement in tests.
var randReader = rand.Reader

// JobNonceHeader is the header used to pass the nonce to the agent when the
// job is created. The agent will use this nonce to validate that the callback
// request comes from the right workflow run.
const JobNonceHeader = "X-GitHub-Job-Nonce"

// EventType represents the type of event that triggered the job.
type EventType string

const (
	// EventTypeIssueCreated represents an issue created event.
	EventTypeIssueCreated EventType = "issue_created"
	// EventTypeIssueAssignment represents an issue assignment event.
	EventTypeIssueAssignment EventType = "issue_assignment"
	// EventTypePullRequestComment represents a pull request comment event.
	EventTypePullRequestComment EventType = "pull_request_comment"
	// EventTypePullRequestCommentNonCopilotPullRequest represents a pull request
	// comment event on a non-Copilot pull request.
	EventTypePullRequestCommentNonCopilotPullRequest EventType = "pull_request_comment_non_copilot_pull_request"
	// EventTypePullRequestReview represents a pull request review event.
	EventTypePullRequestReview EventType = "pull_request_review"
	// EventTypePullRequestReviewNonCopilotPullRequest represents a pull request
	// review event on a non-Copilot pull request.
	EventTypePullRequestReviewNonCopilotPullRequest EventType = "pull_request_review_non_copilot_pull_request"
	// EventTypeCodeScanningAlertsAssignment represents a code scanning alerts
	// assignment event.
	EventTypeCodeScanningAlertsAssignment EventType = "code_scanning_alerts_assignment"
	// EventTypeCodeReviewFixWithCopilot represents a job created to fix a
	// Copilot code review finding on an existing pull request.
	EventTypeCodeReviewFixWithCopilot EventType = "code_review_fix_with_copilot"
	// EventTypeAPICallReceived represents an API call received event.
	EventTypeAPICallReceived EventType = "api_call_received"
	// EventTypeSlack represents a Slack event.
	EventTypeSlack EventType = "slack"
	// EventTypeWorkflowRunFailed represents a workflow run failed event.
	EventTypeWorkflowRunFailed EventType = "workflow_run_failed"
	// EventTypeFixFailedWorkflow represents a job created via the Jobs API to
	// fix a failed workflow run (i.e. the "fix failed workflow" code path).
	EventTypeFixFailedWorkflow EventType = "fix_failed_workflow"
	// EventTypeIntervalTriggered represents a scheduled interval trigger event.
	EventTypeIntervalTriggered EventType = "interval_triggered"
	// EventTypeMergeConflict represents a merge conflict event.
	EventTypeMergeConflict EventType = "merge_conflict"
	// EventTypePullRequestOpened represents a pull_request.opened automation
	// trigger event.
	EventTypePullRequestOpened EventType = "pull_request_opened"
	// EventTypePullRequestMerged represents a pull_request.merged automation
	// trigger event.
	EventTypePullRequestMerged EventType = "pull_request_merged"
	// EventTypePullRequestSynchronize represents a pull_request.synchronize automation
	// trigger event.
	EventTypePullRequestSynchronize EventType = "pull_request_synchronize"
	// EventTypeManualTriggered represents a user-initiated manual automation run
	// with no specific event context.
	EventTypeManualTriggered EventType = "manual_triggered"
)

// AgentAction represents the category of action that the agent is expected
// is taking for the job.
type AgentAction string

const (
	// AgentActionFix is the action that the agent takes when it is triggered by
	// initially being assigned to an issue. The agent will then create a pull
	// request, post the plan/summary as the PR body, and make the fix in the PR.
	AgentActionFix AgentAction = "fix"
	// AgentActionFixPRComment is the action that the agent takes when it is
	// triggered by an actionable comment or a review or trigger n a pull request. The agent
	// replies directly to review comments and posts the plan/summary as a comment
	// on the pull request.
	AgentActionFixPRComment AgentAction = "fix-pr-comment"
	// AgentActionTask is the action used for a generic task that the agent is
	// expected to perform. This is typically triggered via an API call, and when
	// the user has not explicitly requested to work within a pull request to fix something.
	AgentActionTask AgentAction = "task"
)

// ResolveAction determines the correct agent action based on whether the job
// targets a pre-existing PR (HeadRef non-empty) as fix-pr-comment or is a new task/fix.
func ResolveAction(hasPR bool, headRef string) AgentAction {
	if hasPR && headRef != "" {
		return AgentActionFixPRComment
	}
	if !hasPR {
		return AgentActionTask
	}
	return AgentActionFix
}

// ActorType represents whether the job actor is a user or an organization.
type ActorType string

const (
	// ActorTypeUser indicates the job actor is a GitHub user (default).
	ActorTypeUser ActorType = "user"
	// ActorTypeOrg indicates the job actor is a GitHub organization.
	// When set, ActorID holds the org ID and billing is routed to the org's seat pool.
	ActorTypeOrg ActorType = "org"
)

// JobStatus represents the current status of a job.
type JobStatus string

const (
	// JobStatusPending means the job is waiting to be processed. This almost
	// always means there is another job running for the same assignment.
	JobStatusPending JobStatus = "pending"
	// JobStatusQueued means the job is queued for execution. Queued jobs
	// are ready to be executed, but are waiting for a worker to pick them up.
	// Queued jobs can also be delayed based on concurrency or rate limits.
	JobStatusQueued JobStatus = "queued"
	// JobStatusRunning means the job has been executed and is currently running.
	JobStatusRunning JobStatus = "running"
	// JobStatusCompleted means the job has been successfully completed.
	JobStatusCompleted JobStatus = "completed"
	// JobStatusFailed means the job has failed to complete successfully. Failed
	// jobs may have failed during processing, execution, or while running.
	JobStatusFailed JobStatus = "failed"
	// JobStatusCancelled means the job has been cancelled. This is used when
	// the job is cancelled by the user or by the system.
	JobStatusCancelled JobStatus = "cancelled"
	// JobStatusTimedOut means the job has been terminated due to exceeding
	// the maximum execution time limit.
	JobStatusTimedOut JobStatus = "timed_out"
)

// IsTerminal returns true if the job status is terminal ("completed", "failed",
// "cancelled", or "timed_out").
func (s JobStatus) IsTerminal() bool {
	return s == JobStatusCompleted || s == JobStatusFailed || s == JobStatusCancelled || s == JobStatusTimedOut
}

// RunOptions are options that can be set when creating a job to customize the
// output and behavior of the agent when it runs.
type RunOptions struct {
	// RunName is an optional title to use for runs
	RunName string `json:"run_name,omitempty"`
}

// EnvironmentFeatures describes the features of the environment that must be
// created for the agent to run the job.
type EnvironmentFeatures struct {
	// Branch contains details about the branch provided to the agent to use
	// during execution of the job.
	Branch *BranchFeature `json:"branch,omitempty"`

	// PullRequest contains details about the pull request provided to the agent
	// to use during execution of the job.
	PullRequest *PullRequestFeature `json:"pull_request,omitempty"`

	// CopilotSetupSteps configures the copilot setup steps feature.
	// When nil, setup steps use default behavior based on the agent config.
	CopilotSetupSteps *CopilotSetupStepsFeature `json:"copilot_setup_steps,omitempty"`
}

// CopilotSetupStepsFeature describes the copilot-setup-steps feature configuration.
type CopilotSetupStepsFeature struct {
	// Skip indicates that copilot-setup-steps should not be applied
	// even though the feature is configured. Defaults to false.
	Skip bool `json:"skip,omitempty"`

	// Exclude is a list of customization property names to ignore when
	// applying copilot-setup-steps (e.g. "steps", "runs-on", "permissions").
	// Mutually exclusive with Only. An error will be thrown if both are used.
	Exclude []string `json:"exclude,omitempty"`

	// Only is an allow-list of customization property names to honor when
	// applying copilot-setup-steps. When non-empty, every property not listed
	// here is ignored, including any new properties added to the service's
	// known set in the future. Mutually exclusive with Exclude.
	// An error will be thrown if both are used.
	Only []string `json:"only,omitempty"`
}

// ModelSelectionInfo contains metadata for engines that support dynamic model
// selection. When Enabled is true, engines can use the provided fields to
// resolve which model to use.
type ModelSelectionInfo struct {
	// Enabled indicates that model selection is active for this job.
	Enabled bool `json:"enabled,omitempty"`

	// Vendors is the list of model vendor names used for filtering (e.g. ["Anthropic", "OpenAI"]).
	Vendors []string `json:"vendors,omitempty"`

	// DefaultModel is the default model for this engine/vendor.
	DefaultModel string `json:"default_model,omitempty"`

	// AvailableModels is the list of model IDs the engine can choose from,
	// already filtered by vendor and user policy.
	AvailableModels []string `json:"available_models,omitempty"`
}

// CapiModelPrefix is the prefix used for models provided by CAPI.
const CapiModelPrefix = "sweagent-capi:"

// BranchFeature describes the branch that will be created for the job.
type BranchFeature struct {
	// Name is the name of the branch created for the job.
	Name string `json:"name,omitempty"`

	// BaseRef is the base ref that the branch is created from.
	BaseRef string `json:"base_ref,omitempty"`
}

// PullRequestFeature describes the pull request that will be created for the job.
type PullRequestFeature struct {
	// TitlePlaceholder is the placeholder text for the title of the pull request
	// before the AI updates it.
	TitlePlaceholder string `json:"title_placeholder,omitempty"`

	// BodyPlaceholder is the placeholder text for the body of the pull request
	// before the AI updates it.
	BodyPlaceholder string `json:"body_placeholder,omitempty"`

	// BodySuffix is the suffix to append to the body of the pull request after
	// each time the AI updates it.
	BodySuffix string `json:"body_suffix,omitempty"`

	// BaseRef is the base branch that the pull request targets.
	BaseRef string `json:"base_ref,omitempty"`

	// HeadRef is the branch that will be used for the PR (but still targeting
	// the BaseRef).
	// If not specified, but the branch feature is specified, the branch feature's
	// resulting branch will be used.
	// If neither is specified, a new branch will be created from the BaseRef.
	HeadRef string `json:"head_ref,omitempty"`

	// Labels are the labels to add to the PR.
	Labels []string `json:"labels,omitempty"`
}

// ProblemStatement describes the problem that the agent is being asked to solve.
type ProblemStatement struct {
	Content           string                            `json:"content"`
	CommitCount       int                               `json:"commit_count"`
	ContentFilterMode ProblemStatementContentFilterMode `json:"content_filter_mode"`
}

// ProblemStatementContentFilterMode describes how the content of the problem
// statement should be filtered.
type ProblemStatementContentFilterMode string

const (
	// ProblemStatementContentFilterModeNone specifies no filtering, the content
	// is used as-is and may include markdown, code blocks, HTML tags, etc.
	ProblemStatementContentFilterModeNone ProblemStatementContentFilterMode = "none"

	// ProblemStatementContentFilterModeMarkdown specifies filtering out any
	// non-markdown content (e.g. HTML tags, code blocks).
	ProblemStatementContentFilterModeMarkdown ProblemStatementContentFilterMode = "markdown"

	// ProblemStatementContentFilterModeHiddenCharacters specifies filtering
	// out any characters that are not visible (e.g. whitespace, newlines).
	ProblemStatementContentFilterModeHiddenCharacters ProblemStatementContentFilterMode = "hidden_characters"
)

// RepositoryRef identifies a repository by its database and node IDs along
// with the corresponding owner identifiers. It is used to reference
// repositories outside of the primary job context, such as additional
// repositories made available to a multi-repo job.
type RepositoryRef struct {
	RepoID      int64  `json:"repo_id"`
	OwnerID     int64  `json:"owner_id"`
	RepoNodeID  string `json:"repo_node_id"`
	OwnerNodeID string `json:"owner_node_id"`
}

// Job represents a unit of work to be performed by an agent.
//
// IMPORTANT:
//   - New jobs should be created using the [Assignment.NewJob] method.
//   - New fields should only be of primitive types, slices, or maps, or structs
//     defined in this package or in leaf packages (e.g. customagent). Do not import
//     other internal packages here unless absolutely necessary.
type Job struct {
	ID          string `json:"id"`
	RepoID      int64  `json:"repo_id"`
	OwnerID     int64  `json:"owner_id"`
	RepoNodeID  string `json:"repo_node_id"`
	OwnerNodeID string `json:"owner_node_id"`

	// AdditionalRepositories is the list of additional repositories that the
	// job has access to beyond the primary repository identified by RepoID,
	// OwnerID, RepoNodeID, and OwnerNodeID. This is used to support multi-repo
	// jobs where the agent needs context from more than one repository.
	AdditionalRepositories []RepositoryRef `json:"additional_repositories,omitempty"`

	// AssignmentID is the ID of the assignment that the job is part of
	AssignmentID      string `json:"assignment_id"`
	PullRequestID     int64  `json:"pull_request_id"`
	PullRequestNumber int    `json:"pull_request_number"`

	// PullRequestTitle is the agent-generated pull request title, populated from the
	// agent callback result. This field is passed through and not persisted in the DB.
	// It is included in JobUpdated Hydro events so async session consumers can
	// store it on the session.
	PullRequestTitle string `json:"-"`

	// PullRequestDescription is the agent-generated pull request description,
	// populated from the agent callback result. This field is passed through and not
	// persisted in the DB. It is included in JobUpdated Hydro events so async
	// session consumers can store it on the session.
	PullRequestDescription string `json:"-"`

	// IssueNumber is the number of the issue that the job is associated with.
	// It is needed to manage the issue state and to create comments.
	IssueNumber int `json:"issue_number,omitzero"`

	// ComputeID identifies the compute instance that the job runs/ran on.
	// For GitHub Actions, this is the ID of the WorkflowRun.
	ComputeID string `json:"compute_id"`
	SessionID string `json:"session_id"`

	// Title is a human-readable title for the job, typically derived from the
	// session name. This is used for display purposes and is included in
	// JobUpdated Hydro events for async session consumers.
	Title string `json:"title,omitempty"`

	// The IDs of previously launched job sessions, if those jobs have completed.
	// Ordered from most recent to oldest.
	// Determined just before job execution and not currently persisted.
	PreviousSessionIDs []string `json:"-"`

	// PreviousComputeID is the ComputeID of the most recent previous job
	// from the same actor. Used by the sandbox launcher to attempt resuming
	// a suspended VM. Determined just before job execution, not persisted.
	PreviousComputeID string `json:"-"`

	// PreviousComputeLaunchedAt is when the previous job's sandbox was launched.
	// Used to skip resume when tokens have expired. Not persisted.
	PreviousComputeLaunchedAt int64 `json:"-"`

	// ResumeSessionID, when non-empty, identifies a session that this job is
	// resuming (e.g. a session that was paused waiting for a permission
	// response and timed out). The runtime container loads that session's
	// events.jsonl snapshot from progress history and calls
	// client.resumeSession with it instead of starting fresh.
	ResumeSessionID string `json:"resume_session_id,omitempty"`

	EventType        EventType     `json:"event_type"`
	EventURL         string        `json:"event_url"`
	EventIdentifiers []string      `json:"event_identifiers"`
	EventContent     string        `json:"event_content"`
	Launcher         launcher.Type `json:"launcher"`
	Status           JobStatus     `json:"status"`
	RequestStartedAt int64         `json:"request_started_at"`
	CreatedAt        int64         `json:"created_at"`
	PreparedAt       int64         `json:"prepared_at"`
	LaunchedAt       int64         `json:"launched_at"`
	QueuedAt         int64         `json:"queued_at"`
	CompletedAt      int64         `json:"completed_at"`
	WasDelayed       bool          `json:"was_delayed,omitempty"`
	UpdatedAt        int64         `json:"_ts,omitempty"`
	StartedAt        int64         `json:"started_at"`
	RunningAt        int64         `json:"running_at"`
	Action           AgentAction   `json:"action"`
	Model            string        `json:"model"`
	IsAutoMode       bool          `json:"is_auto_mode"`
	// IsTriggered indicates whether the job was initiated by a custom agent
	// trigger (e.g. issues.opened, workflow_run.failed) rather than a direct
	// user action. Set when WithTrigger() is called on the job builder.
	IsTriggered bool `json:"is_triggered,omitempty"`
	// AutomationID is the ID of the automation that triggered this job, if any.
	AutomationID     string               `json:"automation_id,omitempty"`
	BranchName       string               `json:"branch_name"`
	BaseCommit       string               `json:"base_commit"`
	ProblemStatement ProblemStatement     `json:"problem_statement"`
	CustomAgent      customagent.DBRecord `json:"custom_agent"`

	RunOptions     RunOptions          `json:"run_options"`
	Features       EnvironmentFeatures `json:"features"`
	ModelSelection *ModelSelectionInfo `json:"model_selection,omitempty"`

	Args launcher.LaunchAgentOpts `json:"args"`

	// ReplyCommentID is the ID of the of the PR comment where the agent replied
	ReplyCommentID int64 `json:"reply_comment_id"`

	// OnboardingCommentID is the ID of the comment that was posted to the PR to
	// onboard the user to the Copilot agent. This is used to track the onboarding
	// process and to ensure that the user has been onboarded only once per repository.
	OnboardingCommentID int64 `json:"onboarding_comment_id"`

	// ActorID is the ID of the GitHub user that triggered the copilot agent job.
	// This is the actor that will be attributed to API calls made by the agent
	// as well as git commits made by the agent. Thus, the actor must have the
	// necessary permissions to perform the required actions.
	ActorID int64 `json:"actor_id"`

	// ActorLogin is the login of the GitHub user that triggered the copilot agent
	// job. This is the actor that will be attributed to API calls made by the
	// agent as well as git commits made by the agent. Thus, the actor must have
	// the necessary permissions to perform the required actions.
	ActorLogin string `json:"actor_login"`

	// ActorDisplayLogin is the suffix-less login of the GitHub user that triggered
	// the copilot agent job. This value is primarily intended for use with Proxima,
	// outside of Proxima it is identical to ActorLogin. If this isn't set in Proxima,
	// it needs to be filled through the use of ResolveUserIDToDisplayLogin .
	ActorDisplayLogin string `json:"actor_display_login"`

	// ActorAnalyticsTrackingID is the tracking ID of the actor that triggered the copilot agent job.
	ActorAnalyticsTrackingID string `json:"actor_analytics_tracking_id,omitempty"`

	// ActorType indicates whether the actor is a user or an organization.
	// When "org", ActorID is the org ID and billing is routed to the org's seat pool
	// via S2S tokens. When "user" or empty (default), existing user billing applies.
	ActorType ActorType `json:"actor_type,omitempty"`

	// AgentID is the GitHub App ID to use for this job. If 0, defaults to Copilot's app ID.
	AgentID int64 `json:"agent_id,omitempty"`

	// ReviewIDs is a list of review IDs that can be considered handled/to
	// be handled) by the agent as part of this job.
	// Individual review comments are tracked as part of their parent review.
	ReviewIDs []int64 `json:"review_ids"`

	// CommentIDs is a list of comment IDs that can be considered handled/to
	// be handled) by the agent as part of this job.
	CommentIDs []int64 `json:"comment_ids"`

	// CustomSetupStepsUsed indicates whether custom setup steps from
	// .github/workflows/copilot-setup-steps.yml/yaml were successfully applied
	// to this job.
	CustomSetupStepsUsed bool `json:"custom_setup_steps_used,omitempty"`

	// RunsOn contains the actual runs-on value from custom setup steps.
	// Empty string means no custom runs-on was specified (defaults to ubuntu-latest).
	// This field is only meaningful when CustomSetupStepsUsed is true.
	RunsOn string `json:"runs_on,omitempty"`

	// NonceHash is a SHA256 hash of a random value generated when the job is created and used to
	// validate callback requests come from the right workflow run
	NonceHash            string                             `json:"nonce_hash"`
	Error                *JobError                          `json:"error,omitempty"`
	Experiments          *experiments.AssignmentExperiments `json:"experiments,omitempty"`
	SDKAssignmentContext string                             `json:"sdk_assignment_context,omitempty"`
	ETag                 *azcore.ETag                       `json:"_etag,omitempty"`

	// UseAsyncSessions indicates whether sessions should be managed asynchronously
	// by the runtime instead of by sweagentd. Copied from Assignment at job creation.
	UseAsyncSessions bool `json:"use_async_sessions,omitempty"`

	// RequireSignedCommits indicates whether the repository's branch protection
	// or ruleset rules require commits to be signed. Determined at job creation time
	// and used by the runtime to enable commit signing.
	RequireSignedCommits bool `json:"require_signed_commits,omitempty"`

	// CanWriteWorkflows records whether the triggering credential had
	// workflows:write at job creation. Tri-state: nil ⇒ not checked (FF off
	// or out-of-scope path); &true ⇒ allowed; &false ⇒ denied.
	CanWriteWorkflows *bool `json:"can_write_workflows,omitempty"`
}

// NewJob creates a new pending job for the assignment.
func (a *Assignment) NewJob(action AgentAction, actor JobActor, baseCommit string) *Job {
	jobID := GenerateJobID(a.OwnerID, a.RepoID)

	job := &Job{
		ID:                       jobID,
		AssignmentID:             a.ID,
		RepoID:                   a.RepoID,
		OwnerID:                  a.OwnerID,
		RepoNodeID:               a.RepoNodeID,
		OwnerNodeID:              a.OwnerNodeID,
		AdditionalRepositories:   a.AdditionalRepositories,
		PullRequestID:            a.PullRequestID,
		PullRequestNumber:        a.PullRequestNumber,
		Status:                   JobStatusPending,
		Action:                   action,
		Args:                     launcher.LaunchAgentOpts{},
		ActorID:                  actor.ID,
		ActorLogin:               actor.Login,
		ActorDisplayLogin:        actor.DisplayLogin,
		ActorAnalyticsTrackingID: actor.TrackingID,
		ActorType:                actor.Type,
		BaseCommit:               baseCommit,
		Experiments:              a.Experiments,
		SDKAssignmentContext:     a.SDKAssignmentContext,
		CustomAgent:              a.CustomAgent,
		UseAsyncSessions:         a.UseAsyncSessions,
	}

	// Generate a new session ID for async sessions since sweagentd won't create one via CAPI
	if a.UseAsyncSessions {
		job.SessionID = uuid.NewString()
	}

	return job
}

// GenerateJobID generates a new job ID based on the owner ID, repository ID,
// and a new UUID.
func GenerateJobID(ownerID, repoID int64) string {
	uid := uuid.New()
	return fmt.Sprintf("%d-%d-%s", ownerID, repoID, uid)
}

// JobActor represents the a GitHub user that is associated with a job.
type JobActor struct {
	ID           int64
	Login        string
	DisplayLogin string
	TrackingID   string
	Type         ActorType
}

// JobError represents an error that occurred during the processing of a job.
type JobError struct {
	Message string `json:"message"`

	// Optional status code that is representative of the class of error that was encountered
	ResponseStatusCode string `json:"response_status_code,omitempty"`

	Service string `json:"service,omitempty"`
}

// Summary returns a string summary of the error in the format "service:code".
func (je *JobError) Summary() string {
	var segments []string

	if je.Service != "" {
		segments = append(segments, je.Service)
	}

	if je.ResponseStatusCode != "" {
		segments = append(segments, je.ResponseStatusCode)
	}

	return strings.Join(segments, ":")
}

// CreateJobError creates a JobError from an error. If the error is a JobError,
// it is returned as-is. If the error is a joberrors.JobError, the relevant fields
// are extracted and used to create a JobError. Otherwise, a generic JobError is
// created with the error message and a status code derived from the error using
// joberrors.StatusCodeFromMarkedError.
func CreateJobError(err error) *JobError {
	var je *joberrors.JobError
	if errors.As(err, &je) {
		return &JobError{
			Message:            err.Error(),
			ResponseStatusCode: je.Code,
			Service:            je.Service,
		}
	}

	code := joberrors.StatusCodeFromMarkedError(err)
	return &JobError{
		Message:            err.Error(),
		ResponseStatusCode: fmt.Sprintf("%v", code),
	}
}

// CreateJobErrorWithMessage creates a JobError from a joberrors.JobError with an additional
// custom message.
func CreateJobErrorWithMessage(je *joberrors.JobError, message string) *JobError {
	return &JobError{
		ResponseStatusCode: je.Code,
		Service:            je.Service,
		Message:            message,
	}
}

// Persisted returns true if the job has been persisted to the database.
func (j *Job) Persisted() bool {
	return j.ETag != nil
}

// PullRequestBodySuffix returns the suffix to append to the body of the pull
// request after each time the AI updates it.
func (j *Job) PullRequestBodySuffix() string {
	if j.Features.PullRequest != nil && j.Features.PullRequest.BodySuffix != "" {
		return j.Features.PullRequest.BodySuffix
	}
	return ""
}

// GetRepositoryID returns the repository ID associated with the job.
// This method satisfies the [sweagentd.Repository] interface for [Job].
func (j *Job) GetRepositoryID() int64 {
	return j.RepoID
}

// GetOwnerID returns the owner ID associated with the job.
// This method satisfies the [sweagentd.Repository] interface for [Job].
func (j *Job) GetOwnerID() int64 {
	return j.OwnerID
}

// GetActorID returns the actor ID associated with the job.
// This method satisfies the [sweagentd.Actor] interface for [Job].
func (j *Job) GetActorID() int64 {
	return j.ActorID
}

// IsOrgActor returns true if this job's actor is an organization.
func (j *Job) IsOrgActor() bool {
	return j.ActorType == ActorTypeOrg
}

// IsBillToOrg returns true if this job should be billed to the org's seat pool.
// This is equivalent to IsOrgActor and satisfies the [tokens.OrgBillableJob] interface.
func (j *Job) IsBillToOrg() bool {
	return j.IsOrgActor()
}

// IsQueued returns true if the job has the status "queued".
func (j *Job) IsQueued() bool {
	return j.Status == JobStatusQueued
}

// IsPending returns true if the job has the status "pending".
func (j *Job) IsPending() bool {
	return j.Status == JobStatusPending
}

// IsRunning returns true if the job has the status "running".
func (j *Job) IsRunning() bool {
	return j.Status == JobStatusRunning
}

// IsTerminal returns true if the job status is terminal ("completed", "failed",
// "cancelled", or "timed_out").
func (j *Job) IsTerminal() bool {
	return j.Status.IsTerminal()
}

// IsActionsLauncher reports whether this job runs (or ran) on GitHub Actions.
// Jobs created before the Launcher field was tracked have an empty Launcher
// value, which is treated as Actions for back-compat.
func (j *Job) IsActionsLauncher() bool {
	return j.Launcher == "" || j.Launcher == launcher.TypeActions
}

// ComputeType returns the compute backend type used for telemetry.
func (j *Job) ComputeType() string {
	if j.IsActionsLauncher() {
		return string(launcher.TypeActions)
	}
	return string(j.Launcher)
}

// WorkflowRunID returns the GitHub Actions workflow run ID for this job,
// parsed from ComputeID. The boolean is false when the job did not run on
// Actions or when ComputeID is empty/unparseable, in which case callers must
// not use the returned ID. This is the canonical way to obtain the Actions run
// ID from a Job — call sites should not parse ComputeID themselves.
func (j *Job) WorkflowRunID() (int64, bool) {
	if !j.IsActionsLauncher() || j.ComputeID == "" {
		return 0, false
	}
	id, err := strconv.ParseInt(j.ComputeID, 10, 64)
	if err != nil {
		return 0, false
	}
	return id, true
}

// HasFeatures returns true if the job has any environment features set.
func (j *Job) HasFeatures() bool {
	return j.Features.Branch != nil || j.Features.PullRequest != nil || j.Features.CopilotSetupSteps != nil
}

// HasBranch returns true if the job is associated with a branch.
func (j *Job) HasBranch() bool {
	return j.BranchName != ""
}

// RequiresBranch returns true if the job requires a branch to be created.
func (j *Job) RequiresBranch() bool {
	return j.Features.Branch != nil || j.Features.PullRequest != nil
}

// HasPullRequest returns true if the job is associated with pull request ids.
func (j *Job) HasPullRequest() bool {
	return j.PullRequestID != 0 && j.PullRequestNumber != 0
}

// RequiresPullRequest returns true if the job requires a pull request to be created.
func (j *Job) RequiresPullRequest() bool {
	return j.Features.PullRequest != nil
}

// HasRunOptions returns true if the job has run options run name or output type set.
func (j *Job) HasRunOptions() bool {
	return j.RunOptions.RunName != ""
}

// HasCustomAgent returns true if the job has a custom agent assigned to it.
func (j *Job) HasCustomAgent() bool {
	return j.CustomAgent.Name != ""
}

// HasOnboardingComment returns true if the job has an onboarding comment ID set.
func (j *Job) HasOnboardingComment() bool {
	return j.OnboardingCommentID != 0
}

// HasSession returns true if the job has a session ID set.
func (j *Job) HasSession() bool {
	return j.SessionID != ""
}

// GenerateNonce generates a new random nonce that can be used to validate
// callback requests from the agent scoped to a specific job. It returns an
// error if cryptographic randomness generation fails.
func GenerateNonce() (string, error) {
	return generateRandomHex(32) // 64 characters as hex string
}

// HashNonce returns the SHA256 hash of the given nonce string.
func HashNonce(nonce string) string {
	hasher := sha256.New()
	_, _ = hasher.Write([]byte(nonce))
	return hex.EncodeToString(hasher.Sum(nil))
}

func generateRandomHex(n int) (string, error) {
	bytes := make([]byte, n)
	_, err := io.ReadFull(randReader, bytes)
	if err != nil {
		return "", goerrors.Errorf("failed to read random bytes from randReader: %w", err)
	}
	return hex.EncodeToString(bytes), nil
}

// HasNonTerminalJobs returns true if any of the jobs in the slice are not in a
// terminal state.
func HasNonTerminalJobs(jobs []*Job) bool {
	for _, j := range jobs {
		if !j.IsTerminal() {
			return true
		}
	}
	return false
}

// HasQueuedOrRunningJobs returns true if any of the jobs in the slice are in a
// "queued" or "running" state. It also returns the ID of the first job found
// that is in one of those states.
func HasQueuedOrRunningJobs(jobs []*Job) (bool, string) {
	for _, j := range jobs {
		if j.Status == JobStatusQueued || j.Status == JobStatusRunning {
			return true, j.ID
		}
	}
	return false, ""
}

// NewCommand creates a new pending [command.Command] for the job.
func (j *Job) NewCommand(externalID string, actorID int64, content string, cmdType command.Type, timestamp int64) *command.Command {
	return &command.Command{
		ID:                command.NewID(),
		JobID:             j.ID,
		AssignmentID:      j.AssignmentID,
		RepoID:            j.RepoID,
		OwnerID:           j.OwnerID,
		SessionID:         j.SessionID,
		ExternalID:        externalID,
		ActorID:           actorID,
		Content:           content,
		Status:            command.StatusPending,
		Type:              cmdType,
		ExternalTimestamp: timestamp,
	}
}

// NewProgress creates a new [progress.Progress] for the job.
func (j *Job) NewProgress(namespace, kind string, version int64, content any) *progress.Progress {
	return &progress.Progress{
		ID:           progress.NewID(),
		JobID:        j.ID,
		AssignmentID: j.AssignmentID,
		RepoID:       j.RepoID,
		OwnerID:      j.OwnerID,
		Namespace:    namespace,
		Kind:         kind,
		Version:      version,
		Content:      content,
	}
}

// RefName returns the full ref name for the job's branch.
func (j *Job) RefName() string {
	maybeRef := j.BranchName
	if maybeRef == "" && j.Features.Branch != nil {
		maybeRef = j.Features.Branch.Name
	}
	if maybeRef == "" && j.Features.PullRequest != nil {
		maybeRef = j.Features.PullRequest.HeadRef
	}
	if maybeRef == "" {
		return ""
	}
	if strings.HasPrefix(maybeRef, "refs/") {
		return maybeRef
	}
	return "refs/heads/" + maybeRef
}

// InheritedWorkflowsAccess returns the most recent non-nil
// Job.CanWriteWorkflows value across jobs in the assignment that share the
// given agentID, or nil when no prior same-agent job has a checked value.
func InheritedWorkflowsAccess(allJobs []*Job, agentID int64) *bool {
	var mostRecent *Job
	for _, j := range allJobs {
		if j == nil || j.AgentID != agentID || j.CanWriteWorkflows == nil {
			continue
		}
		if mostRecent == nil || j.CreatedAt > mostRecent.CreatedAt {
			mostRecent = j
		}
	}
	if mostRecent == nil {
		return nil
	}
	return mostRecent.CanWriteWorkflows
}
