// Package cache references https://github.com/github/copilot-api/blob/main/pkg/redis/circuitbreaker.go for a Redis client implementation
package cache

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/redis"
)

// Inspired by https://github.com/github/copilot-api/blob/main/pkg/cache/cache.go

// Store represents a name/value cache store without context.
type Store interface {
	// Get retrieves a value from the cache.
	Get(key string) (string, bool)
	// Set sets a value in the cache with an optional TTL.
	Set(key, value string, ttl time.Duration)
	// Delete removes a value from the cache.
	Delete(key string)
	// GetMultiple retrieves multiple values from the cache.
	GetMultiple(keys []string) (map[string]string, bool)
	// SetMultiple sets multiple values in the cache with an optional TTL.
	SetMultiple(values map[string]string, ttl time.Duration)
	// Incr atomically increments a numeric value in the cache by delta and sets TTL.
	// If the key doesn't exist, it is initialized to 0 before incrementing.
	// Returns the new value and true on success, or 0 and false on error.
	Incr(key string, delta int64, ttl time.Duration) (int64, bool)
	// Decr atomically decrements a numeric value in the cache by delta and sets TTL.
	// If the key doesn't exist, it is initialized to 0 before decrementing.
	// The value is clamped to 0 and will not go negative.
	// Returns the new value and true on success, or 0 and false on error.
	Decr(key string, delta int64, ttl time.Duration) (int64, bool)
}

// NewCacheStore creates a new cache store based on the configuration.
// It uses Redis in production. In development mode, it tries to connect to a local
// Redis server before falling back to an in-memory store.
func NewCacheStore(ctx context.Context, cfg *config.Config, obsv observability.Exporters) (Store, error) {
	rc := cfg.RedisConfiguration()
	if rc == nil {
		obsv.Logger.Info("no Redis configuration found, falling back to in-memory cache store")
		return NewMemoryCacheStore(), nil
	}

	// In development mode, try local Redis first, then fall back to in-memory
	if cfg.IsDevelopment() {
		// Try to connect to local Redis
		redisStore, err := tryLocalRedis(ctx, rc, obsv)
		if err == nil {
			obsv.Logger.Info("connected to local Redis cache store")
			return redisStore, nil
		}
		obsv.Logger.WithError(err).Warn("failed to connect to local Redis, falling back to in-memory cache store")
		return NewMemoryCacheStore(), nil
	}

	obsv.Logger.WithFields(
		kvp.String("redis.provider", rc.Provider.String()),
		kvp.String("redis.host", rc.Host),
	).Info("using redis cache store")

	redisClient, err := redis.NewClient(ctx, rc, obsv)
	if err != nil {
		return nil, goerrors.Errorf("failed to initialize Redis client: %w", err)
	}

	redisCircuitBreaker := redis.NewRedisCircuitBreaker(obsv, rc.Host, redis.RedisResetInterval, redis.RedisOpenTimeout)
	return NewRedisStore(ctx, redisClient, redisCircuitBreaker, obsv), nil
}

// tryLocalRedis attempts to connect to a local Redis server for development.
func tryLocalRedis(ctx context.Context, rc *config.RedisConfig, obsv observability.Exporters) (Store, error) {
	redisClient, err := redis.NewClient(ctx, rc, obsv)
	if err != nil {
		return nil, err
	}

	redisCircuitBreaker := redis.NewRedisCircuitBreaker(obsv, rc.Host, redis.RedisResetInterval, redis.RedisOpenTimeout)
	return NewRedisStore(ctx, redisClient, redisCircuitBreaker, obsv), nil
}
