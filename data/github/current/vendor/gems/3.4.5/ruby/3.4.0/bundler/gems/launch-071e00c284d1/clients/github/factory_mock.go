package github

import (
	"context"

	errs "github.com/pkg/errors"

	"github.com/github/launch/types"
)

// MockClientFactory is a ClientFactory that returns pre-built clients
type MockClientFactory struct {
	ByRepositoryOwnerDatabaseID map[int64]Client
	ByRepositoryOwnerID         map[types.GlobalID]Client
	ByRepositoryID              map[types.GlobalID]Client
}

// NewMockClientFactory instantiates a new MockClientFactory
func NewMockClientFactory() *MockClientFactory {
	return &MockClientFactory{
		ByRepositoryOwnerDatabaseID: map[int64]Client{},
		ByRepositoryOwnerID:         map[types.GlobalID]Client{},
		ByRepositoryID:              map[types.GlobalID]Client{},
	}
}

var _ Factory = (*MockClientFactory)(nil)

func (f *MockClientFactory) NewClientForRepositoryOwnerDatabaseID(_ context.Context, _ types.GlobalID, ownerID int64) (Client, error) {
	if client, ok := f.ByRepositoryOwnerDatabaseID[ownerID]; ok {
		return client, nil
	}
	return nil, errs.Errorf("No mock provided for repository owner client; ownerID: %q", ownerID)
}

func (f *MockClientFactory) NewClientForRepositoryOwner(_ context.Context, repoID, ownerID types.GlobalID) (Client, error) {
	if client, ok := f.ByRepositoryOwnerID[ownerID]; ok {
		return client, nil
	}

	// fallback to repoID in this case; this is how it works in factory.go
	if client, ok := f.ByRepositoryID[repoID]; ok {
		return client, nil
	}

	return nil, errs.Errorf("No mock provided for repository owner client; ownerID: %q", ownerID.String())
}

func (f *MockClientFactory) NewClientForRepository(_ context.Context, repoID, _ types.GlobalID, _ *ClientTokenOptions) (Client, error) {
	if client, ok := f.ByRepositoryID[repoID]; ok {
		return client, nil
	}
	return nil, errs.Errorf("No mock provided for repository client; repoID: %q", repoID.String())
}
