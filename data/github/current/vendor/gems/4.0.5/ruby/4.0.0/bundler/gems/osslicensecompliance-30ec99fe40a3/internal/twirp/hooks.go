package twirp

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/twitchtv/twirp"
)

type contextKey string

const requestStartTimeKey contextKey = "request_start_time"

// DefaultHooks returns a set of recommended hooks.
func DefaultHooks(logger log.Logger, reporter *exceptions.Reporter, statter stats.Client) (*twirp.ServerHooks, error) {
	hooks := twirp.ChainHooks(
		twhooks.TimingHooks(),
		twhooks.StoreTwirpErrorHooks(),
		loggingHook(logger),
		twstats.DefaultHooks(statter),
		twhooks.TraceHooks(),
		errorReporterHook(logger, reporter),
		statsReporterHook(statter),
	)

	return hooks, nil
}

func loggingHook(logger log.Logger) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		ResponseSent: func(ctx context.Context) {
			fields := twirpLogTags(ctx)
			// Get request duration from timing hooks
			duration := twhooks.RequestDuration(ctx)
			fields = append(fields, kvp.Duration("request_duration", duration))

			err, ok := twhooks.GetTwirpError(ctx)
			// Log at error level for non-404 HTTP status codes, otherwise log at info level
			if ok && twirp.ServerHTTPStatusFromErrorCode(err.Code()) != http.StatusNotFound {
				if cause := errors.Unwrap(err); cause != nil {
					fields = append(fields, kvp.String("cause", cause.Error()))
				}
				logger.WithError(err).Error("twirp error", fields...)
				return
			}
			logger.WithFields(fields...).Info("twirp request")
		},
	}
}

func statsReporterHook(statter stats.Client) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			tags := twirpTags(ctx)
			statter.Counter("twirp.request.received", tags, 1)
			return ctx, nil
		},
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			tags := twirpTags(ctx)
			statter.Counter("twirp.request.routed", tags, 1)
			return context.WithValue(ctx, requestStartTimeKey, time.Now()), nil
		},
		ResponseSent: func(ctx context.Context) {
			tags := twirpTags(ctx)
			if startTime, ok := ctx.Value(requestStartTimeKey).(time.Time); ok {
				execDuration := time.Since(startTime)
				statter.DistributionMs("twirp.request.execution", tags, execDuration)
			}
		},
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			httpStatus := twirp.ServerHTTPStatusFromErrorCode(twerr.Code())
			// Do not consider 404 (not found) status code as an error metric
			if httpStatus == http.StatusNotFound {
				return ctx
			}
			tags := twirpTags(ctx)
			statter.Counter("twirp.request.error", tags, 1)
			return ctx
		},
	}
}

// errorReporterHook reports an errors with the given reporter.
func errorReporterHook(logger log.Logger, reporter *exceptions.Reporter) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			payload := map[string]string{}

			if m, ok := twirp.MethodName(ctx); ok {
				payload["twirp_method"] = m
			}
			if m, ok := twirp.PackageName(ctx); ok {
				payload["twirp_package_name"] = m
			}
			if m, ok := twirp.ServiceName(ctx); ok {
				payload["twirp_service_name"] = m
			}
			if m, ok := twirp.StatusCode(ctx); ok {
				payload["http_status"] = m
			}

			httpStatus := twirp.ServerHTTPStatusFromErrorCode(twerr.Code())
			// Do not report 404 (not found) status code in sentry
			if httpStatus == http.StatusNotFound {
				return ctx
			}

			// twirp wraps errors for pkg/errors interoperability whenever we
			// use "twirp.InternalErrorWith()". This allows us to return the
			// underlying error.
			err := Cause(twerr)

			if err := reporter.Report(ctx, err, payload); err != nil {
				logger.WithError(err).Error("ERROR: Failed to report error.")
			}

			return ctx
		},
	}
}

// Cause is copy-n-pasted from pkg/errors since we're not supposed to use pkg/errors any more, but
// it isn't clear how else to do this particular thing.
func Cause(err error) error {
	type causer interface {
		Cause() error
	}

	for err != nil {
		//nolint:errorlint // we're not casting to an error, so the lint's suggestion won't work.
		cause, ok := err.(causer)
		if !ok {
			break
		}
		err = cause.Cause()
	}
	return err
}

func twirpTags(ctx context.Context) stats.Tags {
	tags := stats.Tags{}
	if m, ok := twirp.MethodName(ctx); ok {
		tags["twirp_method"] = m
	}
	if m, ok := twirp.PackageName(ctx); ok {
		tags["twirp_package_name"] = m
	}
	if m, ok := twirp.ServiceName(ctx); ok {
		tags["twirp_service_name"] = m
	}
	if m, ok := twirp.StatusCode(ctx); ok {
		tags["http_status"] = m
	}
	return tags
}

func twirpLogTags(ctx context.Context) []kvp.Field {
	fields := []kvp.Field{}
	if m, ok := twirp.MethodName(ctx); ok {
		fields = append(fields, kvp.String("twirp_method", m))
	}
	if m, ok := twirp.PackageName(ctx); ok {
		fields = append(fields, kvp.String("twirp_package", m))
	}
	if m, ok := twirp.ServiceName(ctx); ok {
		fields = append(fields, kvp.String("twirp_service", m))
	}
	if m, ok := twirp.StatusCode(ctx); ok {
		fields = append(fields, kvp.String("http_status", m))
	}
	return fields
}
