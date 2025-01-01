package matchengine

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/jmoiron/sqlx"

	"github.com/github/notifyd/internal/pkg/errors"
	querierpkg "github.com/github/notifyd/internal/pkg/mysql/querier"
	"github.com/github/notifyd/internal/pkg/notify"
)

// MatchedEntriesRepo represents a repository for matched entries.
type MatchedEntriesRepo struct {
	querierpkg.Querier
	queries matchedEntriesQueries
}

// NewMatchedEntriesRepo creates a new MatchedEntriesRepo.
func NewMatchedEntriesRepo(clock clockpkg.Clock, telem *telemetry.Provider) MatchedEntriesRepo {
	querier := querierpkg.NewRetrier(querierpkg.New(), clock, telem)
	return MatchedEntriesRepo{
		Querier: querier,
		queries: matchedEntriesQueries{},
	}
}

// Get gets matched entries.
func (r MatchedEntriesRepo) Get(ctx context.Context, store sqlx.QueryerContext, fields notify.MessageMatchFields) ([]*MatchedEntry, error) {
	var entries []*MatchedEntry

	if err := r.Select(ctx, store, &entries, r.queries.findByFields(fields)); err != nil {
		return nil, errors.Wrap(err, "fetching matching subscriptions")
	}

	return entries, nil
}
