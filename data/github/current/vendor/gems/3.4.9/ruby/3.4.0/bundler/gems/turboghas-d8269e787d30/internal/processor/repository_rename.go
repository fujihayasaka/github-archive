package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.RepositoryRename")

func (p *Processor) repositoryRename(ctx context.Context, repositoryRename *githubv1.RepositoryRename) error {
	return errors.Wrap(p.syncRepositoryEntity(ctx, repositoryRename.Repository), "failed to process RepositoryRename")
}
