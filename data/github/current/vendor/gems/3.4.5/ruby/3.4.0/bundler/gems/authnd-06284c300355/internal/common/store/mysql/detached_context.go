package mysql

import (
	"context"
	"database/sql"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/go-ctxutil"
	"github.com/jmoiron/sqlx"
)

// NewDetachedContextExecutor executor implementation intercepts context cancellation to prevent signals
// from being sent to MySQL/HAProxy, but still allows the caller to returns early in the control flow.
//
// NOTE(chriskirkland): the working theory here is that context cancellation is being propagated to the MySQL HAProxy
// backend and is causing the connection to be closed prematurely.  This executor allows us to continue using context
// cancellation as a standard mechanism for controlling the flow of the application, but prevents the signals from
// from affecting the HAProxy connection state.
//
// It's already well-known that context cancellation doesn't cause query execution to halt on the MySQL server-side,
// so this should only affect HAProxy.
// ref: https://medium.com/@rocketlaunchr.cloud/canceling-mysql-in-go-827ed8f83b30

func NewDetachedContextExecutor(ex Executor) Executor {
	return &detachedContextExecutor{
		ex: ex,
	}
}

type detachedContextExecutor struct {
	ex Executor
}

func (e *detachedContextExecutor) ConnectionName() string {
	return e.ex.ConnectionName()
}

func (e *detachedContextExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withDetachedContext(ctx, func(detachedCtx context.Context) error {
		return e.ex.GetContext(detachedCtx, dest, query, args...)
	})
}

func (e *detachedContextExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return withDetachedContext(ctx, func(detachedCtx context.Context) error {
		return e.ex.SelectContext(detachedCtx, dest, query, args...)
	})
}

func (e *detachedContextExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	var row Row
	err := withDetachedContext(ctx, func(detachedCtx context.Context) error {
		row := e.ex.QueryRowxContext(detachedCtx, query, args...)
		return row.Err()
	})

	if common.NewErrorIsOneOf(context.DeadlineExceeded, context.Canceled)(err) {
		return &errorRow{err: err}
	}
	return row
}

func (e *detachedContextExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	var result sql.Result
	err := withDetachedContext(ctx, func(detachedCtx context.Context) error {
		var innerErr error
		result, innerErr = e.ex.ExecContext(ctx, query, args...)
		return innerErr
	})

	if common.NewErrorIsOneOf(context.DeadlineExceeded, context.Canceled)(err) {
		return nil, err
	}
	return result, err
}

func (e *detachedContextExecutor) unwrap() (*sqlx.DB, error) {
	return e.ex.unwrap()
}

func withDetachedContext(ctx context.Context, op func(ctx context.Context) error) error {
	diagnostics.Logger(ctx).Debug("detaching context for mysql request")
	diagnostics.Statter(ctx).Counter("db.store.detached_context", nil, 1)

	result := make(chan error, 1)
	go func() {
		detachedCtx := ctxutil.DetachedCancel(ctx)
		result <- op(detachedCtx)
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-result:
		return err
	}
}
