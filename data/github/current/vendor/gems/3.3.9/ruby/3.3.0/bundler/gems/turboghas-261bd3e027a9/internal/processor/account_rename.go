package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.AccountRename")

func (p *Processor) accountRename(ctx context.Context, accountRename *githubv1.AccountRename) error {
	return errors.Wrap(p.syncAccountEntity(ctx, accountRename.Account), "failed to process AccountRename")
}
