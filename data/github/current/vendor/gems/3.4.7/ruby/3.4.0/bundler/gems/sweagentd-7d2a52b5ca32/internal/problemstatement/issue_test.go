package problemstatement

import (
	"cmp"
	"context"
	"slices"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
)

func TestIssueCommentOrderingAndFiltering(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	actx := getIssueContext()

	actx.Issue.Comments.Nodes = []github.GQLIssueComment{ // out of order
		*testIssueComment(*actorWriter(), false, 101, "comment writer one"),
		*testIssueComment(*actorWriter(), true, 102, "comment minimized"), // minimized
		*testIssueComment(*actorBot(), false, 104, "comment bot"),         // bot
		*testIssueComment(*actorReader(), false, 105, "comment reader"),   // reader
		*testIssueComment(*actorCopilot(), false, 103, "comment copilot"), // copilot
		*testIssueComment(*actorWriter(), false, 106, "comment writer six"),
	}

	problemStatement, err := NewIssueBuilder(obsv, gh, actx, mockAuthorResolver{}).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content
	commitCount := problemStatement.CommitCount

	require.NotEmpty(t, statement)

	require.Contains(t, statement, "comment writer one")
	require.Contains(t, statement, "comment writer six")
	require.Contains(t, statement, "comment copilot")

	require.NotContains(t, statement, "comment bot") // ??
	require.NotContains(t, statement, "comment reader")
	require.NotContains(t, statement, "comment minimized")

	type index struct {
		Index     int
		Timestamp int64
	}
	indexes := []index{}

	// Find the indexes of the comments in the statement
	for _, comment := range actx.Issue.Comments.Nodes {
		i := strings.Index(statement, comment.Body)
		if i >= 0 {
			indexes = append(indexes, index{
				Index:     i,
				Timestamp: comment.PublishedAt.Unix(),
			})
		}
	}

	// Sort the indexes so we can check the order of the comments
	slices.SortFunc(indexes, func(i, j index) int {
		return cmp.Compare(i.Index, j.Index)
	})

	// Check the indexes are sorted by published at date
	isSorted := slices.IsSortedFunc(indexes, func(i, j index) int {
		return cmp.Compare(i.Timestamp, j.Timestamp)
	})
	require.True(t, isSorted, "issue comments are not sorted by published at date")

	// For issue problem statements, make sure we don't include the revision section
	require.NotContains(t, statement, "git commits in this branch")
	require.Zero(t, commitCount, "commit count is not zero for issue problem statement")
}

func TestIssueCommentCountAutoReduction(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	actx := getIssueContext()

	actx.Issue.Comments.Nodes = []github.GQLIssueComment{
		*testIssueComment(*actorWriter(), false, 101, "comment writer one"),
		*testIssueComment(*actorWriter(), false, 102, "comment writer two"),
		*testIssueComment(*actorWriter(), false, 103, "comment writer three"),
		*testIssueComment(*actorWriter(), false, 104, "comment writer four"),
		*testIssueComment(*actorWriter(), false, 105, "comment writer five"),
	}

	actx.Issue.Comments.Nodes[2].Body = actx.Issue.Comments.Nodes[2].Body + strings.Repeat("-", tooBigCharacterCount)
	actx.Issue.Comments.Nodes[3].Body = actx.Issue.Comments.Nodes[3].Body + strings.Repeat("-", tooBigCharacterCount)

	problemStatement, err := NewIssueBuilder(obsv, gh, actx, mockAuthorResolver{}).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content
	commitCount := problemStatement.CommitCount

	require.NotEmpty(t, statement)
	// Too long comments should be truncated
	require.Contains(t, statement, "----...")
	// But all comments should be present
	require.Contains(t, statement, "writer one")
	require.Contains(t, statement, "writer two")
	require.Contains(t, statement, "writer three")
	require.Contains(t, statement, "writer four")
	require.Contains(t, statement, "writer five")

	// For issue problem statements, make sure we don't include the revision section
	require.NotContains(t, statement, "git commits in this branch")
	require.Zero(t, commitCount, "commit count is not zero for issue problem statement")
}

func TestIssueBuilder_AuthorResolverIntegration(t *testing.T) {
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	err := requestctx.AddTenantSlug(ctx, "test-org")
	require.NoError(t, err)

	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{GithubAppLogin: GitHubAppLogin, GithubBotLogin: GitHubBotLogin}

	actx := getIssueContext()

	// Add comments from different types of users
	// Note: based on existing tests, bot comments get filtered out,
	// so we focus on writer and copilot comments which are included
	actx.Issue.Comments.Nodes = []github.GQLIssueComment{
		*testIssueComment(*actorWriter(), false, 101, "comment from writer user"),
		*testIssueComment(*actorCopilot(), false, 102, "comment from copilot"),
	}

	assigner := *actorWriter()

	expectedDisplayLogin := "resolved-display-name"
	problemStatement, err := NewIssueBuilder(obsv, gh, actx, mockAuthorResolver{expectedID: uint64(assigner.GetID()), expectedDisplayLogin: expectedDisplayLogin}).Build(ctx)
	require.NoError(t, err)

	statement := problemStatement.Content

	require.NotEmpty(t, statement)

	// Verify that the resolved display login is used for the writer user
	require.Contains(t, statement, "@"+expectedDisplayLogin, "problem statement should contain resolved display login")
	require.Contains(t, statement, "comment from writer user")

	// Verify that copilot comments use @copilot (not resolved via author resolver)
	require.Contains(t, statement, "@copilot")
	require.Contains(t, statement, "comment from copilot")

	// Ensure we don't have the original login in the statement since it should be resolved
	require.NotContains(t, statement, "@"+actorWriter().GetLogin(), "should not contain original login, should be resolved")
}
