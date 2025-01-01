package logger

import (
	"context"
	"sync"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

var (
	globalLogger *Logger
	mu           sync.Mutex
)

func GetLogger() *Logger {
	if globalLogger == nil {
		return NewLogger(log.NewNullLogger())
	}

	return globalLogger
}

func GetBaseLogger() log.Logger {
	return GetLogger().base
}

func SetLogger(baseLogger log.Logger) {
	mu.Lock()
	globalLogger = NewLogger(baseLogger)
	mu.Unlock()
}

func Info(ctx context.Context, msg string, fields ...kvp.Field) {
	GetLogger().Info(ctx, msg, fields...)
}

func Warn(ctx context.Context, msg string, fields ...kvp.Field) {
	GetLogger().Warn(ctx, msg, fields...)
}

func Debug(ctx context.Context, msg string, fields ...kvp.Field) {
	GetLogger().Debug(ctx, msg, fields...)
}

func Error(ctx context.Context, msg string, fields ...kvp.Field) {
	GetLogger().Error(ctx, msg, fields...)
}

func ErrorWithReport(ctx context.Context, msg string, err error, fields ...kvp.Field) {
	GetLogger().ErrorWithReport(ctx, msg, err, fields...)
}

func Fatal(ctx context.Context, msg string, fields ...kvp.Field) {
	GetLogger().Fatal(ctx, msg, fields...)
}

func WithFields(fields ...kvp.Field) *Logger {
	return GetLogger().WithFields(fields...)
}

func WithError(err error) *Logger {
	return GetLogger().WithError(err)
}
