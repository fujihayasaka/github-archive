package cachebreaker

import (
	"context"
	"time"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/cache"
)

type circuitBreakerOptions struct {
	setTimeout time.Duration
	getTimeout time.Duration
	obs        *observability.Observability
}

func WithTimeouts(get, set time.Duration) CircuitBreakerOption {
	return func(opts *circuitBreakerOptions) {
		opts.getTimeout = get
		opts.setTimeout = set
	}
}

func WithTelemetry(obs *observability.Observability) CircuitBreakerOption {
	return func(opts *circuitBreakerOptions) {
		opts.obs = obs
	}
}

type CircuitBreakerOption func(*circuitBreakerOptions)

type failfast struct {
	opts  *circuitBreakerOptions
	cache cache.ExpiringCache
	bk    *circuit.Breaker
}

func CircuitBreaker(cache cache.ExpiringCache, breaker *circuit.Breaker, opts ...CircuitBreakerOption) cache.ExpiringCache {
	opt := &circuitBreakerOptions{
		obs: observability.NewNullObservability(),
	}
	for _, o := range opts {
		o(opt)
	}
	return &failfast{
		opts:  opt,
		cache: cache,
		bk:    breaker,
	}
}

func (ff *failfast) Set(ctx context.Context, key string, value []byte, now time.Time, expiresIn time.Duration) (err error) {
	if !ff.bk.Ready() {
		ff.opts.obs.Counter(ctx, "cache.breaker.set_skipped_because_open", nil, 1)
		return nil
	}

	if ff.opts.setTimeout != 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, ff.opts.setTimeout)
		defer cancel()
	}

	err = ff.cache.Set(ctx, key, value, now, expiresIn)
	if err != nil && err != context.Canceled {
		ff.bk.Fail()
		ff.opts.obs.Counter(ctx, "cache.breaker.observed_failure", statter.Tags{"call": "set"}, 1)
	} else {
		ff.bk.Success()
	}
	return err
}

func (ff *failfast) Get(ctx context.Context, key string, now time.Time) (value *cache.ExpiringValue, found bool, err error) {
	if !ff.bk.Ready() {
		return nil, false, nil
	}

	if ff.opts.getTimeout != 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, ff.opts.getTimeout)
		defer cancel()
	}

	value, found, err = ff.cache.Get(ctx, key, now)
	if err != nil && err != context.Canceled {
		ff.bk.Fail()
		ff.opts.obs.Counter(ctx, "cache.breaker.observed_failure", statter.Tags{"call": "get"}, 1)
	} else {
		ff.bk.Success()
	}
	return value, found, err
}
