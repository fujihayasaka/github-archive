package githubtwirp

import (
	"context"

	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
)

type NoopAuthorizationAPI struct {
	coreTwirp.AuthorizationAPI
	MockBatchControlAccess func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error)
}

// Ensure NoopClient implements ClientInterface
var _ coreTwirp.AuthorizationAPI = &NoopAuthorizationAPI{}

func (n *NoopAuthorizationAPI) BatchControlAccess(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
	if n.MockBatchControlAccess != nil {
		return n.MockBatchControlAccess(ctx, req)
	}

	return &coreTwirp.BatchControlAccessResponse{
		Decisions: []*coreTwirp.AuthorizationDecision{
			{
				Id:       "noop-id",
				Decision: true,
			},
		},
	}, nil
}
