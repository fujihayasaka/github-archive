package jobutils

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
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
}
