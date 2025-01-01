package azp

import (
	"context"

	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type RepositoryClientFactory interface {
	// ClientFromResources returns a RepositoryClient
	ClientFromResources(ctx context.Context, resources *azptypes.BackingResources) RepositoryClient
	// ClientFromRepoGID will return a client where we have Azure responses stored in the DB
	ClientFromRepoGID(ctx context.Context, repoID types.GlobalID) (RepositoryClient, error)
	// GetPipelineServiceURL returns the URL for the pipeline service of the given backing resources
	GetPipelineServiceURL(ctx context.Context, resources *azptypes.BackingResources) string
}
