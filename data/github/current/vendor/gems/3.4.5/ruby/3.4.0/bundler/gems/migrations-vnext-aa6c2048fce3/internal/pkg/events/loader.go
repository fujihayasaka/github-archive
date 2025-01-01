// Package events contains business logic for loading events.
package events

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/migrationctx"
	octoshift "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// Loader defines the methods required to load events.
type Loader interface {
	LoadEvent(ctx context.Context, event *v1.Event) error
}

// EventLoader is a struct for loading events.
type EventLoader struct {
	importClient client.Importer
	kvRedis      KVResolver
	logger       log.Logger
	statter      stats.Client
}

// KVResolver is an interface that defines the methods that are required to keep track
// of the resource IDs translations
type KVResolver interface {
	ResolveInt64Resource(ctx context.Context, namespace, key string) (int64, error)
	ResolveStringResource(ctx context.Context, namespace, key string) (string, error)
	ResourceExists(ctx context.Context, namespace, key string) (bool, error)
}

// New returns an initialized EventLoader.
func New(importClient client.Importer, kv *resource.KVRedis, logger log.Logger, statter stats.Client) *EventLoader {
	return &EventLoader{
		importClient: importClient,
		kvRedis:      kv,
		logger:       logger,
		statter:      statter,
	}
}

// LoadEvent loads an event.
func (l *EventLoader) LoadEvent(ctx context.Context, event *v1.Event) error {
	ns, err := migrationctx.Namespace(event)
	if err != nil {
		return fmt.Errorf("failed to get namespace: %w", err)
	}

	switch d := event.EventDetails.(type) {
	case *v1.Event_IssueEvent:
		err = l.issueEventRouter(ctx, ns, event, d.IssueEvent)
	case *v1.Event_IssueCommentEvent:
		err = l.issueCommentEventRouter(ctx, ns, event, d.IssueCommentEvent)
	case *v1.Event_PullRequestEvent:
		err = l.pullRequestEventRouter(ctx, ns, event, d.PullRequestEvent)
	case *v1.Event_PullRequestReviewEvent:
		err = l.pullRequestReviewEventRouter(ctx, ns, event, d.PullRequestReviewEvent)
	case *v1.Event_PullRequestReviewCommentEvent:
		err = l.pullRequestReviewCommentEventRouter(ctx, ns, event, d.PullRequestReviewCommentEvent)
	case *v1.Event_PullRequestReviewThreadEvent:
		err = l.pullRequestReviewThreadEventRouter(ctx, ns, event, d.PullRequestReviewThreadEvent)
	}
	return err
}

func (l *EventLoader) issueEventRouter(ctx context.Context, namespace string, event *v1.Event, edit *v1.Issue) error {
	l.logger.Info("processing issue event edit",
		kvp.String("namespace", namespace),
		kvp.String("id", event.EventId),
		kvp.String("resource_id", event.ResourceId),
		kvp.String("action", event.EventAction.String()),
		kvp.String("user", edit.UserResourceId),
		kvp.String("title", edit.Title),
		kvp.String("body", edit.Body),
		kvp.Any("assignees", edit.AssigneesResourceIds),
		kvp.Time("updated_at", edit.UpdatedAt.AsTime()),
		kvp.Time("closed_at", edit.ClosedAt.AsTime()))

	// Resolve dependencies: issue, user, assignees
	id, err := l.kvRedis.ResolveInt64Resource(ctx, namespace, event.ResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve issue ID from issue resource: %w", err)
	}

	user, err := l.kvRedis.ResolveStringResource(ctx, namespace, edit.UserResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve user from issue resource: %w", err)
	}

	var assignees []string
	for _, a := range edit.AssigneesResourceIds {
		assignee, err := l.kvRedis.ResolveStringResource(ctx, namespace, a)
		if err != nil {
			return fmt.Errorf("failed to resolve assignee from issue comment resource: %w", err)
		}
		assignees = append(assignees, assignee)
	}

	state := octoshift.EditIssueState_EDIT_ISSUE_STATE_OPEN
	if edit.ClosedAt != nil && !edit.ClosedAt.AsTime().IsZero() {
		state = octoshift.EditIssueState_EDIT_ISSUE_STATE_CLOSED
	}
	req := &octoshift.EditIssueRequest{
		Id:        id,
		Title:     edit.Title,
		Body:      wrapperspb.String(edit.Body),
		UpdatedAt: event.Timestamp,
		UserLogin: user,
		Action:    octoshift.LiveMigrationAction_LIVE_MIGRATION_ACTION_EDITED,
		Assignees: assignees,
		State:     state,
	}

	l.logger.Info("editing issue", kvp.Any("request", req))

	if _, err = l.importClient.EditIssue(ctx, req); err != nil {
		return fmt.Errorf("failed to edit issue: %w", err)
	}

	return nil
}

