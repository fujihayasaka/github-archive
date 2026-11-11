package hydro

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	codescanningv0 "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	actionsv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/sweagentd"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Error to indicate that a message is not applicable and should be ignored.
var ErrMessageNotApplicable = errors.New("message not applicable")

// IsMessageNotApplicable is a helper function to check for [ErrMessageNotApplicable] errors.
func IsMessageNotApplicable(err error) bool {
	return errors.Is(err, ErrMessageNotApplicable)
}

type envelope interface {
	GetMessage() []byte
	GetTimestamp() *timestamppb.Timestamp
}

func EventForTopic(ctx context.Context, topic string, envelope envelope, p *agenticapp.Provider) (proto.Message, sweagentd.Event, error) {
	switch topic {
	case topics.PullRequestReviewSubmit:
		return GetEvent[*githubv1.PullRequestReviewSubmit, *events.PullRequestReviewSubmitEvent](ctx, envelope, p)

	case topics.PullRequestTimelineCommentCreate:
		return GetEvent[*githubv1.PullRequestTimelineCommentCreate, *events.PullRequestCommentCreatedEvent](ctx, envelope, p)

	case topics.PullRequestReopen:
		return GetEvent[*githubv1.PullRequestReopen, *events.PullRequestStateChangedEvent](ctx, envelope, p)

	case topics.PullRequestClose:
		return GetEvent[*githubv1.PullRequestClose, *events.PullRequestStateChangedEvent](ctx, envelope, p)

	case topics.PullRequestMerge:
		return GetEvent[*githubv1.PullRequestMerge, *events.PullRequestStateChangedEvent](ctx, envelope, p)

	case topics.WorkflowRunExecution:
		return GetEvent[*actionsv0.WorkflowRunExecution, *events.WorkflowRunCompletedEvent](ctx, envelope, p)

	case topics.CodeScanningAlertAssignment:
		return GetEvent[*codescanningv0.AlertsAssignment, *events.CodeScanningAlertsAssignmentEvent](ctx, envelope, p)

	case topics.IssueCreateTemplate:
		return GetEvent[*githubv1.IssueCreateTemplate, *events.IssueCreatedEvent](ctx, envelope, p)

	default:
		return nil, nil, fmt.Errorf("unknown topic: %s", topic)
	}
}

// GetEvent converts a hydro message to an event and returns the message and event.
// It returns an error if the message cannot be converted to the event type.
// The message and event types are determined by the type of the envelope and the message.
func GetEvent[M proto.Message, E sweagentd.Event](ctx context.Context, envelope envelope, p *agenticapp.Provider) (M, E, error) {
	var m M
	var e E

	evt := any(e)
	msg := any(m)

	message := envelope.GetMessage()
	timestamp := envelope.GetTimestamp().AsTime()

	var err error
	switch evt.(type) {
	case *events.PullRequestReviewSubmitEvent:
		msg, evt, err = getPullRequestReviewSubmitEvent(ctx, message, timestamp, p)
	case *events.PullRequestCommentCreatedEvent:
		msg, evt, err = getPullRequestCommentCreatedEvent(ctx, message, timestamp, p)
	case *events.PullRequestStateChangedEvent:
		switch msg.(type) {
		case *githubv1.PullRequestReopen:
			msg, evt, err = getPullRequestStateChangedEventForReopen(ctx, message, timestamp, p)
		case *githubv1.PullRequestClose:
			msg, evt, err = getPullRequestStateChangedEventForClose(ctx, message, timestamp, p)
		case *githubv1.PullRequestMerge:
			msg, evt, err = getPullRequestStateChangedEventForMerge(ctx, message, timestamp, p)
		}
	case *events.WorkflowRunCompletedEvent:
		msg, evt, err = getWorkflowRunCompletedEvent(ctx, message, timestamp, p)
	case *events.CodeScanningAlertsAssignmentEvent:
		msg, evt, err = getCodeScanningAlertsAssignmentEvent(ctx, message, p)
	case *events.IssueCreatedEvent:
		msg, evt, err = getIssueCreatedEvent(ctx, message, timestamp, p)
	default:
		return m, e, fmt.Errorf("unsupported message event type pair [%T,%T]", m, e)
	}

	switch {
	case err != nil:
		return m, e, fmt.Errorf("failed to convert message to event: %w", err)
	case msg == nil:
		return m, e, fmt.Errorf("failed to unmarshal message for %T", m)
	case evt == nil:
		return m, e, ErrMessageNotApplicable
	}

	return msg.(M), evt.(E), nil
}

