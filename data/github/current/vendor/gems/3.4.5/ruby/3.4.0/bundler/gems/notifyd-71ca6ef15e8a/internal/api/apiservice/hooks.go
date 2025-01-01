package apiservice

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/otel-instrumentation-go/oteltwirp"
	"github.com/twitchtv/twirp"

	"github.com/github/notifyd/internal/pkg/o11y"
)

// NewHooks creates a chain of twirp hooks to customize the request during its lifecycle.
// Certain events during that lifecycle expect function callbacks to exist and when they do they are called with different purposes.
func NewHooks(ctx context.Context, logger log.Logger, statter stats.Client) (*twirp.ServerHooks, error) {
	return twirp.ChainHooks(
		// set the times at which certain parts of the lifecycle happen so that they can be used for measures of elapsed times,
		// it is a requirement of other hooks.
		twhooks.TimingHooks(),
		// send stats to datadog about requests with info like which RPC method was called and the duration of the request.
		twstats.DefaultHooks(statter),
		// add additional context to the request
		contextHook(ctx),
		// send logs about requests with info like which RPC method was called and the duration of the request.
		twlog.DefaultHooks(logger),
		// distributed tracing hooks
		oteltwirp.NewServerHooks(),
	), nil
}

func contextHook(ctx context.Context) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(reqCtx context.Context) (context.Context, error) {
			reqCtx = o11y.CtxSetDeploymentEnv(reqCtx, o11y.CtxGetDeploymentEnv(ctx))
			return o11y.CtxSetUnit(reqCtx, o11y.CtxGetUnit(ctx)), nil
		},
	}
}
