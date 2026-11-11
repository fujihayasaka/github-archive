package events

import (
	"strings"
	"time"
)

const (
	PullRequestStateOpen   = "open"
	PullRequestStateClosed = "closed"
	PullRequestStateMerged = "merged"
)

const (
	WorkflowCompletedEventStatusCompleted     = "completed"
	WorkflowCompletedEventConclusionSuccess   = "success"
	WorkflowCompletedEventConclusionFailure   = "failure"
	WorkflowCompletedEventConclusionCancelled = "cancelled"
)

// Actor represents a user or bot that is the subject of an event.
type Actor struct {
	ID           int64
	NodeID       string
	Login        string
	DisplayLogin string
	TrackingID   string // New field for tracking ID
	Type         string
}

func (a Actor) GetActorID() int64 {
	return a.ID
}

func (a Actor) GetLogin() string {
	return a.Login
}

// Repository represents a GitHub repository associated with an event.
type Repository struct {
	ID            int64
	NodeID        string
	Name          string
	OwnerID       int64
	IsPrivate     bool
	IsPublic      bool
	DefaultBranch string
}

// GetRepositoryID returns the repository ID.
// This satisfies the sweagentd.Repository interface.
func (r Repository) GetRepositoryID() int64 {
	return r.ID
}

// GetOwnerID returns the owner ID.
// This satisfies the sweagentd.Repository interface.
func (r Repository) GetOwnerID() int64 {
	return r.OwnerID
}

// Issue represents a GitHub issue or pull request associated with an event.
type Issue struct {
	ID     int64
	NodeID string
	Number int
	IsOpen bool
}

// PullRequestIssue represents a GitHub pull request represented as an issue.
// This is used in events where only the issue object is available, such as
// PullRequestTimelineCommentCreate to make it clear which fields are available.
// The NodeID and Number fields will match the values of the associated PullRequest
// but the ID field will not.
type PullRequestIssue struct {
	NodeID string
	Number int
	IsOpen bool
}

func (p *PullRequestIssue) isOpen() bool {
	return p.IsOpen
}

// PullRequest represents a GitHub pull request associated with an event.
type PullRequest struct {
	ID         int64
	NodeID     string
	Number     int
	IsOpen     bool
	IsDraft    *bool
	AuthorID   int64
	State      string // e.g. "open", "closed", "merged"
	HeadBranch string
	BaseBranch string
}

func (p *PullRequest) HeadBranchHasPrefix(prefix string) bool {
	return p.HeadBranch != "" && strings.HasPrefix(p.HeadBranch, prefix)
}

func (p *PullRequest) isOpen() bool {
	return p.IsOpen
}

type PullRequestReview struct {
	ID   int64
	Body string

	// Comments is mostly used to detect Agentic mentions in review comments.
	Comments []string
}

type PullRequestComment struct {
	ID     int64
	NodeID string
	Body   string
}

// WorkflowRun represents a GitHub Actions workflow run associated with an event.
type WorkflowRun struct {
	ID           int64
	Path         string
	UserID       int64
	CheckSuiteID int64
	Status       string
	Conclusion   string
	Attempt      int
	StartedAt    int64
	CompletedAt  int64
	UsageMs      int64
}

func (w *WorkflowRun) PathHasPrefix(prefix string) bool {
	return w.Path != "" && strings.HasPrefix(w.Path, prefix)
}

type WorkflowRepository struct {
	ID      int64
	OwnerID int64
}

// GetRepositoryID returns the repository ID.
// This satisfies the sweagentd.Repository interface.
func (r *WorkflowRepository) GetRepositoryID() int64 {
	return r.ID
}

// GetOwnerID returns the owner ID.
// This satisfies the sweagentd.Repository interface.
func (r *WorkflowRepository) GetOwnerID() int64 {
	return r.OwnerID
}

type CodeScanningAlert struct {
	Number       int64
	Title        string
	Url          string
	SuggestedFix *SuggestedFix
}
type SuggestedFix struct {
	Files []*SuggestedFixFile
}
type SuggestedFixFile struct {
	FilePath    string
	DiffContent []byte
}

type PullRequestReviewSubmitEvent struct {
	// The user that submitted the PR review
	Actor             *Actor
	Repo              *Repository
	PullRequest       *PullRequest
	PullRequestReview *PullRequestReview
	EventUrl          string
	Timestamp         time.Time
	// AgentID is the target agentic app that was @-mentioned.
	AgentID int64
	// GitHubAppID is the ID of the GitHub App that submitted the review, if any.
	// Used to check the app's permissions before allowing it to trigger agent work.
	GitHubAppID *int64
}