// getPullRequestReviewSubmitEvent converts a [githubv1.PullRequestReviewSubmit] message to an [events.PullRequestReviewSubmitEvent].
func getPullRequestReviewSubmitEvent(ctx context.Context, msg []byte, timestamp time.Time, p *agenticapp.Provider) (*githubv1.PullRequestReviewSubmit, *events.PullRequestReviewSubmitEvent, error) {
	message := new(githubv1.PullRequestReviewSubmit)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}

	actor := getActor(message)
	if actor == nil {
		return nil, nil, errors.New("failed getting actor")
	}

	repo := getRepository(message)
	if repo == nil {
		return nil, nil, errors.New("failed getting repository")
	}

	pullRequest := getPullRequest(message)
	if pullRequest == nil {
		return nil, nil, errors.New("failed getting pull request")
	}

	pullRequestReview := getPullRequestReview(message)
	if pullRequestReview == nil {
		return nil, nil, errors.New("failed getting pull request review")
	}

	getAgent := func() (sweagentd.AgenticApp, bool) {
		if app, ok := p.IsAgenticMention(pullRequestReview.Body); ok {
			return app, true
		}

		for _, comment := range pullRequestReview.Comments {
			if app, ok := p.IsAgenticMention(comment); ok {
				return app, true
			}
		}

		// Handle the case where PR is from agentic author
		// and user is asking for changes via request changes without
		// mentioning the app directly.
		// Here we'll just check if the PR author is an app and
		// the rest of the conditions are checked in the event processing logic.
		if app, err := p.FindByBotID(pullRequest.AuthorID); err == nil {
			return app, true
		}

		return nil, false
	}

	var agentID int64
	if agent, ok := getAgent(); ok {
		agentID = agent.AppID()
	}

	event := &events.PullRequestReviewSubmitEvent{
		Actor:             actor,
		Repo:              repo,
		PullRequest:       pullRequest,
		PullRequestReview: pullRequestReview,
		EventUrl:          message.EventUrl,
		Timestamp:         timestamp,
		AgentID:           agentID,
	}

	if err := event.AddToRequestContext(ctx); err != nil {
		return nil, nil, fmt.Errorf("failed to add event to request context: %w", err)
	}

	return message, event, nil
}

// getPullRequestCommentCreatedEvent converts a [githubv1.PullRequestTimelineCommentCreate] message to an [events.PullRequestCommentCreatedEvent].
func getPullRequestCommentCreatedEvent(ctx context.Context, msg []byte, timestamp time.Time, p *agenticapp.Provider) (*githubv1.PullRequestTimelineCommentCreate, *events.PullRequestCommentCreatedEvent, error) {
	message := new(githubv1.PullRequestTimelineCommentCreate)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}

	actor := getActor(message)
	if actor == nil {
		return nil, nil, errors.New("failed getting actor")
	}

	repo := getRepository(message)
	if repo == nil {
		return nil, nil, errors.New("failed getting repository")
	}

	pullRequest := getPullRequestIssue(message)
	if pullRequest == nil {
		return nil, nil, errors.New("failed getting pull request")
	}

	pullRequestComment := getPullRequestComment(message)
	if pullRequestComment == nil {
		return nil, nil, errors.New("failed getting pull request comment")
	}

	var agentID int64
	if agent, ok := p.IsAgenticMention(pullRequestComment.Body); ok {
		agentID = agent.AppID()
	}

	event := &events.PullRequestCommentCreatedEvent{
		Actor:       actor,
		Repo:        repo,
		PullRequest: pullRequest,
		Comment:     pullRequestComment,
		EventUrl:    message.EventUrl,
		Timestamp:   timestamp,
		AgentID:     agentID,
	}

	if err := event.AddToRequestContext(ctx); err != nil {
		return nil, nil, fmt.Errorf("failed to add event to request context: %w", err)
	}

	return message, event, nil
}

