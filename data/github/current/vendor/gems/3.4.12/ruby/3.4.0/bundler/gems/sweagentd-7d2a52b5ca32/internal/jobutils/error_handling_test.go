package jobutils

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

func TestNewUnhandledErrorWithIssueComment(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{}
	cf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}

	t.Run("handle error with issue only", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		uhErr := NewUnhandledErrorWithIssueComment(
			ctx,
			errors.New("test error"),
			&jobs.Assignment{
				PullRequestID:     0,
				PullRequestNumber: 0,
				RepoID:            0,
			},
			false,
			"actor",
			1,
		)
		err := HandleErrorByType(ctx, obsv, cf, uhErr)
		require.Error(t, err)
		pass := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				require.Equal(t, call.Args[0], int64(0))
				require.Equal(t, call.Args[1], 1)
				require.Contains(t, call.Args[2], "@actor Unfortunately I hit an unexpected error while trying to work on issue #1")
				require.True(t, joberrors.IsCopilotErrorComment(call.Args[2].(string)))
				pass = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass)
	})

	t.Run("handle rules that are blocking copilot", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		uhErr := NewUnhandledRulesErrorWithIssueComment(
			ctx,
			errors.New("test error"),
			&jobs.Assignment{
				PullRequestID:     0,
				PullRequestNumber: 0,
				RepoID:            0,
			},
			"actor",
			1,
			&jobservice.CheckRulesResult{
				Rules:                    []string{"branch rule 1", "branch rule 2"},
				HasBranchProtectionRules: true,
				HasRepositoryRules:       false,
			},
		)
		body, err := uhErr.GenerateComment()
		require.NoError(t, err)
		require.Contains(t, body, "@actor I hit the following errors while trying to work on issue #1")
		require.Contains(t, body, "branch rule 1")
		require.Contains(t, body, "branch rule 2")
		require.Contains(t, body, "> [!NOTE]")
		require.Contains(t, body, "To learn about managing branch protection rules")
		require.NotContains(t, body, "To learn about managing repository rules")
		require.True(t, joberrors.IsCopilotErrorComment(body))
	})

	t.Run("handle error with issue and PR", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		uhErr := NewUnhandledErrorWithIssueComment(
			ctx,
			errors.New("test error"),
			&jobs.Assignment{
				PullRequestID:     2,
				PullRequestNumber: 2,
				RepoID:            0,
			},
			false,
			"actor",
			1,
		)
		err := HandleErrorByType(ctx, obsv, cf, uhErr)
		require.Error(t, err)
		pass := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				require.Equal(t, call.Args[0], int64(0))
				require.Equal(t, call.Args[1], 2)
				require.Contains(t, call.Args[2], "@actor Unfortunately I hit an unexpected error while trying to work on issue #1")
				require.True(t, joberrors.IsCopilotErrorComment(call.Args[2].(string)))
				pass = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass)
	})

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
			false,
			"actor",
		)
		err := HandleErrorByType(ctx, obsv, cf, uhErr)
		require.Error(t, err)
		pass1 := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				require.Equal(t, call.Args[0], int64(0))
				require.Equal(t, call.Args[1], 2)
				require.Contains(t, call.Args[2], "@actor Unfortunately I hit an unexpected error while processing your comment.")
				require.True(t, joberrors.IsCopilotErrorComment(call.Args[2].(string)))
				pass1 = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass1)
	})

	t.Run("close PR with issue", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		uhErr := NewUnhandledErrorWithIssueComment(
			ctx,
			errors.New("test error"),
			&jobs.Assignment{
				PullRequestID:     2,
				PullRequestNumber: 2,
				RepoID:            0,
			},
			true,
			"actor",
			1,
		)
		err := HandleErrorByType(ctx, obsv, cf, uhErr)
		require.Error(t, err)
		pass1 := false
		pass2 := false
		pass3 := false
		for _, call := range gh.MethodCalls {
			switch call.Method {
			case "CreateComment":
				require.Equal(t, call.Args[0], int64(0))
				require.Equal(t, call.Args[1], 2)
				require.Contains(t, call.Args[2], "@actor Unfortunately I hit an unexpected error while trying to work on issue #1")
				require.True(t, joberrors.IsCopilotErrorComment(call.Args[2].(string)))
				pass1 = true
			case "UpdatePullRequest":
				require.Equal(t, call.Args[0], int64(0))
				pr := call.Args[1].(*gg.PullRequest)
				require.Equal(t, pr.GetNumber(), 2)
				require.Equal(t, pr.GetState(), "closed")
				pass2 = true
			case "GetPullRequest":
				require.Equal(t, call.Args[0], int64(0))
				require.Equal(t, call.Args[1], 2)
				pass3 = true
			default:
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass1)
		require.True(t, pass2)
		require.True(t, pass3)
	})

	t.Run("close PR with issue", func(t *testing.T) {
		gh.MethodCalls = []github.MethodCall{}
		uhErr := NewUnhandledErrorWithPRComment(
			ctx,
			errors.New("test error"),
			&jobs.Assignment{
				PullRequestID:     2,
				PullRequestNumber: 2,
				RepoID:            0,
			},
			true,
			"actor",
		)
		err := HandleErrorByType(ctx, obsv, cf, uhErr)
		require.Error(t, err)
		pass1 := false
		pass2 := false
		pass3 := false
		for _, call := range gh.MethodCalls {
			switch call.Method {
			case "CreateComment":
				require.Equal(t, call.Args[0], int64(0))
				require.Equal(t, call.Args[1], 2)
				require.Contains(t, call.Args[2], "@actor Unfortunately I hit an unexpected error while trying to work on your request. ")
				require.True(t, joberrors.IsCopilotErrorComment(call.Args[2].(string)))
				pass1 = true
			case "UpdatePullRequest":
				require.Equal(t, call.Args[0], int64(0))
				pr := call.Args[1].(*gg.PullRequest)
				require.Equal(t, pr.GetNumber(), 2)
				require.Equal(t, pr.GetState(), "closed")
				pass2 = true
			case "GetPullRequest":
				require.Equal(t, call.Args[0], int64(0))
				require.Equal(t, call.Args[1], 2)
				pass3 = true
			default:
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass1)
		require.True(t, pass2)
		require.True(t, pass3)
	})
}
