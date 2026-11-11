package jobs

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"

	"errors"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/google/uuid"
)

// JobNonceHeader is the header used to pass the nonce to the agent when the
// job is created. The agent will use this nonce to validate that the callback
// request comes from the right workflow run.
const JobNonceHeader = "X-GitHub-Job-Nonce"

// EventType represents the type of event that triggered the job.
type EventType string

const (
	EventTypeIssueAssignment                         EventType = "issue_assignment"
	EventTypePullRequestComment                      EventType = "pull_request_comment"
	EventTypePullRequestCommentNonCopilotPullRequest EventType = "pull_request_comment_non_copilot_pull_request"
	EventTypePullRequestReview                       EventType = "pull_request_review"
	EventTypePullRequestReviewNonCopilotPullRequest  EventType = "pull_request_review_non_copilot_pull_request"
	EventTypeCodeScanningAlertsAssignment            EventType = "code_scanning_alerts_assignment"
	EventTypeApiCallReceived                         EventType = "api_call_received"
	EventTypeSlack                                   EventType = "slack"
	EventTypeSlackStaging                            EventType = "slack-staging"
)

type AgentAction string

const (
	// AgentActionFix is the action that the agent takes when it is triggered by
	// by initially being assigned to an issue. The agent will then create a pull
	// request, post the plan/summary as the PR body, and make the fix in the PR.
	AgentActionFix AgentAction = "fix"
	// AgentActionFixPRComment is the action that the agent takes when it is
	// triggered by an actionable comment or a review on a pull request. The agent
	// replies directly to review comments and posts the plan/summary as a comment
	// on the pull request.
	AgentActionFixPRComment AgentAction = "fix-pr-comment"
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
}

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

func (j *Job) PullRequestBodySuffix() string {
	if j.Features.PullRequest != nil && j.Features.PullRequest.BodySuffix != "" {
		return j.Features.PullRequest.BodySuffix
	}
	return ""
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
	RepoName    string `json:"repo_name"`
	RepoOwner   string `json:"repo_owner"`

	// AssignmentID is the ID of the assignment that the job is part of
	AssignmentID      string `json:"assignment_id"`
	PullRequestID     int64  `json:"pull_request_id"`
	PullRequestNumber int    `json:"pull_request_number"`

	// IssueNumber is the number of the issue that the job is associated with.
	// It is needed to manage the issue state and to create comments.
	IssueNumber int `json:"issue_number,omitzero"`

	// ComputeID identifies the compute instance that the job runs/ran on.
	// For GitHub Actions, this is the ID of the WorkflowRun.
	ComputeID string `json:"compute_id"`
	SessionID string `json:"session_id"`

	// The IDs of previously launched job sessions, if those jobs have completed.
	// Ordered from most recent to oldest.
	// Determined just before job execution and not currently persisted.
	PreviousSessionIDs []string `json:"-"`

	EventType        EventType             `json:"event_type"`
	EventURL         string                `json:"event_url"`
	EventIdentifiers []string              `json:"event_identifiers"`
	EventContent     string                `json:"event_content"`
	Launcher         launcher.LauncherType `json:"launcher"`
	Status           JobStatus             `json:"status"`
	CreatedAt        int64                 `json:"created_at"`
	LaunchedAt       int64                 `json:"launched_at"`
	QueuedAt         int64                 `json:"queued_at"`
	CompletedAt      int64                 `json:"completed_at"`
	UpdatedAt        int64                 `json:"_ts,omitempty"`
	Action           AgentAction           `json:"action"`
	Model            string                `json:"model"`
	BranchName       string                `json:"branch_name"`
	BaseCommit       string                `json:"base_commit"`
	ProblemStatement ProblemStatement      `json:"problem_statement"`
	CustomAgent      customagent.DBRecord  `json:"custom_agent"`

	RunOptions RunOptions          `json:"run_options"`
	Features   EnvironmentFeatures `json:"features,omitempty"`

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

	// ReviewIDs is a list of review IDs that can be considered handled/to
	// be handled) by the agent as part of this job.
	// Individual review comments are tracked as part of their parent review.
	ReviewIDs []int64 `json:"review_ids"`

	// CommentIDs is a list of comment IDs that can be considered handled/to
	// be handled) by the agent as part of this job.
	CommentIDs []int64 `json:"comment_ids"`

	// NonceHash is a SHA256 hash of a random value generated when the job is created and used to
	// validate callback requests come from the right workflow run
	NonceHash   string                             `json:"nonce_hash"`
	Error       *JobError                          `json:"error,omitempty"`
	Experiments *experiments.AssignmentExperiments `json:"experiments,omitempty"`
	ETag        *azcore.ETag                       `json:"_etag,omitempty"`
}

// NewJob creates a new pending job for the assignment.
func (a *Assignment) NewJob(action AgentAction, actor JobActor, baseCommit string) *Job {
	return &Job{
		ID:                       GenerateJobID(a.OwnerID, a.RepoID),
		AssignmentID:             a.ID,
		RepoID:                   a.RepoID,
		OwnerID:                  a.OwnerID,
		RepoNodeID:               a.RepoNodeID,
		OwnerNodeID:              a.OwnerNodeID,
		RepoName:                 a.RepoName,
		RepoOwner:                a.RepoOwner,
		PullRequestID:            a.PullRequestID,
		PullRequestNumber:        a.PullRequestNumber,
		Status:                   JobStatusPending,
		Action:                   action,
		Args:                     launcher.LaunchAgentOpts{},
		ActorID:                  actor.ID,
		ActorLogin:               actor.Login,
		ActorDisplayLogin:        actor.DisplayLogin,
		ActorAnalyticsTrackingID: actor.TrackingID,
		BaseCommit:               baseCommit,
		Experiments:              a.Experiments,
		CustomAgent:              a.CustomAgent,
	}
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
}

// JobError represents an error that occurred during the processing of a job.
type JobError struct {
	Message string `json:"message"`

	// Optional HTTP status code that is representative of the class of error that was encountered
	ResponseStatusCode string `json:"response_status_code,omitempty"`
	Service            string `json:"service,omitempty"`
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

// GetRepositoryName returns the repository name associated with the job.
// This method satisfies the [sweagentd.RepositoryWithName] interface for [Job].
func (j *Job) GetRepositoryName() string {
	return j.RepoName
}

// GetActorID returns the actor ID associated with the job.
// This method satisfies the [sweagentd.Actor] interface for [Job].
func (j *Job) GetActorID() int64 {
	return j.ActorID
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

// HasFeatures returns true if the job has any environment features set.
func (j *Job) HasFeatures() bool {
	return j.Features.Branch != nil || j.Features.PullRequest != nil
}

// HasBranch returns true if the job is associated with a branch.
func (j *Job) HasBranch() bool {
	return j.BranchName != ""
}

// RequiresBranch returns true if the job requires a branch to be created.
func (j *Job) RequiresBranch() bool {
	return j.Features.Branch != nil || j.Features.PullRequest != nil
}

// HasPullRequest returns true if the job is associated with a pull request.
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
// callback requests from the agent scoped to a specific job.
func GenerateNonce() string {
	return generateRandomHex(32) // 64 characters as hex string
}

// HashNonce returns the SHA256 hash of the given nonce string.
func HashNonce(nonce string) string {
	hasher := sha256.New()
	hasher.Write([]byte(nonce))
	return hex.EncodeToString(hasher.Sum(nil))
}

func generateRandomHex(n int) string {
	bytes := make([]byte, n)
	if _, err := rand.Read(bytes); err != nil {
		return "12345"
	}
	return hex.EncodeToString(bytes)
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
