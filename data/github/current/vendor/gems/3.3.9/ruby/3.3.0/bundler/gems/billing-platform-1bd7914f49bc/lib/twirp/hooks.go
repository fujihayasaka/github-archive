package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
	stats "github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	opentracing "github.com/opentracing/opentracing-go"
	"github.com/pkg/errors"
	twtrace "github.com/twirp-ecosystem/twirp-opentracing"
	"github.com/twitchtv/twirp"
)

// DefaultHooks returns a set of recommended hooks.
func DefaultHooks(logger log.Logger, reporter *exceptions.Reporter, statter stats.Client, tracer opentracing.Tracer) *twirp.ServerHooks {
	hooks := twirp.ChainHooks(
		twhooks.DefaultHooks(),
		twlog.DefaultHooks(logger),
		twstats.DefaultHooks(statter),
		twtrace.NewOpenTracingHooks(tracer),
		errorReporterHook(logger, reporter),
	)

	return hooks
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

			// twirp wraps errors for pkg/errors interoperability whenever we
			// use "twirp.InternalErrorWith()". This allows us to return the
			// underlying error.
			err := errors.Cause(twerr)

			if err := reporter.Report(ctx, err, payload); err != nil {
				logger.WithError(err).Error("Failed to report error")
			}

			return ctx
		},
	}
}
