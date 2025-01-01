package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.RepositoryVisibilityChanged")

func (p *Processor) repositoryVisibilityChanged(ctx context.Context, repositoryVisibilityChanged *githubv1.RepositoryVisibilityChanged) error {
	return errors.Wrap(p.syncRepository(ctx, repositoryVisibilityChanged.RepositoryId), "failed to process RepositoryVisibilityChanged")
}
