package log

import (
	"context"
	"errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	sh "github.com/github/go-twirp/v2/server/hooks"
	"github.com/twitchtv/twirp"
)

const loggerName = "go_twirp"

// CustomTimingHooks returns a twirp hook that emits a log line per request.
// If the hook.TimingHooks are not in the twirp.ServerHooks chain BEFORE this, it will panic.
func CustomTimingHooks(logger log.Logger, ffs ...FieldsFunc) *twirp.ServerHooks {
	return CustomTimingHooksWithLevel(logger, log.InfoLevel, ffs...)
}

// CustomTimingHooksWithLevel is like CustomTimingHooks but takes a desired log level
// that each request log will be fired at.
func CustomTimingHooksWithLevel(logger log.Logger, level log.Level, ffs ...FieldsFunc) *twirp.ServerHooks {
	hooks := &twirp.ServerHooks{}
	logger = logger.Named(loggerName)

	logFunc := logger.Debug
	switch level {
	case log.InfoLevel:
		logFunc = logger.Info
	case log.ErrorLevel:
		logFunc = logger.Error
	}

	// log request and response metadata
	hooks.ResponseSent = func(ctx context.Context) {
		fields := genFields(ctx, ffs)
		fields = append(fields, kvp.Duration(sh.RequestDurationLabel, sh.RequestDuration(ctx)))
		logFunc("request", fields...)
	}

	return hooks
}

// CustomErrorHooks logs twirp.Errors with a custom set of fields generated from
// the provided ffs functions. If the twirp.Error in the context has a cause,
// the cause will be logged (not recursively, only the first cause is logged).
//
// The hooks.StoreTwirpErrorHooks must be in the twirp.ServerHooks chain or this won't log.
func CustomErrorHooks(logger log.Logger, ffs ...FieldsFunc) *twirp.ServerHooks {
	hooks := &twirp.ServerHooks{}
	logger = logger.Named(loggerName)

	hooks.ResponseSent = func(ctx context.Context) {
		if err, ok := sh.GetTwirpError(ctx); ok {
			fields := genFields(ctx, ffs)
			if cause := errors.Unwrap(err); cause != nil {
				fields = append(fields, kvp.String("cause", cause.Error()))
			}
			logger.WithError(err).Error("twirp error", fields...)
		}
	}
	return hooks
}

// DefaultHooks the twirp.ServerHooks that are recommended for logging, these also use the default
// set of fields.
// The hooks.StoreTwirpErrorHooks and hooks.TimingHooks must BOTH be in the twirp.ServerHooks chain
// or this will panic.
func DefaultHooks(logger log.Logger) *twirp.ServerHooks {
	return twirp.ChainHooks(
		CustomErrorHooks(logger, DefaultFields),
		CustomTimingHooks(logger, DefaultFields),
	)
}