func getPullRequestStateChangedEventForReopen(ctx context.Context, msg []byte, timestamp time.Time, p *agenticapp.Provider) (*githubv1.PullRequestReopen, *events.PullRequestStateChangedEvent, error) {
	message := new(githubv1.PullRequestReopen)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}
	evt, err := getPullRequestStateChangedEvent(ctx, message, timestamp, p)
	if err != nil {
		return nil, nil, err
	}
	return message, evt, nil
}

func getPullRequestStateChangedEventForClose(ctx context.Context, msg []byte, timestamp time.Time, p *agenticapp.Provider) (*githubv1.PullRequestClose, *events.PullRequestStateChangedEvent, error) {
	message := new(githubv1.PullRequestClose)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}
	evt, err := getPullRequestStateChangedEvent(ctx, message, timestamp, p)
	if err != nil {
		return nil, nil, err
	}
	return message, evt, nil
}

func getPullRequestStateChangedEventForMerge(ctx context.Context, msg []byte, timestamp time.Time, p *agenticapp.Provider) (*githubv1.PullRequestMerge, *events.PullRequestStateChangedEvent, error) {
	message := new(githubv1.PullRequestMerge)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}
	evt, err := getPullRequestStateChangedEvent(ctx, message, timestamp, p)
	if err != nil {
		return nil, nil, err
	}
	return message, evt, nil
}

type prStateChangedMessage interface {
	GetActor() *entities.User
	GetRepository() *entities.Repository
	GetRepositoryOwner() *entities.User
	GetPullRequest() *entities.PullRequest
	GetIssue() *entities.Issue
}

// getPullRequestStateChangedEvent converts a [githubv1.PullRequestReopen], [githubv1.PullRequestClose], or [githubv1.PullRequestMerge]
// message to an [events.PullRequestStateChangedEvent].
func getPullRequestStateChangedEvent(ctx context.Context, message prStateChangedMessage, timestamp time.Time, p *agenticapp.Provider) (*events.PullRequestStateChangedEvent, error) {
	actor := getActor(message)
	if actor == nil {
		return nil, errors.New("failed getting actor")
	}

	repo := getRepository(message)
	if repo == nil {
		return nil, errors.New("failed getting repository")
	}

	pullRequest := getPullRequest(message)
	if pullRequest == nil {
		return nil, errors.New("failed getting pull request")
	}

	var agentID int64
	if agent, err := p.FindByBotID(pullRequest.AuthorID); err == nil {
		agentID = agent.AppID()
	}

	event := &events.PullRequestStateChangedEvent{
		Actor:       actor,
		Repo:        repo,
		PullRequest: pullRequest,
		Timestamp:   timestamp,
		AgentID:     agentID,
	}

	if err := event.AddToRequestContext(ctx); err != nil {
		return nil, fmt.Errorf("failed to add event to request context: %w", err)
	}

	return event, nil
}

// getWorkflowRunCompletedEvent converts a [actionsv0.WorkflowRunExecution] message to an [events.WorkflowRunCompletedEvent].
func getWorkflowRunCompletedEvent(ctx context.Context, msg []byte, timestamp time.Time, p *agenticapp.Provider) (*actionsv0.WorkflowRunExecution, *events.WorkflowRunCompletedEvent, error) {
	message := new(actionsv0.WorkflowRunExecution)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}

	// TODO(colbylwilliams): There is currently an issue causing hydro events
	// to be sent with repository_owner_id = 0. This is a bug in the hydro
	// event producer and should be fixed. In the meantime, we can ignore
	// these events to avoid flooding the queue with errors.
	if message.RepositoryOwnerId == 0 {
		return nil, nil, ErrMessageNotApplicable
	}

	repo := getWorkflowRepository(message)
	if repo == nil {
		return nil, nil, errors.New("failed getting repository")
	}

	run := getWorkflowRun(message)
	if run == nil {
		return nil, nil, errors.New("failed getting workflow run")
	}

	var agentID int64
	parts := strings.Split(run.Path, "/") // dynamic/copilot-swe-agent/copilot
	if len(parts) > 2 {
		// Use the second part of the path as the agent login
		agentLogin := parts[1]
		if agent, ok := p.IsAgenticActor(agenticapp.ActorLoginFromString(agentLogin)); ok {
			agentID = agent.AppID()
		}
	}

	event := &events.WorkflowRunCompletedEvent{
		Repo:        repo,
		WorkflowRun: run,
		Timestamp:   timestamp,
		AgentID:     agentID,
	}

	if err := event.AddToRequestContext(ctx); err != nil {
		return nil, nil, fmt.Errorf("failed to add event to request context: %w", err)
	}

	return message, event, nil
}

