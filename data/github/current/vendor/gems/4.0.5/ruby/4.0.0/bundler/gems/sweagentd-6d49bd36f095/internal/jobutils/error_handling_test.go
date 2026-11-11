package jobutils

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestNewUnhandledErrorWithPRComment(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{}
	cf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}

	t.Run("handle error with PR only", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		uhErr := NewUnhandledErrorWithPRComment(
			ctx,
			errors.New("test error"),
			&jobs.Assignment{
				PullRequestID:     2,
				PullRequestNumber: 2,
				RepoID:            0,
			},
			"actor",
		)
		err := HandleErrorByType(ctx, obsv, cf, agenticapptest.NewTestCopilot(t), uhErr)
		require.Error(t, err)
		pass1 := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				require.Equal(t, int64(0), call.Args[0])
				require.Equal(t, 2, call.Args[1])
				require.Contains(t, call.Args[2], "@actor Unfortunately I hit an unexpected error while processing your comment.")
				require.True(t, joberrors.IsCopilotErrorComment(call.Args[2].(string)))
				pass1 = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass1)
	})

	t.Run("handle error with nil assignment does not panic", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		uhErr := NewUnhandledErrorWithPRComment(
			ctx,
			errors.New("test error"),
			nil,
			"actor",
		)
		err := HandleErrorByType(ctx, obsv, cf, agenticapptest.NewTestCopilot(t), uhErr)
		require.Error(t, err)
		// No comment should be created since we don't know which repo/PR to post to
		for _, call := range gh.MethodCalls {
			require.NotEqual(t, "CreateComment", call.Method, "should not attempt to create comment with nil assignment")
		}
	})

	t.Run("handle model not available error", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		modelErr := NewModelNotAvailableErrorWithPRComment(
			ctx,
			errors.New("model not found"),
			&jobs.Assignment{
				PullRequestID:     3,
				PullRequestNumber: 3,
				RepoID:            0,
			},
			"actor",
			"claude-opus-4.5",
		)
		err := HandleErrorByType(ctx, obsv, cf, agenticapptest.NewTestCopilot(t), modelErr)
		require.Error(t, err)
		pass := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				body := call.Args[2].(string)
				require.Contains(t, body, "@actor")
				require.Contains(t, body, "`claude-opus-4.5`")
				require.Contains(t, body, "not available for your account")
				require.True(t, joberrors.IsCopilotErrorComment(body))
				pass = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass)
	})

	t.Run("handle default branch error", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		defaultBranchErr := NewDefaultBranchErrorWithPRComment(
			ctx,
			errors.New("head branch \"main\" is the default branch"),
			&jobs.Assignment{
				PullRequestID:     5,
				PullRequestNumber: 5,
				RepoID:            0,
			},
			"actor",
		)
		err := HandleErrorByType(ctx, obsv, cf, agenticapptest.NewTestCopilot(t), defaultBranchErr)
		require.NoError(t, err, "default branch error should return nil after posting comment")
		pass := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				body := call.Args[2].(string)
				require.Contains(t, body, "@actor")
				require.Contains(t, body, "default branch")
				require.Contains(t, body, "not allowed to push to directly")
				require.True(t, joberrors.IsCopilotErrorComment(body))
				pass = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass)
	})

	t.Run("handle rules violation error", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		rulesResult := &jobservice.CheckRulesResult{
			Rules:                    []string{"Branch creation is blocked due to repository rules", "Changes must be made through a pull request due to branch protection rules"},
			HasBranchProtectionRules: true,
			HasRepositoryRules:       true,
		}
		rulesErr := NewRulesViolationErrorWithPRComment(
			ctx,
			errors.New("rules violation"),
			&jobs.Assignment{
				PullRequestID:     4,
				PullRequestNumber: 4,
				RepoID:            0,
			},
			"actor",
			rulesResult,
		)
		err := HandleErrorByType(ctx, obsv, cf, agenticapptest.NewTestCopilot(t), rulesErr)
		require.NoError(t, err, "non-retryable rules violation should return nil after posting comment")
		pass := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				body := call.Args[2].(string)
				require.Contains(t, body, "@actor")
				require.Contains(t, body, "repository rules")
				require.Contains(t, body, "Branch creation is blocked")
				require.Contains(t, body, "the documentation")
				require.True(t, joberrors.IsCopilotErrorComment(body))
				pass = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass)
	})
}
