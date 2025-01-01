package twirp

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/twitchtv/twirp"
)

// NewDefaultHooks returns a set of recommended hooks for twirp servers.
// Hooks source code: https://github.com/github/go-twirp/tree/main/server/hooks
func NewDefaultHooks(logger log.Logger, statter stats.Client) *twirp.ServerHooks {
	hooks := twirp.ChainHooks(
		// records the time at which each hook occurs and stores them in the Context
		// captures any twirp.Errors and store them in the Context
		// creates trace spans for each request
		twhooks.DefaultHooks(),
		twlog.DefaultHooks(logger),    // logs request and response metadata for success and errors
		twstats.DefaultHooks(statter), // records request count, routing duration, response preparation duration, and response sent duration
		logRequestLifecycleHooks(logger),
	)

	return hooks
}

// logRequestLifecycleHooks returns a set of hooks that will log request lifecycle events.
func logRequestLifecycleHooks(logger log.Logger) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			l := logger.WithContext(ctx).WithFields(twlog.DefaultFields(ctx)...)
			l.Debug("Twirp request received")
			return ctx, nil
		},
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			l := logger.WithContext(ctx).WithFields(twlog.DefaultFields(ctx)...)
			l.Info("Twirp request routed")
			return ctx, nil
		},
		ResponsePrepared: func(ctx context.Context) context.Context {
			l := logger.WithContext(ctx).WithFields(twlog.DefaultFields(ctx)...)
			l.Debug("Twirp response prepared")
			return ctx
		},
		ResponseSent: func(ctx context.Context) {
			l := logger.WithContext(ctx).WithFields(twlog.DefaultFields(ctx)...)
			l.Info("Twirp response sent")
		},
	}
}