// getCodeScanningAlertsAssignmentEvent converts a [codescanningv0.AlertsAssignment] message to an [events.CodeScanningAlertsAssignmentEvent].
func getCodeScanningAlertsAssignmentEvent(ctx context.Context, msg []byte, p *agenticapp.Provider) (*codescanningv0.AlertsAssignment, *events.CodeScanningAlertsAssignmentEvent, error) {
	message := new(codescanningv0.AlertsAssignment)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}

	actor := getActor(message)
	if actor == nil {
		return nil, nil, errors.New("failed getting actor")
	}

	repo := getRepository(message)
	if repo == nil {
		return nil, nil, errors.New("failed getting repository")
	}

	alerts := make([]*events.CodeScanningAlert, len(message.CodeScanningAlerts))
	for ix, alert := range message.CodeScanningAlerts {
		a := &events.CodeScanningAlert{
			Number: alert.AlertNumber,
			Title:  alert.AlertTitle,
			Url:    alert.AlertUrl,
			SuggestedFix: &events.SuggestedFix{
				Files: make([]*events.SuggestedFixFile, len(alert.SuggestedFix.Files)),
			},
		}
		for i, file := range alert.SuggestedFix.Files {
			f := &events.SuggestedFixFile{
				FilePath:    file.FilePath,
				DiffContent: []byte(file.DiffContent),
			}
			a.SuggestedFix.Files[i] = f
		}
		alerts[ix] = a
	}

	assignees := make([]string, 0, len(message.Assignees))
	for _, assignee := range message.Assignees {
		assignees = append(assignees, assignee.Login)
	}

	var agentID int64
	if agent, ok := p.HasAnyAgenticActor(agenticapp.ActorLoginsFromStrings(assignees)); ok {
		agentID = agent.AppID()
	}

	event := &events.CodeScanningAlertsAssignmentEvent{
		Actor:     actor,
		Repo:      repo,
		Alerts:    alerts,
		Assignees: assignees,
		EventUrl:  message.EventUrl,
		AgentID:   agentID,
	}

	if err := event.AddToRequestContext(ctx); err != nil {
		return nil, nil, fmt.Errorf("failed to add event to request context: %w", err)
	}

	return message, event, nil
}

// getIssueCreatedEvent converts an [githubv1.IssueCreateTemplate] message to an [events.IssueCreatedEvent].
func getIssueCreatedEvent(ctx context.Context, msg []byte, timestamp time.Time, p *agenticapp.Provider) (*githubv1.IssueCreateTemplate, *events.IssueCreatedEvent, error) {
	message := new(githubv1.IssueCreateTemplate)
	if err := proto.Unmarshal(msg, message); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal message: %w", err)
	}

	actor := getActor(message)
	if actor == nil {
		return nil, nil, errors.New("failed getting actor")
	}

	repo := getRepository(message)
	if repo == nil {
		return nil, nil, errors.New("failed getting repository")
	}

	owner := getRepositoryOwner(message)
	if owner == nil {
		return nil, nil, errors.New("failed getting repository owner")
	}

	issue := getIssue(message)
	if issue == nil {
		return nil, nil, errors.New("failed getting issue")
	}

	// TODO(colbylwilliams): Should we filter out issues not created by agentic apps?

	// Today custom agent triggers are only supported by copilot, so we force
	// the agent ID to be copilot's app ID here.
	agentID := p.CopilotApp().AppID()

	event := &events.IssueCreatedEvent{
		Actor:     actor,
		Repo:      repo,
		Owner:     owner,
		Issue:     issue,
		AgentID:   agentID,
		Timestamp: timestamp,
	}

	if err := event.AddToRequestContext(ctx); err != nil {
		return nil, nil, fmt.Errorf("failed to add event to request context: %w", err)
	}

	return message, event, nil
}

