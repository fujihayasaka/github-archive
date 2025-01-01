package twirpserver

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/twitchtv/twirp"
)

// DefaultHooks returns a set of default hooks for a Twirp server.
func DefaultHooks(logger log.Logger, reporter *exceptions.Reporter, statter stats.Client) *twirp.ServerHooks {
	hooks := twirp.ChainHooks(
		twhooks.DefaultHooks(),
		twlog.DefaultHooks(logger),
		twstats.DefaultHooks(statter),
		errorReporterHook(logger, reporter),
	)

	return hooks
}

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
			err := Cause(twerr)

			if err := reporter.Report(ctx, err, payload); err != nil {
				logger.WithError(err).Error("Failed to report error")
			}

			return ctx
		},
	}
}

// Cause is copied from github/go-sample-service since we're not supposed to use pkg/errors anymore
// but still need a way to get the underlying error from a twirp.Error.
func Cause(err error) error {
	type causer interface {
		Cause() error
	}

	for err != nil {
		cause, ok := err.(causer)
		if !ok {
			break
		}
		err = cause.Cause()
	}
	return err
}
