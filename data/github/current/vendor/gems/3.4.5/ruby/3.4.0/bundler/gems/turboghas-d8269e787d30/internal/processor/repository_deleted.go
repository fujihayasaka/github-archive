package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.RepositoryDeleted")

func (p *Processor) repositoryDeleted(ctx context.Context, repositoryDeleted *githubv1.RepositoryDeleted) error {
	return errors.Wrap(p.syncRepositoryEntity(ctx, repositoryDeleted.DeletedRepository), "failed to process RepositoryDeleted")
}
