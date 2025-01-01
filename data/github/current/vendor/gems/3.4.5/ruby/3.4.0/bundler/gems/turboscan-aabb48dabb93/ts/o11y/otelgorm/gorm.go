// Package otelgorm provide OpenTelemetry instrumentation for GORM v1.
//
// If you are using the newer version of GORM, see https://github.com/go-gorm/opentelemetry
package otelgorm

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"io"

	"github.com/pkg/errors"

	"github.com/jinzhu/gorm"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
	"go.opentelemetry.io/otel/trace"
)

const (
	parentSpanGormKey = "opentelemetryParentSpan"
	spanGormKey       = "opentelemetrySpan"
)

var dbRowsAffected = attribute.Key("db.rows_affected")

// SetSpanToGorm copies the span from the context to the GORM scope.
// This is needed because the GORM callbacks do not have access to the context.
func SetSpanToGorm(ctx context.Context, db *gorm.DB) *gorm.DB {
	if ctx == nil {
		return db
	}
	parentSpan := trace.SpanFromContext(ctx)
	if parentSpan == nil {
		return db
	}
	return db.Set(parentSpanGormKey, parentSpan)
}

// Initialize registers the instrumentation callbacks for the provided DB instance.
func Initialize(db *gorm.DB) {
	provider := otel.GetTracerProvider()
	t := provider.Tracer("github.com/github/turboscan/o11y/otelgorm")

	cb := db.Callback()
	// Create
	cb.Create().Before("gorm:create").Register("otel:before:create", before(t, "gorm.Create"))
	cb.Create().After("gorm:create").Register("otel:after:create", after())

	// Select
	cb.Query().Before("gorm:query").Register("otel:before:select", before(t, "gorm.Query"))
	cb.Query().After("gorm:query").Register("otel:after:select", after())

	// Delete
	cb.Delete().Before("gorm:delete").Register("otel:before:delete", before(t, "gorm.Delete"))
	cb.Delete().After("gorm:delete").Register("otel:after:delete", after())

	// Update
	cb.Update().Before("gorm:update").Register("otel:before:update", before(t, "gorm.Update"))
	cb.Update().After("gorm:update").Register("otel:after:update", after())

	// Row
	cb.RowQuery().Before("gorm:row").Register("otel:before:row", before(t, "gorm.Row"))
	cb.RowQuery().After("gorm:row").Register("otel:after:row", after())
}

// before sets up the span before the operation.
// We fetch the parent span from the scope, as we do not have access to the context at this point.
// We store the new span again in the scope, so that we can access it in the after hook.
func before(tracer trace.Tracer, spanName string) gormHookFunc {
	return func(tx *gorm.Scope) {
		val, ok := tx.Get(parentSpanGormKey)
		if !ok {
			return
		}
		parentSpan, ok := val.(trace.Span)
		if !ok {
			return
		}
		ctx := trace.ContextWithSpan(context.Background(), parentSpan)
		_, newSpan := tracer.Start(ctx, spanName, trace.WithSpanKind(trace.SpanKindClient))
		tx.Set(spanGormKey, newSpan)
	}
}

// after writes down interesting attributes and closes the span.
func after() gormHookFunc {
	return func(tx *gorm.Scope) {
		val, ok := tx.Get(spanGormKey)
		if !ok {
			return
		}
		span, ok := val.(trace.Span)
		if !ok {
			return
		}
		if !span.IsRecording() {
			return
		}
		defer span.End()

		query := tx.SQL

		// TODO: The SQL query contains the operation (SELECT/UPDATE/INSERT/DELETE/...) but it
		// might make sense to have an explicit attribute to support filtering.
		attrs := []attribute.KeyValue{
			semconv.DBSystemMySQL, // TODO: Hardcode mysql because that is mostly what we use.
			semconv.DBStatementKey.String(query),
		}

		if tx.TableName() != "" {
			attrs = append(attrs, semconv.DBSQLTableKey.String(tx.TableName()))
		}
		if tx.DB().RowsAffected != -1 {
			attrs = append(attrs, dbRowsAffected.Int64(tx.DB().RowsAffected))
		}
		span.SetAttributes(attrs...)

		// Check if the query was successful or not.
		lastErr := tx.DB().Error
		if lastErr != nil &&
			!errors.Is(lastErr, gorm.ErrRecordNotFound) &&
			!errors.Is(lastErr, driver.ErrSkip) &&
			!errors.Is(lastErr, io.EOF) && // end of rows iterator
			!errors.Is(lastErr, sql.ErrNoRows) {
			// The errors above are not real errors, but rather expected behavior.
			// If the error is something different from those, we mark the span as errored.
			span.RecordError(tx.DB().Error)
			span.SetStatus(codes.Error, tx.DB().Error.Error())
		}
	}
}

type gormHookFunc func(tx *gorm.Scope)
