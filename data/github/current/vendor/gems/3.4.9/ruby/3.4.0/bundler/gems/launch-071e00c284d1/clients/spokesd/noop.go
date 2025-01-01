package spokesd

import (
	"context"
	"errors"

	"github.com/github/spokes-proto/gen/go/v1/blobs"
	commits "github.com/github/spokes-proto/gen/go/v1/commits"
	objects "github.com/github/spokes-proto/gen/go/v1/objects"
)

type noopClient struct{}

// NewNoopClient returns a noop Spokes client
// This should only be used for new environments where the Spokes service is not yet available.
// This client will return an error for all requests, so it should not be used
// in customer-facing environments.
func NewNoopClient() Client {
	return &noopClient{}
}

func (n *noopClient) GetBlobContents(_ context.Context, _ *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
	return nil, errors.New("noop spokes client")
}

func (n *noopClient) GetBlobContentsBatch(_ context.Context, _ *GetBlobContentsBatchRequest) (*GetBlobContentsBatchResponse, error) {
	return nil, errors.New("noop spokes client")
}

func (n *noopClient) ResolveObject(_ context.Context, _ *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	return nil, errors.New("noop spokes client")
}

func (n *noopClient) CheckCommitReachability(_ context.Context, _ *commits.CheckCommitReachabilityRequest) (*commits.CheckCommitReachabilityResponse, error) {
	return nil, errors.New("noop spokes client")
}

func (n *noopClient) ResolveObjectsByCommitShaAndPath(_ context.Context, _ *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return nil, errors.New("noop spokes client")
}

func (n *noopClient) ResolveObjectsByRef(_ context.Context, _ *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return nil, errors.New("noop spokes client")
}
