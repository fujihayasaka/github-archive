package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.RepositoryArchivedStatusChanged")

func (p *Processor) repositoryArchivedStatusChanged(ctx context.Context, repositoryArchivedStatusChanged *githubv1.RepositoryArchivedStatusChanged) error {
	return errors.Wrap(p.syncRepository(ctx, repositoryArchivedStatusChanged.RepositoryId), "failed to process RepositoryArchivedStatusChanged")
}