// getActor returns an [events.Actor] from a given [entities.User].
func getActor(message interface {
	GetActor() *entities.User
},
) *events.Actor {
	user := message.GetActor()
	if user == nil {
		return nil
	}
	return &events.Actor{
		ID:           int64(user.Id),
		NodeID:       getGlobalID(user),
		Login:        user.Login,
		DisplayLogin: user.DisplayLogin,
		TrackingID:   user.AnalyticsTrackingId,
		Type:         user.Type.String(),
	}
}

// getRepository returns an [events.Repository] from a given [entities.Repository]
func getRepository(message interface {
	GetRepository() *entities.Repository
},
) *events.Repository {
	repo := message.GetRepository()
	if repo == nil {
		return nil
	}
	var ownerID int64
	if repo.OwnerId != nil {
		ownerID = int64(repo.OwnerId.Value)
	}
	return &events.Repository{
		ID:            int64(repo.Id),
		NodeID:        getGlobalID(repo),
		Name:          repo.Name,
		OwnerID:       ownerID,
		DefaultBranch: repo.DefaultBranch,
		IsPrivate:     repo.Visibility == entities.Repository_PRIVATE || repo.Visibility == entities.Repository_INTERNAL,
	}
}

func getRepositoryOwner(message interface {
	GetRepositoryOwner() *entities.User
},
) *events.Actor {
	user := message.GetRepositoryOwner()
	if user == nil {
		return nil
	}
	return &events.Actor{
		ID:           int64(user.Id),
		NodeID:       getGlobalID(user),
		Login:        user.Login,
		DisplayLogin: user.DisplayLogin,
		TrackingID:   user.AnalyticsTrackingId,
		Type:         user.Type.String(),
	}
}

// getIssue returns an [events.Issue] from a given [entities.Issue].
func getIssue(message interface {
	GetIssue() *entities.Issue
},
) *events.Issue {
	issue := message.GetIssue()
	if issue == nil {
		return nil
	}
	return &events.Issue{
		ID:     getID(issue),
		NodeID: issue.GlobalRelayId,
		Number: int(issue.Number),
		IsOpen: issue.IssueState == entities.Issue_OPEN,
	}
}

// getPullRequestIssue returns an [events.PullRequestIssue] from a given [entities.Issue].
func getPullRequestIssue(message interface {
	GetIssue() *entities.Issue
},
) *events.PullRequestIssue {
	issue := message.GetIssue()
	if issue == nil {
		return nil
	}
	return &events.PullRequestIssue{
		NodeID: issue.GlobalRelayId,
		Number: int(issue.Number),
		IsOpen: issue.IssueState == entities.Issue_OPEN,
	}
}

// getPullRequest returns an [events.PullRequest] from a given [entities.PullRequest] and [entities.Issue].
func getPullRequest(message interface {
	GetIssue() *entities.Issue
	GetPullRequest() *entities.PullRequest
},
) *events.PullRequest {
	issue := message.GetIssue()
	pr := message.GetPullRequest()
	if issue == nil || pr == nil {
		return nil
	}
	eventsPR := &events.PullRequest{
		ID:       int64(pr.Id),
		NodeID:   pr.GlobalRelayId,
		Number:   int(issue.Number),
		IsOpen:   pr.PullRequestState == entities.PullRequest_OPEN,
		IsDraft:  &pr.Draft,
		AuthorID: int64(pr.AuthorId),
	}

	headBranch := string(pr.HeadBranch)
	if headBranch != "" {
		eventsPR.HeadBranch = headBranch
	}

	baseBranch := string(pr.BaseBranch)
	if baseBranch != "" {
		eventsPR.BaseBranch = baseBranch
	}

	switch pr.PullRequestState {
	case entities.PullRequest_OPEN:
		eventsPR.State = events.PullRequestStateOpen
	case entities.PullRequest_CLOSED:
		eventsPR.State = events.PullRequestStateClosed
	case entities.PullRequest_MERGED:
		eventsPR.State = events.PullRequestStateMerged
	default:
		eventsPR.State = "" // Unknown state
	}

	return eventsPR
}

