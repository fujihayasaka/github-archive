package hydro

import (
	"context"
	"testing"
	"time"

	actionsv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestGetWorkflowRunCompletedEvent_AgentIDFromPath(t *testing.T) {
	const (
		copilotAppID = int64(100)
		claudeAppID  = int64(200)
	)

	copilot := agenticapp.NewCopilot(copilotAppID, "copilot-swe-agent", copilotAppID+1, "copilot-swe-agent-bot", "commit", "commit@email.com")
	claude := agenticapp.NewClaude(claudeAppID, "anthropic-code-agent", claudeAppID+1, "anthropic-code-agent-bot", "commit", "commit@email.com")
	provider := agenticapp.NewProvider(copilot, claude)

	makeMsg := func(t *testing.T, path, conclusion string) []byte {
		t.Helper()
		msg := &actionsv0.WorkflowRunExecution{
			WorkflowRunId:     1,
			RepositoryId:      10,
			RepositoryOwnerId: 20,
			ActorId:           30,
			WorkflowRunPath:   path,
			Conclusion:        conclusion,
			Status:            "completed",
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)
		return data
	}

	ctx := requestctx.NewContext(context.Background())

	t.Run("old copilot path sets agent ID and Kind=AgentCompletion", func(t *testing.T) {
		data := makeMsg(t, "dynamic/copilot-swe-agent/copilot", "success")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, copilotAppID, event.AgentID)
		require.Equal(t, events.WorkflowRunKindAgentCompletion, event.Kind)
	})

	t.Run("new 3P agents path sets agent ID and Kind=AgentCompletion", func(t *testing.T) {
		data := makeMsg(t, "dynamic/agents/anthropic-code-agent", "success")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, claudeAppID, event.AgentID)
		require.Equal(t, events.WorkflowRunKindAgentCompletion, event.Kind)
	})

	t.Run("legacy duplicated-slug path is not resolved as agent completion", func(t *testing.T) {
		// dynamic/{slug}/{slug} (e.g., CCR's legacy path) should no longer
		// resolve to an agent. Only dynamic/agents/{slug} and the hardcoded
		// dynamic/copilot-swe-agent/copilot path are accepted.
		data := makeMsg(t, "dynamic/anthropic-code-agent/anthropic-code-agent", "success")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, int64(0), event.AgentID)
		require.Equal(t, events.WorkflowRunEventKind(""), event.Kind)
	})

	t.Run("new 3P agents path with unknown agent sets zero agent ID", func(t *testing.T) {
		data := makeMsg(t, "dynamic/agents/unknown-agent", "success")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, int64(0), event.AgentID)
		require.Equal(t, events.WorkflowRunEventKind(""), event.Kind)
	})

	t.Run("non-agent dynamic path sets zero agent ID", func(t *testing.T) {
		data := makeMsg(t, "dynamic/dependabot/dependabot-updates", "success")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, int64(0), event.AgentID)
		require.Equal(t, events.WorkflowRunEventKind(""), event.Kind)
	})

	t.Run("non-agent failed workflow sets copilot agent ID and Kind=FailedTrigger", func(t *testing.T) {
		data := makeMsg(t, ".github/workflows/ci.yaml", "failure")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, copilotAppID, event.AgentID)
		require.Equal(t, events.WorkflowRunKindFailedTrigger, event.Kind)
	})

	t.Run("agent-triggered failed workflow is not applicable", func(t *testing.T) {
		// Use copilot's bot ID as the actor to simulate an agent-triggered workflow
		msg := &actionsv0.WorkflowRunExecution{
			WorkflowRunId:     1,
			RepositoryId:      10,
			RepositoryOwnerId: 20,
			ActorId:           copilotAppID + 1, // copilot bot ID
			WorkflowRunPath:   ".github/workflows/ci.yaml",
			Conclusion:        "failure",
			Status:            "completed",
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)
		_, _, err = getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.ErrorIs(t, err, ErrMessageNotApplicable)
	})

	t.Run("non-agent successful workflow sets zero agent ID", func(t *testing.T) {
		data := makeMsg(t, ".github/workflows/ci.yaml", "success")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, int64(0), event.AgentID)
		require.Equal(t, events.WorkflowRunEventKind(""), event.Kind)
	})

	t.Run("non-agent cancelled workflow sets zero agent ID", func(t *testing.T) {
		data := makeMsg(t, ".github/workflows/ci.yaml", "cancelled")
		_, event, err := getWorkflowRunCompletedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, int64(0), event.AgentID)
		require.Equal(t, events.WorkflowRunEventKind(""), event.Kind)
	})
}