func (l *EventLoader) issueCommentEventRouter(ctx context.Context, namespace string, event *v1.Event, edit *v1.IssueComment) error {
	l.logger.Info("processing issue comment event edit",
		kvp.String("namespace", namespace),
		kvp.String("id", event.EventId),
		kvp.String("resource_id", event.ResourceId),
		kvp.String("action", event.EventAction.String()),
		kvp.String("user", edit.UserResourceId),
		kvp.String("body", edit.Body),
		kvp.Time("updated_at", event.GetTimestamp().AsTime()))

	id, err := l.kvRedis.ResolveInt64Resource(ctx, namespace, event.ResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve issue comment ID from issue comment resource: %w", err)
	}

	user, err := l.kvRedis.ResolveStringResource(ctx, namespace, edit.UserResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve user from issue comment resource: %w", err)
	}

	req := &octoshift.EditIssueCommentRequest{
		Id:        id,
		Body:      edit.Body,
		UpdatedAt: event.Timestamp,
		UserLogin: user,
		Action:    octoshift.LiveMigrationAction_LIVE_MIGRATION_ACTION_EDITED,
	}

	l.logger.Info("editing issue comment", kvp.Any("request", req))

	if _, err = l.importClient.EditIssueComment(ctx, req); err != nil {
		return fmt.Errorf("failed to edit issue comment: %w", err)
	}

	return nil
}

func (l *EventLoader) pullRequestEventRouter(ctx context.Context, namespace string, event *v1.Event, edit *v1.PullRequest) error {
	l.logger.Info("processing pull request event edit",
		kvp.String("namespace", namespace),
		kvp.String("id", event.EventId),
		kvp.String("resource_id", event.ResourceId),
		kvp.String("action", event.EventAction.String()),
		kvp.String("user", edit.UserResourceId),
		kvp.String("title", edit.Title),
		kvp.String("body", edit.Body),
		kvp.Any("assignees", edit.AssigneesResourceIds),
		kvp.Time("updated_at", event.Timestamp.AsTime()),
		kvp.Time("closed_at", edit.ClosedAt.AsTime()),
		kvp.Time("merged_at", edit.MergedAt.AsTime()),
		kvp.String("base_ref", edit.BaseRef.Name),
		kvp.String("merge_sha", edit.MergeCommitSha),
		kvp.Bool("is_draft", edit.IsDraft))

	id, err := l.kvRedis.ResolveInt64Resource(ctx, namespace, event.ResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve pull request ID from pull request resource: %w", err)
	}

	user, err := l.kvRedis.ResolveStringResource(ctx, namespace, edit.UserResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve user from pull request resource: %w", err)
	}

	var assignees []string
	for _, a := range edit.AssigneesResourceIds {
		assignee, err := l.kvRedis.ResolveStringResource(ctx, namespace, a)
		if err != nil {
			return fmt.Errorf("failed to resolve assignee from pull request resource: %w", err)
		}
		assignees = append(assignees, assignee)
	}

	req := &octoshift.EditPullRequestRequest{
		Id:        id,
		Title:     edit.Title,
		Body:      wrapperspb.String(edit.Body),
		UpdatedAt: event.Timestamp,
		UserLogin: user,
		Assignees: assignees,
		BaseRef:   edit.BaseRef.Name,
	}

	switch {
	case edit.MergedAt != nil && !edit.MergedAt.AsTime().IsZero():
		req.State = octoshift.EditPullRequestState_EDIT_PULL_REQUEST_STATE_MERGED
		req.MergedAt = edit.MergedAt
		req.MergeCommitSha = wrapperspb.String(edit.MergeCommitSha)
	case edit.ClosedAt != nil && !edit.ClosedAt.AsTime().IsZero():
		req.State = octoshift.EditPullRequestState_EDIT_PULL_REQUEST_STATE_CLOSED
		req.ClosedAt = edit.ClosedAt
	default:
		req.State = octoshift.EditPullRequestState_EDIT_PULL_REQUEST_STATE_OPEN
	}

	switch edit.IsDraft {
	case true:
		req.ReviewableState = octoshift.EditPullRequestReviewableState_EDIT_PULL_REQUEST_REVIEWABLE_STATE_DRAFT
	case false:
		req.ReviewableState = octoshift.EditPullRequestReviewableState_EDIT_PULL_REQUEST_REVIEWABLE_STATE_READY_FOR_REVIEW
	}

	l.logger.Info("editing pull request", kvp.Any("request", req))

	if _, err = l.importClient.EditPullRequest(ctx, req); err != nil {
		return fmt.Errorf("failed to edit pull request: %w", err)
	}

	return nil
}

