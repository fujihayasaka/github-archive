package subscriptions

import (
	"context"
	"strconv"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/jmoiron/sqlx"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/errors"
	querierpkg "github.com/github/notifyd/internal/pkg/mysql/querier"
	"github.com/github/notifyd/internal/pkg/pagination"
)

type metaSubscriptionsRepo struct {
	querierpkg.Querier
	queries metaSubscriptionQueries
	clock   clockpkg.Clock
}

func newMetaSubscriptionsRepo(clock clockpkg.Clock, telem *telemetry.Provider) metaSubscriptionsRepo {
	querier := querierpkg.NewRetrier(querierpkg.New(), clock, telem)

	return metaSubscriptionsRepo{
		Querier: querier,
		queries: newMetaSubscriptionQueries(telem),
		clock:   clock,
	}
}

func (r metaSubscriptionsRepo) get(ctx context.Context, store sqlx.QueryerContext, userID int64, fields []CustomField, page pagination.Page) ([]*MetaSubscription, pagination.Pages, error) {
	var subscriptions []*MetaSubscription

	if err := r.Select(ctx, store, &subscriptions, r.queries.find(userID, fields, page)); err != nil {
		return nil, pagination.NewEmptyStandardPages(), errors.Wrap(err, "fetching meta subscriptions")
	}

	if len(subscriptions) == int(page.Limit()) {
		lastID := strconv.FormatInt(subscriptions[len(subscriptions)-1].ID, 10)
		return subscriptions, pagination.NewStandardPages(pagination.EncodeV1Cursor(lastID)), nil
	}

	return subscriptions, pagination.NewEmptyStandardPages(), nil
}

func (r metaSubscriptionsRepo) pluck(ctx context.Context, store sqlx.QueryerContext, userID int64, fields []CustomField) ([]int64, error) {
	var ids []int64

	metaSubscriptions, _, err := r.get(ctx, store, userID, fields, pagination.NewNoLimitPage())
	if err != nil {
		return ids, err
	}

	for _, meta := range metaSubscriptions {
		ids = append(ids, meta.ID)
	}

	return ids, nil
}

func (r metaSubscriptionsRepo) insert(ctx context.Context, store sqlx.ExecerContext, metaSubscriptions []*MetaSubscription, autoIncrementStep int64) ([]*MetaSubscription, error) {
	if len(metaSubscriptions) == 0 {
		return metaSubscriptions, nil
	}

	for _, s := range metaSubscriptions {
		s.UpdateTimestamps(r.clock)
	}

	result, err := r.Insert(ctx, store, r.queries.insert(metaSubscriptions))
	if err != nil {
		return metaSubscriptions, errors.Wrap(err, "inserting meta subscriptions")
	}

	if err := result.EachID(func(idx int64, id int64) { metaSubscriptions[idx].setID(id) }, autoIncrementStep); err != nil {
		return metaSubscriptions, errors.Wrap(err, "inserting meta subscriptions")
	}

	return metaSubscriptions, nil
}

func (r metaSubscriptionsRepo) remove(ctx context.Context, store sqlx.ExecerContext, ids []int64) error {
	if err := r.Delete(ctx, store, r.queries.deleteByIDs(ids)); err != nil {
		return errors.Wrap(err, "delete subscriptions failed")
	}

	return nil
}