func TestGetIssueCreatedEvent_AgentActorSkipped(t *testing.T) {
	const (
		copilotAppID = int64(100)
		claudeAppID  = int64(200)
	)

	copilot := agenticapp.NewCopilot(copilotAppID, "copilot-swe-agent", copilotAppID+1, "copilot-swe-agent-bot", "commit", "commit@email.com")
	claude := agenticapp.NewClaude(claudeAppID, "anthropic-code-agent", claudeAppID+1, "anthropic-code-agent-bot", "commit", "commit@email.com")
	provider := agenticapp.NewProvider(copilot, claude)

	makeMsg := func(t *testing.T, actorLogin string) []byte {
		t.Helper()
		msg := &githubv1.IssueCreateTemplate{
			Actor: &entities.User{
				Id:    1,
				Login: actorLogin,
			},
			Repository: &entities.Repository{
				Id:      10,
				OwnerId: wrapperspb.UInt32(20),
			},
			RepositoryOwner: &entities.User{
				Id:    20,
				Login: "test-owner",
			},
			Issue: &entities.Issue{
				Id:         1,
				IdValue:    1,
				Number:     1,
				IssueState: entities.Issue_OPEN,
			},
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)
		return data
	}

	ctx := requestctx.NewContext(context.Background())

	t.Run("human actor creates issue event", func(t *testing.T) {
		data := makeMsg(t, "human-user")
		_, event, err := getIssueCreatedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.Equal(t, copilotAppID, event.AgentID)
		require.Equal(t, int64(1), event.Issue.ID)
	})

	t.Run("copilot actor is not applicable", func(t *testing.T) {
		data := makeMsg(t, "copilot-swe-agent[bot]")
		_, _, err := getIssueCreatedEvent(ctx, data, time.Now(), provider)
		require.ErrorIs(t, err, ErrMessageNotApplicable)
	})

	t.Run("claude actor is not applicable", func(t *testing.T) {
		data := makeMsg(t, "anthropic-code-agent[bot]")
		_, _, err := getIssueCreatedEvent(ctx, data, time.Now(), provider)
		require.ErrorIs(t, err, ErrMessageNotApplicable)
	})

	t.Run("integration user-to-server auth is not applicable", func(t *testing.T) {
		// CCA's MintUserToServerTokenForRepo issues this auth class. The
		// webhook sender shows the user, not the bot, so the actor check
		// above misses it — we rely on RequestContext.Auth to catch it.
		msg := &githubv1.IssueCreateTemplate{
			Actor:           &entities.User{Id: 1, Login: "human-user"},
			Repository:      &entities.Repository{Id: 10, OwnerId: wrapperspb.UInt32(20)},
			RepositoryOwner: &entities.User{Id: 20, Login: "test-owner"},
			Issue:           &entities.Issue{Id: 1, IdValue: 1, Number: 1, IssueState: entities.Issue_OPEN},
			RequestContext:  &entities.RequestContext{Auth: entities.AuthTypes_INTEGRATION_USER_TO_SERVER},
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)

		_, _, err = getIssueCreatedEvent(ctx, data, time.Now(), provider)
		require.ErrorIs(t, err, ErrMessageNotApplicable)
	})

	t.Run("integration server-to-server auth is not applicable", func(t *testing.T) {
		msg := &githubv1.IssueCreateTemplate{
			Actor:           &entities.User{Id: 1, Login: "human-user"},
			Repository:      &entities.Repository{Id: 10, OwnerId: wrapperspb.UInt32(20)},
			RepositoryOwner: &entities.User{Id: 20, Login: "test-owner"},
			Issue:           &entities.Issue{Id: 1, IdValue: 1, Number: 1, IssueState: entities.Issue_OPEN},
			RequestContext:  &entities.RequestContext{Auth: entities.AuthTypes_INTEGRATION_SERVER_TO_SERVER},
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)

		_, _, err = getIssueCreatedEvent(ctx, data, time.Now(), provider)
		require.ErrorIs(t, err, ErrMessageNotApplicable)
	})

	t.Run("oauth auth still flows through", func(t *testing.T) {
		// Web UI / OAuth flows must keep working — only GitHub-App auth is skipped.
		msg := &githubv1.IssueCreateTemplate{
			Actor:           &entities.User{Id: 1, Login: "human-user"},
			Repository:      &entities.Repository{Id: 10, OwnerId: wrapperspb.UInt32(20)},
			RepositoryOwner: &entities.User{Id: 20, Login: "test-owner"},
			Issue:           &entities.Issue{Id: 1, IdValue: 1, Number: 1, IssueState: entities.Issue_OPEN},
			RequestContext:  &entities.RequestContext{Auth: entities.AuthTypes_OAUTH},
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)

		_, event, err := getIssueCreatedEvent(ctx, data, time.Now(), provider)
		require.NoError(t, err)
		require.NotNil(t, event)
		require.Equal(t, int64(1), event.Issue.ID)
	})
}