// getPullRequestComment returns an [events.PullRequestComment] from a given [entities.IssueComment].
func getPullRequestComment(message interface {
	GetIssueComment() *entities.IssueComment
	GetBody() string
},
) *events.PullRequestComment {
	comment := message.GetIssueComment()
	if comment == nil {
		return nil
	}

	body := message.GetBody()
	return &events.PullRequestComment{
		ID:     getID(comment),
		NodeID: comment.GlobalRelayId,
		Body:   body,
	}
}

// getPullRequestReview returns an [events.PullRequestReview] from a given [entities.PullRequestReview].
func getPullRequestReview(message interface {
	GetPullRequestReview() *entities.PullRequestReview
	GetComments() []*entities.PullRequestReviewComment
},
) *events.PullRequestReview {
	review := message.GetPullRequestReview()
	if review == nil {
		return nil
	}

	comments := make([]string, len(message.GetComments()))
	for i, comment := range message.GetComments() {
		comments[i] = comment.Body
	}

	return &events.PullRequestReview{
		ID:       int64(review.Id),
		Body:     review.Body,
		Comments: comments,
	}
}

// getWorkflowRepository returns an [events.WorkflowRepository] from a given job.
func getWorkflowRepository(job interface {
	GetRepositoryId() int64
	GetRepositoryOwnerId() int64
},
) *events.WorkflowRepository {
	if job == nil {
		return nil
	}
	if job.GetRepositoryId() == 0 || job.GetRepositoryOwnerId() == 0 {
		return nil
	}
	return &events.WorkflowRepository{
		ID:      job.GetRepositoryId(),
		OwnerID: job.GetRepositoryOwnerId(),
	}
}

// getWorkflowRun returns an [events.WorkflowRun] from a given [actionsv0.WorkflowRunExecution].
func getWorkflowRun(job *actionsv0.WorkflowRunExecution) *events.WorkflowRun {
	if job == nil {
		return nil
	}
	run := &events.WorkflowRun{
		ID:           int64(job.WorkflowRunId),
		Path:         job.WorkflowRunPath, // dynamic/copilot-swe-agent/copilot
		UserID:       job.ActorId,         // only interested in copilot (id)
		CheckSuiteID: job.CheckSuiteId,
		Status:       job.Status,
		Conclusion:   workflowConclusion(job),
		Attempt:      int(job.Attempt),
		UsageMs:      workflowUsageMS(job),
	}
	if job.CompletedAt != nil {
		run.CompletedAt = job.CompletedAt.AsTime().Unix()
	}
	if job.StartedAt != nil {
		run.StartedAt = job.StartedAt.AsTime().Unix()
	}
	return run
}

func workflowConclusion(job *actionsv0.WorkflowRunExecution) string {
	if job == nil {
		return ""
	}
	switch job.Conclusion {
	case events.WorkflowCompletedEventConclusionSuccess:
		return events.WorkflowCompletedEventConclusionSuccess
	case events.WorkflowCompletedEventConclusionCancelled:
		return events.WorkflowCompletedEventConclusionCancelled
	default:
		return events.WorkflowCompletedEventConclusionFailure
	}
}

func workflowUsageMS(job interface {
	GetStartedAt() *timestamppb.Timestamp
	GetCompletedAt() *timestamppb.Timestamp
},
) int64 {
	if job == nil {
		return 0
	}
	if job.GetStartedAt() == nil || job.GetCompletedAt() == nil {
		return 0
	}
	return job.GetCompletedAt().AsTime().Sub(job.GetStartedAt().AsTime()).Milliseconds()
}

// getID returns the value of IdValue if it exists, otherwise it returns the value of Id as an int64.
func getID(e interface {
	GetId() uint32
	GetIdValue() int64
},
) int64 {
	if idv := e.GetIdValue(); idv != 0 {
		return idv
	}
	return int64(e.GetId())
}

// getGlobalID returns the value of NextGlobalId if it exists, otherwise it returns the value of GlobalRelayId.
func getGlobalID(e interface {
	GetGlobalRelayId() string
	GetNextGlobalId() string
},
) string {
	if id := e.GetNextGlobalId(); id != "" {
		return id
	}
	if id := e.GetGlobalRelayId(); id != "" {
		return id
	}
	return ""
}
