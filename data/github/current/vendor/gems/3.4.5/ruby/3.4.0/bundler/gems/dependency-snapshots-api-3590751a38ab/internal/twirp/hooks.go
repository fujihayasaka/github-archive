package twirp

import (
	"context"
	"net/http"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/otel-instrumentation-go/oteltwirp"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

// DefaultHooks returns a set of recommended hooks.
func DefaultHooks(reporter *exceptions.Reporter, statter stats.Client) (*twirp.ServerHooks, error) {
	hooks := twirp.ChainHooks(
		// capture start times & meta; must be first in chain!
		twhooks.TimingHooks(),
		twhooks.StoreTwirpErrorHooks(),
		// default logging hooks
		twlog.DefaultHooks(log.Named("default")),
		// stats with custom app-level tags
		twstats.CustomRequestCountHooks(statter, statsTagsFn),
		twstats.CustomResponsePreparationHooks(statter, statsTagsFn),
		twstats.CustomResponseSentDurationHooks(statter, statsTagsFn),
		twstats.CustomRequestDurationHooks(statter, statsTagsFn),
		// custom Sentry exception reporter hooks
		errorReporterHook(reporter),
		// default tracing hooks
		oteltwirp.NewServerHooks(),
	)

	return hooks, nil
}

// sentinel header applied to incoming Twirp submission
// requests to power faceting between static manifest and
// direct API snapshot submissions in DD monitors and metrics
const XGitHubDGInternalSnapshot = "X-GITHUB-DG-INTERNAL-SNAPSHOT"

// context key for storing the header if found
type xGHDGInternalSnapshotKey struct{}

// HTTP middleware for extracting the header into the Twirp request context
func WithSnapshotRequestHeadersInContext(base http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		value := r.Header.Get(XGitHubDGInternalSnapshot)
		if len(value) > 0 {
			ctx := r.Context()
			ctx = context.WithValue(ctx, xGHDGInternalSnapshotKey{}, true)
			r = r.WithContext(ctx)
		}

		base.ServeHTTP(w, r)
	})
}

// custom stats tags func that picks up sentinel header for\
// application to std `go-twirp` request stats
func statsTagsFn(ctx context.Context) stats.Tags {
	tags := twstats.DefaultTags(ctx)
	if _, ok := ctx.Value(xGHDGInternalSnapshotKey{}).(bool); ok {
		tags["twirp_internal_snapshot"] = "true"
	}

	return tags
}

// errorReporterHook reports an errors with the given reporter.
func errorReporterHook(reporter *exceptions.Reporter) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			payload := map[string]string{}

			if m, ok := twirp.MethodName(ctx); ok {
				payload["rpc.method"] = m
			}
			if m, ok := twirp.PackageName(ctx); ok {
				// There is no specific `rpc.` SemConv-compliant tag for this.
				// Since this is a code-specific tag, `code.namespace` is used instead.
				payload["code.namespace"] = m
			}
			if m, ok := twirp.ServiceName(ctx); ok {
				payload["rpc.service"] = m
			}
			if m, ok := twirp.StatusCode(ctx); ok {
				payload["http.response.status_code"] = m
			}

			httpStatus := twirp.ServerHTTPStatusFromErrorCode(twerr.Code())
			// don't consider any thing under 500 reportable (no sentry for 100/200/300/400)
			if httpStatus < 500 {
				return ctx
			}

			// twirp wraps errors for pkg/errors interoperability whenever we
			// use "twirp.InternalErrorWith()". This allows us to return the
			// underlying error, but we need the wrapped error for sentry logging.
			// Some gh codebases use .Cause below, but that ruins the reported stack of the error
			err := errors.Unwrap(twerr)

			requestID := requestid.GetGitHubRequestID(ctx)
			if requestID != "" {
				payload["gh.request_id"] = requestID
			}

			// ensure hard-fail needles make it to Sentry when scoped ctx has timed out
			if err := reporter.Report(context.Background(), err, payload); err != nil {
				// logger only needs the tags from scoped ctx, if present
				contextlogger.Error(ctx, "ERROR: Failed to report error.", kvp.String("exception.message", err.Error()))
			}

			return ctx
		},
	}
}
