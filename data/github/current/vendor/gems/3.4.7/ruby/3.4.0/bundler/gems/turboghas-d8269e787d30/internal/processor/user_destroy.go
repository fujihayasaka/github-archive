package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.UserDestroy")

func (p *Processor) userDestroy(ctx context.Context, userDestroy *githubv1.UserDestroy) error {
	return errors.Wrap(p.syncAccountEntity(ctx, userDestroy.User), "failed to process UserDestroy")
}