func (e *PullRequestReviewSubmitEvent) GetActorID() int64 {
	return e.Actor.ID
}

func (e *PullRequestReviewSubmitEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *PullRequestReviewSubmitEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *PullRequestReviewSubmitEvent) GetAgentID() int64 {
	return e.AgentID
}

type PullRequestCommentCreatedEvent struct {
	// The actor that created the comment.
	Actor       *Actor
	Repo        *Repository
	PullRequest *PullRequestIssue
	Comment     *PullRequestComment
	EventUrl    string
	Timestamp   time.Time
	// AgentID is the target agentic app that was @-mentioned.
	AgentID int64
	// GitHubAppID is the ID of the GitHub App that created the comment, if any.
	// Used to check the app's permissions before allowing it to trigger agent work.
	GitHubAppID *int64
}

func (e *PullRequestCommentCreatedEvent) GetActorID() int64 {
	return e.Actor.ID
}

func (e *PullRequestCommentCreatedEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *PullRequestCommentCreatedEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *PullRequestCommentCreatedEvent) GetAgentID() int64 {
	return e.AgentID
}

type PullRequestStateChangedEvent struct {
	Actor       *Actor
	Repo        *Repository
	PullRequest *PullRequest
	Timestamp   time.Time
	AgentID     int64

	// AutomationID, when set, restricts automation lookup to this specific automation. Used for on-demand automation run requests.
	AutomationID string
}

func (e *PullRequestStateChangedEvent) GetActorID() int64 {
	return e.Actor.ID
}

func (e *PullRequestStateChangedEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *PullRequestStateChangedEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *PullRequestStateChangedEvent) GetAgentID() int64 {
	return e.AgentID
}

// WorkflowRunEventKind categorizes the type of workflow run event for routing
// and processing decisions.
type WorkflowRunEventKind string

const (
	// WorkflowRunKindAgentCompletion indicates a dynamic agent workflow run
	// (e.g., Copilot, Claude) that completed. These events are processed by
	// the service to finalize the job, update the session, and handle pending
	// jobs.
	WorkflowRunKindAgentCompletion WorkflowRunEventKind = "agent_completion"

	// WorkflowRunKindFailedTrigger indicates a non-agent workflow run that
	// failed, eligible for custom agent trigger evaluation. These events are
	// processed by the worker.
	WorkflowRunKindFailedTrigger WorkflowRunEventKind = "workflow_run_failed"
)

type WorkflowRunCompletedEvent struct {
	Repo        *WorkflowRepository
	WorkflowRun *WorkflowRun
	Timestamp   time.Time
	AgentID     int64
	// Kind categorizes this workflow run event for routing and processing.
	Kind WorkflowRunEventKind

	// AutomationID, when set, restricts automation lookup to this specific
	// automation. Used for on-demand automation run requests.
	AutomationID string
}

// IsAgentCompletion returns true if this is a dynamic agent workflow run completion.
func (e *WorkflowRunCompletedEvent) IsAgentCompletion() bool {
	return e.Kind == WorkflowRunKindAgentCompletion
}

// TriggerName returns the trigger name for queue routing, or empty string if
// this is not a trigger event.
func (e *WorkflowRunCompletedEvent) TriggerName() string {
	if e.Kind == WorkflowRunKindFailedTrigger {
		return string(e.Kind)
	}
	return ""
}

func (e *WorkflowRunCompletedEvent) GetActorID() int64 {
	return e.WorkflowRun.UserID
}

func (e *WorkflowRunCompletedEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *WorkflowRunCompletedEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *WorkflowRunCompletedEvent) GetAgentID() int64 {
	return e.AgentID
}

// IsDynamic returns whether this workflow run originated from a dynamic workflow.
func (e *WorkflowRunCompletedEvent) IsDynamic() bool {
	return strings.HasPrefix(e.WorkflowRun.Path, "dynamic/")
}

type CodeScanningAlertsAssignmentEvent struct {
	Actor     *Actor
	Repo      *Repository
	Alerts    []*CodeScanningAlert
	Assignees []string
	EventUrl  string
	Timestamp time.Time
	AgentID   int64
}

func (e *CodeScanningAlertsAssignmentEvent) GetActorID() int64 {
	return e.Actor.ID
}

func (e *CodeScanningAlertsAssignmentEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *CodeScanningAlertsAssignmentEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *CodeScanningAlertsAssignmentEvent) GetAgentID() int64 {
	return e.AgentID
}

