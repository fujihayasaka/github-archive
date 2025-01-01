package subscriptions

import (
	context "context"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/jmoiron/sqlx"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/errors"
	querierpkg "github.com/github/notifyd/internal/pkg/mysql/querier"
)

type subscriptionsRepo struct {
	querierpkg.Querier
	clock   clockpkg.Clock
	queries subscriptionQueries
}

func newSubscriptionsRepo(clock clockpkg.Clock, telem *telemetry.Provider) subscriptionsRepo {
	querier := querierpkg.NewRetrier(querierpkg.New(), clock, telem)

	return subscriptionsRepo{
		clock:   clock,
		Querier: querier,
		queries: subscriptionQueries{},
	}
}

func (r subscriptionsRepo) remove(ctx context.Context, store sqlx.ExecerContext, ids []int64) error {
	if err := r.Delete(ctx, store, r.queries.deleteByIDs(ids)); err != nil {
		return errors.Wrap(err, "delete internal subscriptions failed")
	}

	return nil
}

func (r subscriptionsRepo) pluck(ctx context.Context, store sqlx.QueryerContext, metaIDs []int64) ([]int64, error) {
	var ids []int64
	if err := r.Select(ctx, store, &ids, r.queries.findIDsByMetaIDs(metaIDs)); err != nil {
		return ids, errors.Wrap(err, "error fetching internal subscription ids to delete")
	}

	return ids, nil
}

func (r subscriptionsRepo) insert(ctx context.Context, store sqlx.ExecerContext, metaSubscriptions []*MetaSubscription, autoIncrementStep int64) ([]*Subscription, error) {
	if len(metaSubscriptions) == 0 {
		return []*Subscription{}, nil
	}

	var newSubscriptions []*Subscription
	for _, meta := range metaSubscriptions {
		subscriptions, err := meta.toSubscriptions(r.clock)
		if err != nil {
			//nolint:nilerr // TODO(franciscoj): [On 04/10/2024] review why we ignore this error
			return []*Subscription{}, nil
		}
		newSubscriptions = append(newSubscriptions, subscriptions...)
	}

	res, err := r.Insert(ctx, store, r.queries.insert(newSubscriptions))
	if err != nil {
		return []*Subscription{}, errors.Wrap(err, "inserting subscriptions")
	}

	if err := res.EachID(func(idx, id int64) { newSubscriptions[idx].SetID(id) }, autoIncrementStep); err != nil {
		return []*Subscription{}, errors.Wrap(err, "inserting subscriptions")
	}

	return newSubscriptions, nil
}
