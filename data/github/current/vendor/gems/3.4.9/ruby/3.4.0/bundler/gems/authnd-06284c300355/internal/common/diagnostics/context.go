// Shamelessly based on similar code from authzd:
// https://github.com/github/authzd/blob/9068d53080f4d932dde92ce711e0b8d74a8f3119/internal/trace/trace.go
package diagnostics

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
)

type loggerKey struct{}

// Logger returns the logger available in the context (added with WithLogger function).
// If no logger has been added to the context, the NullLogger will be returned
func Logger(ctx context.Context) log.Logger {
	if logger, ok := ctx.Value(loggerKey{}).(log.Logger); ok && logger != nil {
		return logger
	}
	return log.NewNullLogger()
}

// WithLogger adds the provided log.Logger to the context
func WithLogger(ctx context.Context, log log.Logger) context.Context {
	return context.WithValue(ctx, loggerKey{}, log)
}

// Log fields must use semantic convention: https://thehub.github.com/epd/engineering/dev-practicals/observability/semantic-conventions/user-guide/.
// WithLoggerFields adds the provided kvp.Fields to be used by the logger available in the context,
// and ignores them if the logger is not present. Use WithLogger to add a logger to the context.
func WithLoggerFields(ctx context.Context, fields ...kvp.Field) context.Context {
	if len(fields) == 0 {
		return ctx
	}

	if logger, ok := ctx.Value(loggerKey{}).(log.Logger); ok && logger != nil {
		return WithLogger(ctx, logger.WithFields(fields...))
	}
	return ctx
}

type statterKey struct{}

// Statter returns the stats.Client available in the context (added with WithStatter function).
// If no statter has been added to the context, the NullStatter will be returned
func Statter(ctx context.Context) stats.Client {
	if statter, ok := ctx.Value(statterKey{}).(stats.Client); ok {
		return statter
	}
	return stats.NullStatter
}

// WithStatter adds the provided stats.Client to the context
func WithStatter(ctx context.Context, statter stats.Client) context.Context {
	return context.WithValue(ctx, statterKey{}, statter)
}

// WithStatterTags adds the provided stats.Tags to be used by the statter available in the context,
// and ignores them if the logger is not present. Use WithStatter to add a statter to the context.
func WithStatterTags(ctx context.Context, tags stats.Tags) context.Context {
	if statter, ok := ctx.Value(statterKey{}).(stats.Client); ok {
		return WithStatter(ctx, statter.WithTags(tags))
	}
	return ctx
}

type reporterKey struct{}

// Reporter returns the exceptions.Reporter available in the context (added with WithReporter function).
// If no reporter has been added to the context, the NullReporter will be returned
func Reporter(ctx context.Context) *exceptions.Reporter {
	if reporter, ok := ctx.Value(reporterKey{}).(*exceptions.Reporter); ok {
		return reporter
	}
	return exceptions.NullReporter
}

// WithReporter adds the provided exceptions.Reporter to the context
func WithReporter(ctx context.Context, reporter *exceptions.Reporter) context.Context {
	return context.WithValue(ctx, reporterKey{}, reporter)
}

type integrationTestKey struct{}

// IsIntegrationTest returns true if the context is running within an integration test environment.
func IsIntegrationTest(ctx context.Context) bool {
	if isIntegrationTest, ok := ctx.Value(integrationTestKey{}).(bool); ok {
		return isIntegrationTest
	}
	return false
}

// WithIntegrationTestFlag adds a flag to the context that indicates that the context is running within an integration test environment.
// this function should only ever be used this within test files
func WithIntegrationTestFlag(ctx context.Context) context.Context {
	return context.WithValue(ctx, integrationTestKey{}, true)
}
