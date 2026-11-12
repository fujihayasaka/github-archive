package cache

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/redis/go-redis/v9"
	"github.com/sony/gobreaker"
)

// RedisStore is a redis-based implementation of the Store interface.
type RedisStore struct {
	ctx            context.Context
	redisClient    redis.UniversalClient
	circuitBreaker *gobreaker.CircuitBreaker
	obsv           observability.Exporters
}

// NewRedisStore returns a new RedisStore.
func NewRedisStore(ctx context.Context, redisClient redis.UniversalClient, circuitBreaker *gobreaker.CircuitBreaker, obsv observability.Exporters) *RedisStore {
	return &RedisStore{ctx: ctx, redisClient: redisClient, circuitBreaker: circuitBreaker, obsv: obsv}
}

// Get gets the value of the given key from Redis.
func (r *RedisStore) Get(key string) (string, bool) {
	var cacheMiss bool
	var reason string
	defer func() {
		r.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":  "Get",
			"cache_miss": fmt.Sprintf("%t", cacheMiss),
			"reason":     reason,
		}, 1)
	}()

	result, err := r.circuitBreaker.Execute(func() (any, error) {
		s, err := r.redisClient.Get(r.ctx, key).Result()
		if errors.Is(err, redis.Nil) {
			cacheMiss = true
			reason = "not_found"
			return nil, nil
		}
		return s, err
	})

	switch {
	case errors.Is(err, gobreaker.ErrOpenState):
		cacheMiss = true
		reason = "circuit_breaker_open"
	case err != nil:
		cacheMiss = true
	default:
		// No error case
	}

	if err != nil {
		r.obsv.Logger.WithError(err).Error("failed to get value from Redis cache")
		return "", false
	}

	switch v := result.(type) {
	case string:
		return v, true
	default:
		return "", false
	}
}

// GetMultiple gets the values of the given keys from Redis.
func (r *RedisStore) GetMultiple(keys []string) (map[string]string, bool) {
	var cacheMiss bool
	var reason string
	defer func() {
		r.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":  "GetMultiple",
			"cache_miss": fmt.Sprintf("%t", cacheMiss),
			"reason":     reason,
		}, 1)
	}()

	result, err := r.circuitBreaker.Execute(func() (any, error) {
		values, err := r.redisClient.MGet(r.ctx, keys...).Result()
		if err != nil {
			return nil, err
		}

		results := make(map[string]string, len(values))
		for i, value := range values {
			if value != nil {
				if str, ok := value.(string); ok {
					results[keys[i]] = str
				} else {
					cacheMiss = true
				}
			} else {
				cacheMiss = true
			}
		}
		return results, nil
	})

	switch {
	case errors.Is(err, gobreaker.ErrOpenState):
		cacheMiss = true
		reason = "circuit_breaker_open"
	case err != nil:
		cacheMiss = true
	default:
		// No error case
	}

	if err != nil {
		r.obsv.Logger.WithError(err).Error("failed to get multiple values from Redis cache")
		return nil, false
	}

	res, ok := result.(map[string]string)
	if !ok {
		return nil, false
	}
	return res, true
}

// Set sets the value of the given key in Redis.
func (r *RedisStore) Set(key, value string, exp time.Duration) {
	var failed bool
	var reason string
	defer func() {
		r.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":        "Set",
			"operation_failed": fmt.Sprintf("%t", failed),
			"reason":           reason,
		}, 1)
	}()

	_, err := r.circuitBreaker.Execute(func() (any, error) {
		return nil, r.redisClient.Set(r.ctx, key, value, exp).Err()
	})

	switch {
	case errors.Is(err, gobreaker.ErrOpenState):
		failed = true
		reason = "circuit_breaker_open"
	case err != nil:
		failed = true
	default:
		// No error case
	}

	if err != nil {
		r.obsv.Logger.WithError(err).Error("failed to set value in Redis cache")
	}
}

// SetMultiple sets multiple key-value pairs in Redis with TTL.
// Uses pipelining to set keys and their TTLs atomically and efficiently.
func (r *RedisStore) SetMultiple(values map[string]string, ttl time.Duration) {
	var failed bool
	var reason string
	defer func() {
		r.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":        "SetMultiple",
			"operation_failed": fmt.Sprintf("%t", failed),
			"reason":           reason,
		}, 1)
	}()

	_, err := r.circuitBreaker.Execute(func() (any, error) {
		if len(values) > math.MaxInt32/2 {
			return nil, goerrors.New("too many values for SetMultiple operation")
		}

		// Use pipelining to batch all SET and EXPIRE commands together
		// This ensures atomicity and reduces network roundtrips
		pipe := r.redisClient.Pipeline()

		for key, value := range values {
			if ttl > 0 {
				// Use SETEX to atomically set value and TTL in one command
				pipe.SetEx(r.ctx, key, value, ttl)
			} else {
				// No TTL, just set the value
				pipe.Set(r.ctx, key, value, 0)
			}
		}

		// Execute all commands in the pipeline
		_, err := pipe.Exec(r.ctx)
		return nil, err
	})

	switch {
	case errors.Is(err, gobreaker.ErrOpenState):
		failed = true
		reason = "circuit_breaker_open"
	case err != nil:
		failed = true
	default:
		// No error case
	}

	if err != nil {
		r.obsv.Logger.WithError(err).Error("failed to set multiple values in Redis cache")
	}
}

