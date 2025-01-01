package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.RepositoryInvite")

func (p *Processor) repositoryInvite(ctx context.Context, repositoryInvite *githubv1.RepositoryInvite) error {
	if repositoryInvite.Repository.OwnerId == nil {
		return nil
	}

	return errors.Wrap(p.syncOrganization(ctx, uint64(repositoryInvite.Repository.OwnerId.Value)), "failed to process RepositoryInvite")
}
