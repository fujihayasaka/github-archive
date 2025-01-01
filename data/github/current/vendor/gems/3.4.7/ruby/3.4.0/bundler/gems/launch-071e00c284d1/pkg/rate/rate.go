package rate

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"
	"golang.org/x/time/rate"

	"github.com/github/launch/observability"
)

//revive:disable-next-line:exported
type RateLimiter interface {
	// Allow checks whether the operation should be allowed for a specific `types.GlobalID`
	Allow(ctx context.Context, repoDatabaseID int64) bool
}

// NullRateLimiter is a no-op rate limiter that always allows the operation.
type NullRateLimiter struct{}

func (NullRateLimiter) Allow(_ context.Context, _ int64) bool {
	return true
}

// GhesRateLimiter is a server level rate limiter for GHES.
type GhesRateLimiter struct {
	limiter *rate.Limiter
}

type QueueRateLimitError struct {
}

func (e *QueueRateLimitError) Error() string {
	return "Too many runs queued"
}

// Allow checks if the operation is allowed. `types.GlobalID` in this implementation.
func (r *GhesRateLimiter) Allow(_ context.Context, _ int64) bool {
	return r.limiter.Allow()
}

func NewGHESRateLimiter(maxPerMinute int) *GhesRateLimiter {
	r := rate.Every(time.Duration(maxPerMinute) * time.Minute)
	return &GhesRateLimiter{
		limiter: rate.NewLimiter(r, maxPerMinute),
	}
}

const (
	defaultQueueRateLimitKeyPrefix    = "launch:queue_rate_limits"
	defaultQueueBuildBucketThreshold  = 500
	defaultQueueBuildBucketWindowSize = 10
)

var (
	// Map of Repo Database ID to its maximum per window override.
	queueBuildRateLimitOverrides = map[int64]uint64{
		871197456: 0, // bbq-beets/rate-limited
	}
)

func getQueueBuildOverrides(repoDatabaseID int64) (uint64, bool) {
	overrideValue, has := queueBuildRateLimitOverrides[repoDatabaseID]
	return overrideValue, has
}

// NewQueueBuildRateLimiter provides a per repository rate limiter that is backed by Redis.
func NewQueueBuildRateLimiter(ctx context.Context, obs *observability.Observability, redisClient redis.UniversalClient, breaker *circuit.Breaker, opts ...RedisRateLimiterOption) RateLimiter {
	return newFallbackRateLimiter(
		ctx,
		obs,
		redisClient,
		breaker,
		defaultQueueRateLimitKeyPrefix,
		defaultQueueBuildBucketThreshold,
		defaultQueueBuildBucketWindowSize,
		getQueueBuildOverrides,
		opts...,
	)
}

const (
	defaultWebhookLimitKeyPrefix   = "launch:webhook_rate_limits"
	defaultWebhookBucketThreshold  = 1500
	defaultWebhookBucketWindowSize = 10
)

var (
	// Map of Repo Database ID to its maximum per window override.
	webhookRateLimitOverrides = map[int64]uint64{
		871197456: 0, // bbq-beets/rate-limited
	}
)

func getWebhookOverrides(repoDatabaseID int64) (uint64, bool) {
	overrideValue, has := webhookRateLimitOverrides[repoDatabaseID]
	return overrideValue, has
}

// NewWebhookRateLimiter provides a per repository rate limiter that is backed by Redis.
func NewWebhookRateLimiter(ctx context.Context, obs *observability.Observability, redisClient redis.UniversalClient, breaker *circuit.Breaker, opts ...RedisRateLimiterOption) RateLimiter {
	return newFallbackRateLimiter(
		ctx,
		obs,
		redisClient,
		breaker,
		defaultWebhookLimitKeyPrefix,
		defaultWebhookBucketThreshold,
		defaultWebhookBucketWindowSize,
		getWebhookOverrides,
		opts...,
	)
}
