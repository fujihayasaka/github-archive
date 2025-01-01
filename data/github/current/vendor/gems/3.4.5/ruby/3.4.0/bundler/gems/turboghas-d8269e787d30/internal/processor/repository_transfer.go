package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.RepositoryTransfer")

func (p *Processor) repositoryTransfer(ctx context.Context, repositoryTransfer *githubv1.RepositoryTransfer) error {
	return errors.Wrap(p.syncRepositoryEntity(ctx, repositoryTransfer.Repository), "failed to process RepositoryTransfer")
}