type IssueCreatedEvent struct {
	// The actor that created the issue.
	Actor     *Actor
	Repo      *Repository
	Owner     *Actor
	Issue     *Issue
	AgentID   int64
	Timestamp time.Time

	// AutomationID, when set, restricts automation lookup to this specific
	// automation. Used for on-demand automation run requests.
	AutomationID string
}

func (e *IssueCreatedEvent) GetActorID() int64 {
	return e.Actor.ID
}

func (e *IssueCreatedEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *IssueCreatedEvent) GetOwnerID() int64 {
	return e.Owner.ID
}

func (e *IssueCreatedEvent) GetAgentID() int64 {
	return e.AgentID
}

// PullRequestOpenedEvent represents a pull_request.opened automation trigger event.
type PullRequestOpenedEvent struct {
	Actor       *Actor
	Repo        *Repository
	Owner       *Actor
	PullRequest *PullRequest
	// HeadRepoID differs from Repo.ID when the PR is from a fork.
	HeadRepoID int64
	Title      string
	Body       string
	AgentID    int64
	Timestamp  time.Time

	// AutomationID, when set, restricts automation lookup to this specific
	// automation. Used for on-demand automation run requests.
	AutomationID string
}

func (e *PullRequestOpenedEvent) GetActorID() int64 {
	return e.Actor.ID
}

func (e *PullRequestOpenedEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *PullRequestOpenedEvent) GetOwnerID() int64 {
	return e.Owner.ID
}

func (e *PullRequestOpenedEvent) GetAgentID() int64 {
	return e.AgentID
}

// IsFromFork reports whether the PR originated from a forked repository.
func (e *PullRequestOpenedEvent) IsFromFork() bool {
	if e == nil || e.Repo == nil {
		return false
	}
	return e.HeadRepoID != 0 && e.HeadRepoID != e.Repo.ID
}

// PullRequestSynchronizeEvent represents a pull_request.synchronize automation trigger; handlers must hydrate PR title/body and head-repo owner via the GitHub API.
type PullRequestSynchronizeEvent struct {
	Actor       *Actor
	Repo        *Repository
	PullRequest *PullRequest
	BeforeOID   string
	AfterOID    string
	AgentID     int64
	Timestamp   time.Time

	// AutomationID, when set, restricts automation lookup to this specific automation. Used for on-demand automation run requests.
	AutomationID string
}

func (e *PullRequestSynchronizeEvent) GetActorID() int64 {
	if e.Actor == nil {
		return 0
	}
	return e.Actor.ID
}

func (e *PullRequestSynchronizeEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *PullRequestSynchronizeEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *PullRequestSynchronizeEvent) GetAgentID() int64 {
	return e.AgentID
}

// MergeConflictEvent represents a merge conflict detected on a pull request.
type MergeConflictEvent struct {
	Repo          *MergeConflictRepository
	PullRequestID int64
	BaseCommitOID string
	HeadCommitOID string
	ConflictPaths []string
	AgentID       int64
	Timestamp     time.Time
}

// MergeConflictRepository contains the minimal repository info available from
// the MergeConflict Hydro event (which only provides a repository ID).
type MergeConflictRepository struct {
	ID      int64
	OwnerID int64
}

func (e *MergeConflictEvent) GetActorID() int64 {
	// MergeConflict events have no actor; the PR author is resolved in the handler.
	return 0
}

func (e *MergeConflictEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *MergeConflictEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *MergeConflictEvent) GetAgentID() int64 {
	return e.AgentID
}

// AutomationRunRequestedEvent represents a user-initiated automation run request
// from copilot-mission-control. Contains only routing metadata; the full
// automation config is fetched from CMC via the existing ListForEvent path.
type AutomationRunRequestedEvent struct {
	AutomationID string
	Event        string
	Type         string
	ResourceURL  string
	OwnerLogin   string
	RepoName     string
	RepoID       int64
	OwnerID      int64
	UserID       int64
	UserLogin    string
	Conclusion   string
	AgentID      int64
	Timestamp    time.Time
}

func (e *AutomationRunRequestedEvent) GetActorID() int64 {
	return e.UserID
}

func (e *AutomationRunRequestedEvent) GetRepositoryID() int64 {
	return e.RepoID
}

func (e *AutomationRunRequestedEvent) GetOwnerID() int64 {
	return e.OwnerID
}

func (e *AutomationRunRequestedEvent) GetAgentID() int64 {
	return e.AgentID
}
