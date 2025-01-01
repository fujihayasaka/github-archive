package querier

import (
	"context"

	"github.com/Masterminds/squirrel"
	clockpkg "github.com/benbjohnson/clock"
	"github.com/jmoiron/sqlx"

	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/mysql"
)

// retrier wraps any querier on a default MySQL retrier. This allows to retry by default any query
// that fails for known reasons (namely invalid connections)
type retrier struct {
	clock   clockpkg.Clock
	querier Querier
	telem   *telemetry.Provider
}

// NewRetrier creates a new retrier.
func NewRetrier(base Querier, clock clockpkg.Clock, telem *telemetry.Provider) Querier {
	return retrier{
		querier: base,
		clock:   clock,
		telem:   telem,
	}
}

func (r retrier) Delete(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) error {
	_, err := mysql.WithRetries(ctx, r.clock, r.telem, mysql.ToCallback(func(c context.Context) error {
		return r.querier.Delete(c, store, query)
	}))

	return err
}

func (r retrier) Select(ctx context.Context, store sqlx.QueryerContext, dst interface{}, query squirrel.Sqlizer) error {
	_, err := mysql.WithRetries(ctx, r.clock, r.telem, mysql.ToCallback(func(c context.Context) error {
		return r.querier.Select(c, store, dst, query)
	}))

	return err
}

func (r retrier) Insert(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) (Result, error) {
	return mysql.WithRetries(ctx, r.clock, r.telem, func(c context.Context) (Result, error) {
		return r.querier.Insert(c, store, query)
	})
}

func (r retrier) AutoIncrementStep(ctx context.Context, store *sqlx.Tx) (int64, error) {
	return mysql.WithRetries(ctx, r.clock, r.telem, func(c context.Context) (int64, error) {
		return r.querier.AutoIncrementStep(ctx, store)
	})
}
