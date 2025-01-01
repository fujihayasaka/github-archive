package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.v1.RepositoryBulkInvite")

func (p *Processor) repositoryBulkInvite(ctx context.Context, repositoryBulkInvite *githubv1.RepositoryBulkInvite) error {
	if repositoryBulkInvite.Repository.OwnerId == nil {
		return nil
	}

	return errors.Wrap(p.syncOrganization(ctx, uint64(repositoryBulkInvite.Repository.OwnerId.Value)), "failed to process RepositoryBulkInvite")
}
