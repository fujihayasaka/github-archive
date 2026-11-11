package events

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
)

func TestRequestContext(t *testing.T) {

	t.Run("add PullRequestReviewSubmitEvent to context", func(t *testing.T) {
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		review := &PullRequestReview{
			ID: 1234,
		}
		event := &PullRequestReviewSubmitEvent{
			Actor:             EventActorWriter(),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: review,
		}
		err := event.AddToRequestContext(ctx)
		require.NoError(t, err)

		user, ok := requestctx.User(ctx)
		require.True(t, ok)
		require.EqualValues(t, event.Actor.ID, user.ID)
		require.Equal(t, event.Actor.Login, user.Login)
		require.Equal(t, event.Actor.TrackingID, user.TrackingID)

		repo, ok := requestctx.Repo(ctx)
		require.True(t, ok)
		require.Equal(t, event.Repo.ID, repo.ID)
		require.Equal(t, event.Repo.OwnerID, repo.OwnerID)

		pr, ok := requestctx.PullRequest(ctx)
		require.True(t, ok)
		require.Equal(t, event.PullRequest.ID, *pr.ID)
		require.Equal(t, event.PullRequest.Number, pr.Number)
		require.Equal(t, event.PullRequest.State, pr.State)
		require.Equal(t, event.PullRequestReview.ID, *pr.ReviewID)

	})

	t.Run("add PullRequestCommentCreatedEvent to context", func(t *testing.T) {
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		comment := &PullRequestComment{
			ID: 1234,
		}
		event := &PullRequestCommentCreatedEvent{
			Actor:       EventActorWriter(),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment:     comment,
		}
		err := event.AddToRequestContext(ctx)
		require.NoError(t, err)

		user, ok := requestctx.User(ctx)
		require.True(t, ok)
		require.EqualValues(t, event.Actor.ID, user.ID)
		require.Equal(t, event.Actor.Login, user.Login)
		require.Equal(t, event.Actor.TrackingID, user.TrackingID)

		repo, ok := requestctx.Repo(ctx)
		require.True(t, ok)
		require.Equal(t, event.Repo.ID, repo.ID)
		require.Equal(t, event.Repo.OwnerID, repo.OwnerID)

		pr, ok := requestctx.PullRequest(ctx)
		require.True(t, ok)
		require.Nil(t, pr.ID)
		require.Equal(t, event.PullRequest.Number, pr.Number)
		if event.PullRequest.IsOpen {
			require.Equal(t, "open", pr.State)
		} else {
			require.Equal(t, "", pr.State)
		}
		require.Equal(t, event.Comment.ID, *pr.CommentID)
	})

	t.Run("add PullRequestStateChangeEvent to context", func(t *testing.T) {
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		event := &PullRequestStateChangedEvent{
			Actor:       EventActorWriter(),
			Repo:        EventRepository(),
			PullRequest: EventPullRequest(),
		}
		err := event.AddToRequestContext(ctx)
		require.NoError(t, err)

		user, ok := requestctx.User(ctx)
		require.True(t, ok)
		require.EqualValues(t, event.Actor.ID, user.ID)
		require.Equal(t, event.Actor.Login, user.Login)
		require.Equal(t, event.Actor.TrackingID, user.TrackingID)

		repo, ok := requestctx.Repo(ctx)
		require.True(t, ok)
		require.Equal(t, event.Repo.ID, repo.ID)
		require.Equal(t, event.Repo.OwnerID, repo.OwnerID)

		pr, ok := requestctx.PullRequest(ctx)
		require.True(t, ok)
		require.Equal(t, event.PullRequest.ID, *pr.ID)
		require.Equal(t, event.PullRequest.Number, pr.Number)
		require.Equal(t, event.PullRequest.State, pr.State)
	})

	t.Run("add WorkflowRunCompletedEvent to context", func(t *testing.T) {
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		event := &WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRun(),
		}
		err := event.AddToRequestContext(ctx)
		require.NoError(t, err)

		repo, ok := requestctx.Repo(ctx)
		require.True(t, ok)
		require.Equal(t, event.Repo.ID, repo.ID)
		require.Equal(t, event.Repo.OwnerID, repo.OwnerID)

		run, ok := requestctx.WorkflowRun(ctx)
		require.True(t, ok)
		require.Equal(t, event.WorkflowRun.ID, run.ID)
	})

	t.Run("add CodeScanningAlertsAssignmentEvent to context", func(t *testing.T) {
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		event := &CodeScanningAlertsAssignmentEvent{
			Actor: EventActorAdmin(),
			Repo:  EventRepository(),
			Alerts: []*CodeScanningAlert{
				{Number: 1},
				{Number: 2},
			},
			Assignees: []string{"user1", "user2"},
		}
		err := event.AddToRequestContext(ctx)
		require.NoError(t, err)

		user, ok := requestctx.User(ctx)
		require.True(t, ok)
		require.EqualValues(t, event.Actor.ID, user.ID)
		require.Equal(t, event.Actor.Login, user.Login)
		require.Equal(t, event.Actor.TrackingID, user.TrackingID)

		repo, ok := requestctx.Repo(ctx)
		require.True(t, ok)
		require.Equal(t, event.Repo.ID, repo.ID)
		require.Equal(t, event.Repo.OwnerID, repo.OwnerID)
	})
}
