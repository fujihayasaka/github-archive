package mysql

import freno "github.com/github/go-freno-client"

type ExecutorOption func(*executorOptions)

type executorOptions struct {
	hedging         bool
	tracing         bool
	retries         bool
	detachedContext bool

	primaryReadFallback bool
	throttler           freno.Throttler
}

func WithHedging() ExecutorOption {
	return func(opts *executorOptions) {
		opts.hedging = true
	}
}

func WithTracing() ExecutorOption {
	return func(opts *executorOptions) {
		opts.tracing = true
	}
}

func WithRetries() ExecutorOption {
	return func(opts *executorOptions) {
		opts.retries = true
	}
}

func WithPrimaryReadFallback(throttler freno.Throttler) ExecutorOption {
	return func(opts *executorOptions) {
		opts.primaryReadFallback = true
		opts.throttler = throttler
	}
}

func WithThrottler(throttler freno.Throttler) ExecutorOption {
	return func(opts *executorOptions) {
		opts.throttler = throttler
	}
}

func WithDetachedContext() ExecutorOption {
	return func(opts *executorOptions) {
		opts.detachedContext = true
	}
}
