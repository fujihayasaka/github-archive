package events

import (
	"context"
	"testing"

	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestShouldIgnorePRCommentOrReview(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	handler, _, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)

	t.Run("ignores closed PR", func(t *testing.T) {
		pr := EventPullRequest()
		pr.IsOpen = false

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorWriter())

		require.NoError(t, err)
		require.True(t, ignore, "Should ignore comments on closed PRs")
	})

	t.Run("ignores comments from Copilot", func(t *testing.T) {
		pr := EventPullRequest()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorCopilot())

		require.NoError(t, err)
		require.True(t, ignore, "Should ignore comments from Copilot")
	})

	t.Run("ignores comments from bot users", func(t *testing.T) {
		pr := EventPullRequest()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorBot())

		require.NoError(t, err)
		require.True(t, ignore, "Should ignore comments from bots")
	})

	t.Run("ignores comments from users without write access", func(t *testing.T) {
		gh := ghFactory.NewClient("test-token")

		hasPermissions, err := handler.PRCommentOrReviewAuthorHasPushPermissions(ctx, gh, EventRepository(), EventActorReader())
		require.NoError(t, err)
		require.False(t, hasPermissions, "User should not have write access")
	})

	t.Run("processes comments from users with write access", func(t *testing.T) {
		pr := EventPullRequest()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorAdmin())

		require.NoError(t, err)
		require.False(t, ignore, "Should not ignore comments from users with write access")
	})

	t.Run("processes comments when pr ID is nil", func(t *testing.T) {
		pr := EventPullRequestIssue()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorAdmin())

		require.NoError(t, err)
		require.False(t, ignore, "Should not ignore comments from users with write access")
	})
}
