package subscriptions

import (
	"context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/jmoiron/sqlx"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/errors"
	querierpkg "github.com/github/notifyd/internal/pkg/mysql/querier"
)

type matchRulesRepo struct {
	querierpkg.Querier
	queries matchRulesQueries
}

func newMatchRulesRepo(clock clockpkg.Clock, telem *telemetry.Provider) matchRulesRepo {
	querier := querierpkg.NewRetrier(querierpkg.New(), clock, telem)

	return matchRulesRepo{
		Querier: querier,
		queries: matchRulesQueries{},
	}
}

func (r matchRulesRepo) remove(ctx context.Context, store sqlx.ExecerContext, subscriptionIDs []int64) error {
	return r.Delete(ctx, store, r.queries.deleteBySubscriptionIDs(subscriptionIDs))
}

func (r matchRulesRepo) insert(ctx context.Context, store sqlx.ExecerContext, subscriptions []*Subscription) error {
	if len(subscriptions) == 0 {
		return nil
	}

	newMatchRules := []MatchRule{}
	for _, subscription := range subscriptions {
		newMatchRules = append(newMatchRules, subscription.MatchRules...)
	}

	if len(newMatchRules) == 0 {
		return nil
	}

	if _, err := r.Insert(ctx, store, r.queries.insert(newMatchRules)); err != nil {
		return errors.Wrap(err, "saving match rules")
	}

	return nil
}