func TestGetIssueCreatedEvent_LargeIssueID(t *testing.T) {
	const copilotAppID = int64(100)

	copilot := agenticapp.NewCopilot(copilotAppID, "copilot-swe-agent", copilotAppID+1, "copilot-swe-agent-bot", "commit", "commit@email.com")
	provider := agenticapp.NewProvider(copilot)

	// Issue ID larger than UINT32_MAX (4294967295). The Hydro Issue entity's
	// Id field is uint32 and wraps to 0 for these IDs, so we must rely on
	// the int64 IdValue field instead.
	const largeIssueID = int64(4294967296) // UINT32_MAX + 1

	msg := &githubv1.IssueCreateTemplate{
		Actor: &entities.User{
			Id:    1,
			Login: "human-user",
		},
		Repository: &entities.Repository{
			Id:      10,
			OwnerId: wrapperspb.UInt32(20),
		},
		RepositoryOwner: &entities.User{
			Id:    20,
			Login: "test-owner",
		},
		Issue: &entities.Issue{
			Id:         0, // overflows to 0 for IDs > UINT32_MAX
			IdValue:    largeIssueID,
			Number:     42,
			IssueState: entities.Issue_OPEN,
		},
	}
	data, err := proto.Marshal(msg)
	require.NoError(t, err)

	ctx := requestctx.NewContext(context.Background())
	_, event, err := getIssueCreatedEvent(ctx, data, time.Now(), provider)
	require.NoError(t, err)
	require.Equal(t, largeIssueID, event.Issue.ID)
}

func TestGetID(t *testing.T) {
	t.Run("prefers IdValue when set", func(t *testing.T) {
		issue := &entities.Issue{Id: 41, IdValue: 42}
		require.Equal(t, int64(42), getID(issue))
	})

	t.Run("falls back to Id when IdValue is zero", func(t *testing.T) {
		issue := &entities.Issue{Id: 42, IdValue: 0}
		require.Equal(t, int64(42), getID(issue))
	})

	t.Run("returns IdValue for IDs larger than UINT32_MAX", func(t *testing.T) {
		// When issue IDs exceed UINT32_MAX, the uint32 Id field overflows
		// to 0 and IdValue carries the correct int64 value.
		issue := &entities.Issue{Id: 0, IdValue: 4294967296}
		require.Equal(t, int64(4294967296), getID(issue))
	})
}

