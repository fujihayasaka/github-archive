// Package logs implements a context-aware logger.
package logs

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y"
)

// NullTelem is a telemetry provider that does not emit any logs.
var NullTelem = &telemetry.Provider{
	Logger: log.NewNullLogger(),
}

type logger struct {
	log.Logger
}

// New logger to extend the functionality of base logger with automatic context handling.
// In order for this to work, we need to override all the methods that return a new logger,
// to make sure that always a logger of our own custom type is returned.
// This gives us the opportunity to make some additional customizations.
func New(l log.Logger) log.Logger {
	return logger{Logger: l}
}

func (l logger) WithFields(fields ...kvp.Field) log.Logger {
	return New(l.Logger.WithFields(fields...))
}

// WithError returns a new logger with the error field added as a string.
// See https://github.com/github/github-telemetry-go/issues/174#issuecomment-1351807103 for the rationale.
func (l logger) WithError(err error) log.Logger {
	return l.
		WithFields(kvp.String("error", err.Error())).
		WithFields(kvp.String("error_type", errors.Type(err)))
}

// WithContext adds all the context fields to the logger.
// We DO NOT call the original WithContext as it only makes sense to call it within a span,
// and it emits a debug log otherwise. We should call the original once we add tracing support.
func (l logger) WithContext(ctx context.Context) log.Logger {
	return l.WithFields(CtxFields(ctx)...)
}

func (l logger) Named(name string) log.Logger {
	return New(l.Logger.Named(name))
}

func (l logger) WithLevel(level log.Level) log.Logger {
	return New(l.Logger.WithLevel(level))
}

// CtxFields extracts fields from the provided context
//
// Example:
//
//	func (c *Consumer) Run(ctx context.Context) error {
//		logger.With(logs.CtxFields(ctx)...).Info("Starting Run")
//	}
func CtxFields(ctx context.Context) []kvp.Field {
	fields := make([]kvp.Field, 0)

	if val := o11y.CtxGetDeploymentEnv(ctx); val != "" {
		fields = append(fields, kvp.String("deployment.environment", val))
	}

	if val := o11y.CtxGetUnit(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifyd.unit.name", val))
	}

	if val := o11y.CtxGetRequestID(ctx); val != "" {
		fields = append(fields, kvp.String("gh.request_id", val))
	}

	if val := o11y.CtxGetAqueductParallelJobs(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifyd.aqueduct.parallel_jobs", val))
	}

	if val := o11y.CtxGetAqueductApp(ctx); val != "" {
		fields = append(fields, kvp.String("gh.aqueduct.app", val))
	}

	if val := o11y.CtxGetAqueductQueue(ctx); val != "" {
		fields = append(fields, kvp.String("gh.aqueduct.queue.name", val))
	}

	if val := o11y.CtxGetHydroConsumer(ctx); val != "" {
		fields = append(fields, kvp.String("messaging.client_id", val))
	}

	if val := o11y.CtxGetHydroOffset(ctx); val != "" {
		fields = append(fields, kvp.String("messaging.message.offset", val))
	}

	if val := o11y.CtxGetHydroPartition(ctx); val != "" {
		fields = append(fields, kvp.String("messaging.message.partition", val))
	}

	if val := o11y.CtxGetHydroTopic(ctx); val != "" {
		fields = append(fields, kvp.String("messaging.message.topic", val))
	}

	if val := o11y.CtxGetNotificationID(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifyd.notification.id", val))
	}

	if val := o11y.CtxGetListID(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.list.id", val))
	}

	if val := o11y.CtxGetListType(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.list.type", val))
	}

	if val := o11y.CtxGetThreadID(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.thread.id", val))
	}

	if val := o11y.CtxGetThreadType(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.thread.type", val))
	}

	if val := o11y.CtxGetCommentID(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.comment.id", val))
	}

	if val := o11y.CtxGetCommentType(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.comment.type", val))
	}

	if val := o11y.CtxGetReasons(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifyd.reasons", val))
	}

	if val := o11y.CtxGetChannel(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifyd.channel", val))
	}

	if val := o11y.CtxGetActorID(ctx); val != int64(0) {
		fields = append(fields, kvp.Int64("gh.actor.id", val))
	}

	if val := o11y.CtxGetUserID(ctx); val != int64(0) {
		fields = append(fields, kvp.Int64("gh.user.id", val))
	}

	if val := o11y.CtxGetSubjectType(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.subject.type", val))
	}

	if val := o11y.CtxGetSubjectValue(ctx); val != "" {
		fields = append(fields, kvp.String("gh.notifications.subject.id", val))
	}

	if val := o11y.CtxGetPackage(ctx); val != "" {
		fields = append(fields, kvp.String("code.namespace", val))
	}

	if val := o11y.CtxGetMethod(ctx); val != "" {
		fields = append(fields, kvp.String("code.function", val))
	}

	if val := o11y.CtxGetTenantSlug(ctx); val != "" {
		fields = append(fields, kvp.String("gh.tenant", val))
	}

	return fields
}
