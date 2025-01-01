package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.RepositoryRestored")

func (p *Processor) repositoryRestored(ctx context.Context, repositoryRestored *githubv1.RepositoryRestored) error {
	return errors.Wrap(p.syncRepositoryEntity(ctx, repositoryRestored.RestoredRepository), "failed to process RepositoryRestored")
}
