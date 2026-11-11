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
	DefaultBranch string
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
	AgentID           int64
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
	AgentID     int64
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

type WorkflowRunCompletedEvent struct {
	Repo        *WorkflowRepository
	WorkflowRun *WorkflowRun
	Timestamp   time.Time
	AgentID     int64
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

type CodeScanningAlertsAssignmentEvent struct {
	Actor     *Actor
	Repo      *Repository
	Alerts    []*CodeScanningAlert
	Assignees []string
	EventUrl  string
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
