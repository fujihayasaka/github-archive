package agenticapp

import (
	"context"

	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdpb "github.com/github/sweagentd/proto/sweagentd/v1"
)

// RevokeTokens revokes tokens by calling the RevokeTokens RPC.
// This batches all tokens into a single RPC call.
func RevokeTokens(ctx context.Context, ghtwirp githubtwirp.ClientInterface, app sweagentd.AgenticApp, tokens []string) (failedTokens []string, err error) {
	resp, err := ghtwirp.SweagentdAPI().RevokeTokens(ctx, &sweagentdpb.RevokeTokensRequest{
		AgentId: app.AppID(),
		Tokens:  tokens,
	})
	if err != nil {
		return tokens, err
	}

	return resp.FailedTokens, nil
}
