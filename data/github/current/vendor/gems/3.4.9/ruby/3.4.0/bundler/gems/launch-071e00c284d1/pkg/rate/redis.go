package rate

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/go-kvp"
	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/clock"
)

const (
	counterKeyFormatter = "{%s:r_%d}%d"
)

type redisRateLimiter struct {
	client      redis.UniversalClient
	breaker     *circuit.Breaker
	obs         *observability.Observability
	clock       clock.Clock
	useDarkMode bool
	getOverride func(repoDatabaseID int64) (uint64, bool)

	keyPrefix  string
	threshold  uint64
	windowSize int // In seconds
}

const (
	// Values between 10 and 59 are valid
	defaultExpirationInSec = 10
)

type RedisRateLimiterOption func(*redisRateLimiter)

func WithThreshold(threshold uint64) RedisRateLimiterOption {
	return func(rrl *redisRateLimiter) {
		rrl.threshold = threshold
	}
}

func WithDarkMode() RedisRateLimiterOption {
	return func(rrl *redisRateLimiter) {
		rrl.useDarkMode = true
	}
}

// This option is not exported because it is meant for package scoped unit tests.
func withClock(clock clock.Clock) RedisRateLimiterOption {
	return func(rrl *redisRateLimiter) {
		rrl.clock = clock
	}
}

func newRedisRateLimiter(
	obs *observability.Observability,
	client redis.UniversalClient,
	breaker *circuit.Breaker,
	keyPrefix string,
	threshold uint64,
	windowSize int,
	getOverride func(repoDatabaseID int64) (uint64, bool),
	opts ...RedisRateLimiterOption) *redisRateLimiter {
	rrl := &redisRateLimiter{
		client:      client,
		breaker:     breaker,
		obs:         obs,
		keyPrefix:   keyPrefix,
		threshold:   threshold,
		windowSize:  windowSize,
		clock:       clock.New(),
		getOverride: getOverride,
	}

	for _, opt := range opts {
		opt(rrl)
	}

	return rrl
}

func (rrl *redisRateLimiter) Allow(ctx context.Context, repoDatabaseID int64) bool {
	bucket := rrl.clock.Now().Second() / rrl.windowSize
	key := fmt.Sprintf(counterKeyFormatter, rrl.keyPrefix, repoDatabaseID, bucket)

	tags := statter.Tags{
		tagRateLimitType: rrl.keyPrefix,
		tagDarkMode:      strconv.FormatBool(rrl.useDarkMode),
	}

	kvps := []kvp.Field{
		kvp.Int64("gh.repo.id", repoDatabaseID),
		kvp.Bool("gh.launch.rate_limit.dark_mode", rrl.useDarkMode),
		kvp.String("gh.launch.rate_limit_type", rrl.keyPrefix),
	}

	if !rrl.breaker.Ready() {
		rrl.obs.Counter(ctx, "rate_limit.breaker.set_skipped_because_open", tags, 1)
		rrl.obs.Debug(ctx, "rate limit breaker is open. allowing by default", kvps...)
		return true
	}

	exceededThreshold, err := rrl.isThresholdExceeded(ctx, key, repoDatabaseID)
	if err != nil {
		rrl.obs.Counter(ctx, "rate_limit.breaker.observed_failure", tags.Merge(statter.Tags{"call": "get"}), 1)
		kvps = append(kvps, kvp.Err(err))
		rrl.obs.Error(ctx, "failed to get current state for rate limiter", kvps...)
		rrl.breaker.Fail()
		// Allow, prevents disruptions in the event of a redis outage
		return true
	}

	if exceededThreshold {
		// We are at or beyond the threshold limit, so we should not allow the request
		return false
	}

	err = rrl.incrementWithExpiration(ctx, key)
	if err != nil {
		rrl.obs.Counter(ctx, "rate_limit.breaker.observed_failure", tags.Merge(statter.Tags{"call": "incr"}), 1)
		kvps = append(kvps, kvp.Err(err))
		rrl.obs.Error(ctx, "failed to increment rate limit counter", kvps...)
		rrl.breaker.Fail()

		// Allow, prevents disruptions in the event of a redis outage
		return true
	}

	return true
}

func (rrl *redisRateLimiter) isThresholdExceeded(ctx context.Context, key string, repoID int64) (bool, error) {
	count, err := rrl.client.Get(ctx, key).Uint64()
	if err != nil && err != redis.Nil { // for redis.Nil, we will treat it as a 0 count
		// "false" to indicate this is not at or beyond limit, since we cannot determine it.
		return false, err
	}
	threshold := rrl.threshold
	if override, has := rrl.getOverride(repoID); has {
		threshold = override
	}
	rrl.breaker.Success()
	return count >= threshold, nil
}

func (rrl *redisRateLimiter) incrementWithExpiration(ctx context.Context, key string) error {
	pipeline := rrl.client.TxPipeline()

	incr := pipeline.Incr(ctx, key)
	exp := pipeline.Expire(ctx, key, defaultExpirationInSec*time.Second)

	_, err := pipeline.Exec(ctx)
	if err != nil {
		return err
	}

	if incr.Err() != nil {
		pipeline.Discard()
		return incr.Err()
	}

	if exp.Err() != nil {
		pipeline.Discard()
		return exp.Err()
	}

	return nil
}
