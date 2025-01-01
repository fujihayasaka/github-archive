package cacheobs

import (
	"context"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/cache"
)

type observeOptions struct {
	statsPrefix string
	traceTags   []kvp.Field
}

func WithStatsPrefix(prefix string) ObserveOption {
	return func(opts *observeOptions) {
		opts.statsPrefix = prefix
	}
}

func WithTraceTags(tags ...kvp.Field) ObserveOption {
	return func(opts *observeOptions) {
		opts.traceTags = append(opts.traceTags, tags...)
	}
}

type ObserveOption func(*observeOptions)

type cacheObs struct {
	opts  *observeOptions
	name  string
	cache cache.ExpiringCache
	obs   *observability.Observability
}

func Observe(cache cache.ExpiringCache, name string, obs *observability.Observability, opts ...ObserveOption) cache.ExpiringCache {
	opt := &observeOptions{}
	for _, o := range opts {
		o(opt)
	}
	opt.traceTags = append(opt.traceTags, kvp.String(CacheName, name))
	return &cacheObs{
		opts:  opt,
		name:  name,
		cache: cache,
		obs:   obs,
	}
}

func (co *cacheObs) Set(ctx context.Context, key string, value []byte, now time.Time, expiresIn time.Duration) error {
	tags := statter.Tags{"cache_name": co.name}

	otelAttributes := kvp.MapAttributes(nil, co.opts.traceTags...)
	ctx, span := tracing.Start(ctx, trace.WithAttributes(otelAttributes...))
	defer span.End()

	span.SetAttributes(attribute.String(CacheKey, key))

	span.AddEvent("cache-set", trace.WithAttributes(
		attribute.String(CacheKey, key),
		attribute.Float64(CacheExpiresIn, expiresIn.Seconds()),
	))

	err := co.cache.Set(ctx, key, value, now, expiresIn)
	tags["error"] = strconv.FormatBool(err != nil)

	co.obs.Counter(ctx, co.opts.statsPrefix+"cache.set.count", tags, 1)
	return tracing.RecordError(span, err)
}

func (co *cacheObs) Get(ctx context.Context, key string, now time.Time) (value *cache.ExpiringValue, found bool, err error) {
	tags := statter.Tags{"cache_name": co.name}

	otelAttributes := kvp.MapAttributes(nil, co.opts.traceTags...)
	ctx, span := tracing.Start(ctx, trace.WithAttributes(otelAttributes...))
	defer span.End()

	span.SetAttributes(attribute.String(CacheKey, key))

	value, found, err = co.cache.Get(ctx, key, now)
	tags["error"] = strconv.FormatBool(err != nil)

	span.SetAttributes(attribute.Bool(CacheHit, found))

	tags["cache_hit"] = strconv.FormatBool(found)
	if value != nil {
		expiresInS := value.Expiry.Sub(now).Seconds()
		span.AddEvent("cache-get", trace.WithAttributes(
			attribute.String(CacheValueLen, key),
			attribute.Float64(CacheExpiresIn, expiresInS),
		))
	}

	co.obs.Counter(ctx, co.opts.statsPrefix+"cache.get.count", tags, 1)
	return value, found, tracing.RecordError(span, err)
}
