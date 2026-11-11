package agenticapp

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/githubtwirp"
	sweagentdpb "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func TestRevokeTokens(t *testing.T) {
	app := NewCopilot(42, "test-app", 100, "test-bot", "commit-login", "commit@email.com")

	t.Run("successfully revokes all tokens", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		var capturedReq *sweagentdpb.RevokeTokensRequest
		noopClient.NoopSweagentdAPI.MockRevokeTokens = func(ctx context.Context, req *sweagentdpb.RevokeTokensRequest) (*sweagentdpb.RevokeTokensResponse, error) {
			capturedReq = req
			return &sweagentdpb.RevokeTokensResponse{
				TotalRevoked: int32(len(req.Tokens)),
			}, nil
		}

		tokens := []string{"ghu_token1", "ghs_token2"}

		failedTokens, err := RevokeTokens(context.Background(), noopClient, app, tokens)
		require.NoError(t, err)
		require.Empty(t, failedTokens)
		require.Equal(t, int64(42), capturedReq.AgentId)
		require.Equal(t, tokens, capturedReq.Tokens)
	})

	t.Run("returns failed tokens from response", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.MockRevokeTokens = func(ctx context.Context, req *sweagentdpb.RevokeTokensRequest) (*sweagentdpb.RevokeTokensResponse, error) {
			return &sweagentdpb.RevokeTokensResponse{
				TotalRevoked: 1,
				FailedTokens: []string{"ghs_token2"},
			}, nil
		}

		tokens := []string{"ghu_token1", "ghs_token2"}

		failedTokens, err := RevokeTokens(context.Background(), noopClient, app, tokens)
		require.NoError(t, err)
		require.Equal(t, []string{"ghs_token2"}, failedTokens)
	})

	t.Run("returns all tokens on error", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.MockRevokeTokens = func(ctx context.Context, req *sweagentdpb.RevokeTokensRequest) (*sweagentdpb.RevokeTokensResponse, error) {
			return nil, context.DeadlineExceeded
		}

		tokens := []string{"ghu_token1", "ghs_token2"}

		failedTokens, err := RevokeTokens(context.Background(), noopClient, app, tokens)
		require.ErrorIs(t, err, context.DeadlineExceeded)
		require.Equal(t, tokens, failedTokens)
	})
}