// Incr increments the value of a key by delta atomically.
// If the key doesn't exist, it's initialized to 0 before incrementing.
// Returns the new value and true on success, or 0 and false on error.
//
//nolint:dupword // go-lint identifies false positive for dupword in Lua script
func (r *RedisStore) Incr(key string, delta int64, ttl time.Duration) (int64, bool) {
	var failed bool
	var reason string
	defer func() {
		r.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":        "Incr",
			"operation_failed": fmt.Sprintf("%t", failed),
			"reason":           reason,
		}, 1)
	}()

	result, err := r.circuitBreaker.Execute(func() (any, error) {
		// Use Lua script for atomic increment and TTL setting
		luaScript := `
			local current = redis.call('GET', KEYS[1])
			if current == false then
				current = 0
			else
				current = tonumber(current)
				if current == nil then
					current = 0
				end
			end

			local delta = tonumber(ARGV[1])
			local newVal = current + delta
			redis.call('SET', KEYS[1], newVal)

			if ARGV[2] ~= '0' then
				redis.call('EXPIRE', KEYS[1], ARGV[2])
			end

			return newVal
		`

		ttlSeconds := "0"
		if ttl > 0 {
			ttlSeconds = fmt.Sprintf("%d", int64(ttl.Seconds()))
		}

		result, err := r.redisClient.Eval(r.ctx, luaScript, []string{key}, delta, ttlSeconds).Result()
		if err != nil {
			failed = true
			return int64(0), err
		}

		if val, ok := result.(int64); ok {
			return val, nil
		}
		return int64(0), nil
	})

	switch {
	case errors.Is(err, gobreaker.ErrOpenState):
		failed = true
		reason = "circuit_breaker_open"
	case err != nil:
		failed = true
	default:
		// No error case
	}

	if err != nil {
		r.obsv.Logger.WithError(err).Error("failed to increment value in Redis cache")
		return 0, false
	}

	if val, ok := result.(int64); ok {
		return val, true
	}
	return 0, false
}

// Decr decrements the value of a key by delta atomically.
// If the key doesn't exist or the result would be negative, it returns 0.
// Returns the new value and true on success, or 0 and false on error.
//
//nolint:dupword // go-lint identifies false positive for dupword in Lua script
func (r *RedisStore) Decr(key string, delta int64, ttl time.Duration) (int64, bool) {
	var failed bool
	var reason string
	defer func() {
		r.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":        "Decr",
			"operation_failed": fmt.Sprintf("%t", failed),
			"reason":           reason,
		}, 1)
	}()

	result, err := r.circuitBreaker.Execute(func() (any, error) {
		// Use Lua script for atomic decrement that never goes below 0
		luaScript := `
			local current = redis.call('GET', KEYS[1])
			if current == false then
				current = 0
			else
				current = tonumber(current)
				if current == nil then
					current = 0
				end
			end

			local delta = tonumber(ARGV[1])
			local newVal = math.max(0, current - delta)
			redis.call('SET', KEYS[1], newVal)

			if ARGV[2] ~= '0' then
				redis.call('EXPIRE', KEYS[1], ARGV[2])
			end

			return newVal
		`

		ttlSeconds := "0"
		if ttl > 0 {
			ttlSeconds = fmt.Sprintf("%d", int64(ttl.Seconds()))
		}

		result, err := r.redisClient.Eval(r.ctx, luaScript, []string{key}, delta, ttlSeconds).Result()
		if err != nil {
			failed = true
			return int64(0), err
		}

		if val, ok := result.(int64); ok {
			return val, nil
		}
		return int64(0), nil
	})

	switch {
	case errors.Is(err, gobreaker.ErrOpenState):
		failed = true
		reason = "circuit_breaker_open"
	case err != nil:
		failed = true
	default:
		// No error case
	}

	if err != nil {
		r.obsv.Logger.WithError(err).Error("failed to decrement value in Redis cache")
		return 0, false
	}

	if val, ok := result.(int64); ok {
		return val, true
	}
	return 0, false
}
