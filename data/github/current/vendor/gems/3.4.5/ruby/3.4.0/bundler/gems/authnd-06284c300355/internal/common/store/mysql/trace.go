package mysql

import (
	"context"
	"database/sql"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/jmoiron/sqlx"
	"go.opentelemetry.io/otel/attribute"
)

// NewTracingExecutor executor implementation which contains spans for tracing.
func NewTracingExecutor(ex Executor) Executor {
	return &tracingExecutor{
		ex: ex,
	}
}

type tracingExecutor struct {
	ex Executor
}

func (e *tracingExecutor) ConnectionName() string {
	return e.ex.ConnectionName()
}

func (e *tracingExecutor) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	ctx, span := tracing.ChildSpan(ctx, "mysql.get")
	span.SetAttributes(attribute.String("query", query))
	defer span.End()

	diagnostics.Logger(ctx).Debug("executing GetContext", kvp.String("query", query), kvp.Any("args", args))

	return e.ex.GetContext(ctx, dest, query, args...)
}

func (e *tracingExecutor) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	ctx, span := tracing.ChildSpan(ctx, "mysql.select")
	span.SetAttributes(attribute.String("query", query))
	defer span.End()

	diagnostics.Logger(ctx).Debug("executing SelectContext", kvp.String("query", query), kvp.Any("args", args))

	return e.ex.SelectContext(ctx, dest, query, args...)
}

func (e *tracingExecutor) QueryRowxContext(ctx context.Context, query string, args ...interface{}) Row {
	ctx, span := tracing.ChildSpan(ctx, "mysql.query_row")
	span.SetAttributes(attribute.String("query", query))
	defer span.End()

	diagnostics.Logger(ctx).Debug("executing QueryRowxContext", kvp.String("query", query), kvp.Any("args", args))

	return e.ex.QueryRowxContext(ctx, query, args...)
}

func (e *tracingExecutor) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	ctx, span := tracing.ChildSpan(ctx, "mysql.exec")
	span.SetAttributes(attribute.String("query", query))
	defer span.End()

	diagnostics.Logger(ctx).Debug("executing ExecContext", kvp.String("query", query), kvp.Any("args", args))

	return e.ex.ExecContext(ctx, query, args...)
}

func (e *tracingExecutor) unwrap() (*sqlx.DB, error) {
	return e.ex.unwrap()
}
