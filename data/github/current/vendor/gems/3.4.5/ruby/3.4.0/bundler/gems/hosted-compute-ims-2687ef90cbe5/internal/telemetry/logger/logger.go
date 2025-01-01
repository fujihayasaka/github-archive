package logger

import (
	"context"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/hosted-compute-ims/internal/telemetry/reporter"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

type Logger struct {
	base log.Logger
}

func NewLogger(base log.Logger) *Logger {
	return &Logger{
		base: base,
	}
}

func (l *Logger) Info(ctx context.Context, msg string, fields ...kvp.Field) {
	l.logWithFieldsFromCtx(ctx, log.InfoLevel, msg, fields...)
}

func (l *Logger) Warn(ctx context.Context, msg string, fields ...kvp.Field) {
	l.logWithFieldsFromCtx(ctx, log.WarnLevel, msg, fields...)
}

func (l *Logger) Debug(ctx context.Context, msg string, fields ...kvp.Field) {
	l.logWithFieldsFromCtx(ctx, log.DebugLevel, msg, fields...)
}

func (l *Logger) Error(ctx context.Context, msg string, fields ...kvp.Field) {
	l.logWithFieldsFromCtx(ctx, log.ErrorLevel, msg, fields...)
}

func (l *Logger) ErrorWithReport(ctx context.Context, msg string, err error, fields ...kvp.Field) {
	l.WithError(err).Error(ctx, msg, fields...)

	if errors.Is(err, context.Canceled) {
		return
	}

	reporter.Report(ctx, err, fields...)
}

func (l *Logger) Fatal(ctx context.Context, msg string, fields ...kvp.Field) {
	l.logWithFieldsFromCtx(ctx, log.FatalLevel, msg, fields...)
}

func (l *Logger) WithFields(fields ...kvp.Field) *Logger {
	return l.with(l.base.WithFields(fields...))
}

func (l *Logger) WithError(err error) *Logger {
	return l.with(l.base.WithError(err))
}

func (l *Logger) with(new log.Logger) *Logger {
	return &Logger{
		base: new,
	}
}

func (l *Logger) logWithFieldsFromCtx(ctx context.Context, level log.Level, msg string, newFields ...kvp.Field) {
	fields := stash.LoggingFieldsFromContext(ctx)
	if len(newFields) > 0 {
		fields = append(fields, newFields...)
	}

	l.base.Log(level, msg, stash.UniqueFields(fields)...)
}
