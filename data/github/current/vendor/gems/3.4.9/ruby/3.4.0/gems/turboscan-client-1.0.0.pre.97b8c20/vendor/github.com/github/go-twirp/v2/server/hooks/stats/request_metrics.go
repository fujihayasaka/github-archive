// Package stats provides Twirp hooks for capturing request metrics and sending them using a stats client.
package stats

import (
	"context"

	"github.com/github/go-stats"
	"github.com/github/go-twirp/v2/server/hooks"
	"github.com/twitchtv/twirp"
)

// CustomRequestCountHooks records request count statistics with a custom set of stats.Tags that are
// generated from the context.Context using the tagFn arguments.
func CustomRequestCountHooks(record stats.Client, tagFn ...TagsFunc) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			record.Counter(hooks.RequestCountLabel, genTags(ctx, tagFn...), 1)
			return ctx, nil
		},
	}
}

// CustomRoutingDurationHooks records request routing duration statistics with a custom set of
// stats.Tags that are generated from the context.Context using the tagFn arguments.
// If the hook.TimingHooks are not in the twirp.ServerHooks chain BEFORE this, it will panic.
func CustomRoutingDurationHooks(record stats.Client, tagFn ...TagsFunc) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			record.DistributionMs(
				hooks.RequestRoutedDurationLabel,
				genTags(ctx, tagFn...),
				hooks.RoutingDuration(ctx))
			return ctx, nil
		},
	}
}

// CustomResponsePreparationHooks records response preparation duration statistics with a custom set
// of stats.Tags that are generated from the context.Context using the tagFn arguments.
// If the hook.TimingHooks are not in the twirp.ServerHooks chain BEFORE this, it will panic.
func CustomResponsePreparationHooks(record stats.Client, tagFn ...TagsFunc) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		ResponsePrepared: func(ctx context.Context) context.Context {
			record.DistributionMs(
				hooks.ResponsePreparedDurationLabel,
				genTags(ctx, tagFn...),
				hooks.ResponsePreparationDuration(ctx),
			)
			return ctx
		},
	}
}

// CustomResponseSentDurationHooks records the duration statistics of sending the response, with a
// custom set of stats.Tags that are generated from the context.Context using the tagFn arguments.
// If the hook.TimingHooks are not in the twirp.ServerHooks chain BEFORE this, it will panic.
func CustomResponseSentDurationHooks(record stats.Client, tagFn ...TagsFunc) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		ResponseSent: func(ctx context.Context) {
			record.DistributionMs(
				hooks.ResponseSentDurationLabel,
				genTags(ctx, tagFn...),
				hooks.ResponseSendingDuration(ctx),
			)
		},
	}
}

// CustomRequestDurationHooks records request duration statistics with a custom set of stats.Tags
// that are generated from the context.Context using the tagFn arguments.
// If the hook.TimingHooks are not in the twirp.ServerHooks chain BEFORE this, it will panic.
func CustomRequestDurationHooks(record stats.Client, tagFn ...TagsFunc) *twirp.ServerHooks {
	return &twirp.ServerHooks{
		ResponseSent: func(ctx context.Context) {
			record.DistributionMs(
				hooks.RequestDurationLabel,
				genTags(ctx, tagFn...),
				hooks.RequestDuration(ctx))
		},
	}
}

// DefaultHooks include the recommended stats that should be published for a Twirp service.
// If the hook.TimingHooks are not in the twirp.ServerHooks chain BEFORE this, it will panic.
func DefaultHooks(record stats.Client) *twirp.ServerHooks {
	return twirp.ChainHooks(
		CustomRequestCountHooks(record, DefaultTags),
		CustomResponsePreparationHooks(record, DefaultTags),
		CustomResponseSentDurationHooks(record, DefaultTags),
		CustomRequestDurationHooks(record, DefaultTags),
	)
}