func TestGetPullRequestReviewSubmitEvent_GitHubAppID(t *testing.T) {
	const copilotAppID = int64(100)

	copilot := agenticapp.NewCopilot(copilotAppID, "copilot-swe-agent", copilotAppID+1, "copilot-swe-agent-bot", "commit", "commit@email.com")
	provider := agenticapp.NewProvider(copilot)

	makeMsg := func(t *testing.T, githubAppID *wrapperspb.Int64Value) []byte {
		t.Helper()
		msg := &githubv1.PullRequestReviewSubmit{
			Actor:           &entities.User{Id: 1, Login: "human-user"},
			Repository:      &entities.Repository{Id: 10, OwnerId: wrapperspb.UInt32(20)},
			RepositoryOwner: &entities.User{Id: 20, Login: "test-owner"},
			Issue:           &entities.Issue{Id: 1, IdValue: 1, Number: 1, IssueState: entities.Issue_OPEN},
			PullRequest:     &entities.PullRequest{Id: 7, AuthorId: 1, PullRequestState: entities.PullRequest_OPEN},
			PullRequestReview: &entities.PullRequestReview{
				Id:   42,
				Body: "@copilot please take a look",
			},
			EventUrl:    "https://github.com/owner/repo/pull/1#pullrequestreview-42",
			GithubAppId: githubAppID,
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)
		return data
	}

	ctx := requestctx.NewContext(context.Background())

	t.Run("nil GithubAppId yields nil GitHubAppID", func(t *testing.T) {
		_, event, err := getPullRequestReviewSubmitEvent(ctx, makeMsg(t, nil), time.Now(), provider)
		require.NoError(t, err)
		require.Nil(t, event.GitHubAppID)
	})

	t.Run("populated GithubAppId is extracted", func(t *testing.T) {
		_, event, err := getPullRequestReviewSubmitEvent(ctx, makeMsg(t, wrapperspb.Int64(98765)), time.Now(), provider)
		require.NoError(t, err)
		require.NotNil(t, event.GitHubAppID)
		require.Equal(t, int64(98765), *event.GitHubAppID)
	})
}

func TestGetPullRequestCommentCreatedEvent_GitHubAppID(t *testing.T) {
	const copilotAppID = int64(100)

	copilot := agenticapp.NewCopilot(copilotAppID, "copilot-swe-agent", copilotAppID+1, "copilot-swe-agent-bot", "commit", "commit@email.com")
	provider := agenticapp.NewProvider(copilot)

	makeMsg := func(t *testing.T, githubAppID *wrapperspb.Int64Value) []byte {
		t.Helper()
		msg := &githubv1.PullRequestTimelineCommentCreate{
			Actor:           &entities.User{Id: 1, Login: "human-user"},
			Repository:      &entities.Repository{Id: 10, OwnerId: wrapperspb.UInt32(20)},
			RepositoryOwner: &entities.User{Id: 20, Login: "test-owner"},
			Issue:           &entities.Issue{Id: 1, IdValue: 1, Number: 1, IssueState: entities.Issue_OPEN},
			IssueComment:    &entities.IssueComment{Id: 99, IdValue: 99},
			Body:            "@copilot please take a look",
			EventUrl:        "https://github.com/owner/repo/pull/1#issuecomment-99",
			GithubAppId:     githubAppID,
		}
		data, err := proto.Marshal(msg)
		require.NoError(t, err)
		return data
	}

	ctx := requestctx.NewContext(context.Background())

	t.Run("nil GithubAppId yields nil GitHubAppID", func(t *testing.T) {
		_, event, err := getPullRequestCommentCreatedEvent(ctx, makeMsg(t, nil), time.Now(), provider)
		require.NoError(t, err)
		require.Nil(t, event.GitHubAppID)
	})

	t.Run("populated GithubAppId is extracted", func(t *testing.T) {
		_, event, err := getPullRequestCommentCreatedEvent(ctx, makeMsg(t, wrapperspb.Int64(54321)), time.Now(), provider)
		require.NoError(t, err)
		require.NotNil(t, event.GitHubAppID)
		require.Equal(t, int64(54321), *event.GitHubAppID)
	})
}