func (l *EventLoader) pullRequestReviewThreadEventRouter(ctx context.Context, namespace string, event *v1.Event, edit *v1.PullRequestReviewThreadEventEdit) error {
	l.logger.Info("processing pull request review thread event edit",
		kvp.String("namespace", namespace),
		kvp.String("id", event.EventId),
		kvp.String("resource_id", event.ResourceId),
		kvp.String("action", event.EventAction.String()),
		kvp.String("user", edit.UserResourceId),
		kvp.Int64("thread_id", edit.ThreadId),
		kvp.Int64("first_comment_id", edit.FirstCommentId),
		kvp.Bool("resolved", edit.Resolved),
		kvp.Time("updated_at", edit.UpdatedAt.AsTime()))

	id, err := l.kvRedis.ResolveInt64Resource(ctx, namespace, event.ResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve thread ID from pull request review thread event: %w", err)
	}

	user, err := l.kvRedis.ResolveStringResource(ctx, namespace, edit.UserResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve user from pull request review thread resource: %w", err)
	}

	state := octoshift.EditPullRequestReviewThreadState_EDIT_PULL_REQUEST_REVIEW_THREAD_STATE_RESOLVED
	if !edit.Resolved {
		state = octoshift.EditPullRequestReviewThreadState_EDIT_PULL_REQUEST_REVIEW_THREAD_STATE_UNRESOLVED
	}
	req := &octoshift.EditPullRequestReviewThreadRequest{
		Id:         id,
		Action:     octoshift.LiveMigrationAction_LIVE_MIGRATION_ACTION_EDITED,
		UpdatedAt:  event.Timestamp,
		ResolvedAt: event.Timestamp,
		UserLogin:  user,
		State:      state,
	}

	l.logger.Info("editing pull request review thread", kvp.Any("request", req))

	if _, err = l.importClient.EditPullRequestReviewThread(ctx, req); err != nil {
		return fmt.Errorf("failed to edit pull request review thread: %w", err)
	}

	return nil
}

func (l *EventLoader) pullRequestReviewEventRouter(ctx context.Context, namespace string, event *v1.Event, edit *v1.PullRequestReviewEventEdit) error {
	l.logger.Info("processing pull request review event edit",
		kvp.String("namespace", namespace),
		kvp.String("id", event.EventId),
		kvp.String("resource_id", event.ResourceId),
		kvp.String("action", event.EventAction.String()),
		kvp.String("user", edit.UserResourceId),
		kvp.String("body", edit.Body),
		kvp.Time("updated_at", event.Timestamp.AsTime()))

	id, err := l.kvRedis.ResolveInt64Resource(ctx, namespace, event.ResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve thread ID from pull request review event: %w", err)
	}

	user, err := l.kvRedis.ResolveStringResource(ctx, namespace, edit.UserResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve user from pull request review event: %w", err)
	}

	req := &octoshift.EditPullRequestReviewRequest{
		Id:        id,
		UserLogin: user,
		Body:      wrapperspb.String(edit.Body),
		UpdatedAt: event.Timestamp,
	}

	l.logger.Info("editing pull request review", kvp.Any("request", req))

	if _, err = l.importClient.EditPullRequestReview(ctx, req); err != nil {
		return fmt.Errorf("failed to edit pull request review: %w", err)
	}

	return nil
}

func (l *EventLoader) pullRequestReviewCommentEventRouter(ctx context.Context, namespace string, event *v1.Event, edit *v1.PullRequestReviewCommentEventEdit) error {
	l.logger.Info("processing pull request review comment event edit",
		kvp.String("namespace", namespace),
		kvp.String("id", event.EventId),
		kvp.String("resource_id", event.ResourceId),
		kvp.String("action", event.EventAction.String()),
		kvp.String("user", edit.UserResourceId),
		kvp.String("body", edit.Body),
		kvp.Time("updated_at", event.Timestamp.AsTime()))

	id, err := l.kvRedis.ResolveInt64Resource(ctx, namespace, event.ResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve comment ID from pull request review comment event: %w", err)
	}

	user, err := l.kvRedis.ResolveStringResource(ctx, namespace, edit.UserResourceId)
	if err != nil {
		return fmt.Errorf("failed to resolve user from pull request review comment event: %w", err)
	}

	req := &octoshift.EditPullRequestReviewCommentRequest{
		Id:        id,
		Action:    octoshift.LiveMigrationAction_LIVE_MIGRATION_ACTION_EDITED,
		UserLogin: user,
		Body:      wrapperspb.String(edit.Body),
		UpdatedAt: event.Timestamp,
	}

	l.logger.Info("editing pull request review comment", kvp.Any("request", req))

	if _, err = l.importClient.EditPullRequestReviewComment(ctx, req); err != nil {
		return fmt.Errorf("failed to edit pull request review comment: %w", err)
	}

	return nil
}
