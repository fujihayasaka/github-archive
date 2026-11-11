package redis

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/redis/go-redis/v9"
	"github.com/sony/gobreaker"
)

// Heavily based on https://github.com/github/copilot-api/blob/2b1fae4f328cd35e1d4ac18e1311bf8768a1e686/pkg/cache/rediscachestore.go

// Store is a redis-based implementation of the Store interface.
type Store struct {
	redisClient    redis.UniversalClient
	circuitBreaker *gobreaker.CircuitBreaker
	obsv           *observability.Exporters
	// See https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/#hash-tags
	// We use constants for this today because our use of the cluster client is naive.
	// If you want to use MGet or MSet, you must set hashTag.
	hashTag string
}

var _ sweagentd.CacheStore = (*Store)(nil)

// NewStore returns a new RedisStore.
func NewStore(redisClient redis.UniversalClient, circuitBreaker *gobreaker.CircuitBreaker, obsv *observability.Exporters, hashTag string) *Store {
	return &Store{redisClient: redisClient, circuitBreaker: circuitBreaker, obsv: obsv, hashTag: hashTag}
}

// Get gets the value of the given key from Redis.
func (s *Store) Get(ctx context.Context, key string) (string, error) {
	var cacheMiss bool
	var reason string
	defer func() {
		s.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":  "Get",
			"cache_miss": fmt.Sprintf("%t", cacheMiss),
			"reason":     reason,
		}, 1)
	}()

	result, err := s.circuitBreaker.Execute(func() (interface{}, error) {
		key = s.applyHashTag(key)
		s, err := s.redisClient.Get(ctx, key).Result()
		if errors.Is(err, redis.Nil) {
			cacheMiss = true
			return "", nil
		}
		return s, err
	})

	if errors.Is(err, gobreaker.ErrOpenState) {
		cacheMiss = true
		reason = "circuit_breaker_open"
		return "", nil
	}

	if err != nil {
		return "", err
	}

	switch v := result.(type) {
	case string:
		return v, nil
	default:
		return "", fmt.Errorf("unexpected type %T in RedisStore.Get result", v)
	}
}

// GetMultiple gets the values of the given keys from Redis.
func (s *Store) GetMultiple(ctx context.Context, keys []string) (map[string]string, error) {
	var cacheMiss bool
	var reason string
	defer func() {
		s.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":  "GetMultiple",
			"cache_miss": fmt.Sprintf("%t", cacheMiss),
			"reason":     reason,
		}, 1)
	}()

	taggedKeys := s.applyHashTagM(keys)

	result, err := s.circuitBreaker.Execute(func() (interface{}, error) {
		values, err := s.redisClient.MGet(ctx, taggedKeys...).Result()
		if err != nil {
			return nil, err
		}

		results := make(map[string]string, len(values))
		for i, value := range values {
			valueCast, ok := value.(string)
			if !ok && value != nil {
				return nil, fmt.Errorf("unexpected type %T in RedisStore.GetMultiple MGet result", value)
			}

			if value != nil {
				results[keys[i]] = valueCast
			} else {
				cacheMiss = true
			}
		}
		return results, nil
	})

	if errors.Is(err, gobreaker.ErrOpenState) {
		cacheMiss = true
		reason = "circuit_breaker_open"
		return nil, nil
	}

	if err != nil {
		return nil, err
	}

	resultCast, ok := result.(map[string]string)
	if !ok && result != nil {
		return nil, fmt.Errorf("unexpected type %T in RedisStore.GetMultiple result", result)
	}

	return resultCast, nil
}

// Set sets the value of the given key in Redis.
func (s *Store) Set(ctx context.Context, key, value string, exp time.Duration) error {
	key = s.applyHashTag(key)
	var cacheMiss bool
	var reason string
	defer func() {
		s.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":  "Set",
			"cache_miss": fmt.Sprintf("%t", cacheMiss),
			"reason":     reason,
		}, 1)
	}()

	_, err := s.circuitBreaker.Execute(func() (interface{}, error) {
		return nil, s.redisClient.Set(ctx, key, value, exp).Err()
	})
	cacheMiss = err != nil
	if errors.Is(err, gobreaker.ErrOpenState) {
		reason = "circuit_breaker_open"
		return nil
	}

	return err
}

// SetMultiple sets multiple key-value pairs in Redis.
func (s *Store) SetMultiple(ctx context.Context, values map[string]string, ttl time.Duration) error {
	var cacheMiss bool
	var reason string
	defer func() {
		s.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":  "SetMultiple",
			"cache_miss": fmt.Sprintf("%t", cacheMiss),
			"reason":     reason,
		}, 1)
	}()

	_, err := s.circuitBreaker.Execute(func() (interface{}, error) {
		if len(values) > math.MaxInt32/2 {
			return nil, errors.New("too many values for SetMultiple operation")
		}
		args := make([]interface{}, 0, len(values)*2)
		for key, value := range values {
			args = append(args, s.applyHashTag(key), value)
		}

		err := s.redisClient.MSet(ctx, args...).Err()
		if err != nil {
			return nil, err
		}

		if ttl > 0 {
			for key := range values {
				key = s.applyHashTag(key)
				err := s.redisClient.Expire(ctx, key, ttl).Err()
				if err != nil {
					return nil, err
				}
			}
		}

		return nil, nil
	})
	cacheMiss = err != nil
	if errors.Is(err, gobreaker.ErrOpenState) {
		reason = "circuit_breaker_open"
		return nil
	}

	return err
}

// Delete deletes the given key from Redis.
func (s *Store) Delete(ctx context.Context, key string) error {
	key = s.applyHashTag(key)
	var cacheMiss bool
	var reason string
	defer func() {
		s.obsv.Statter.Counter("cache_operation", stats.Tags{
			"operation":  "Delete",
			"cache_miss": fmt.Sprintf("%t", cacheMiss),
			"reason":     reason,
		}, 1)
	}()

	numDeleted, err := s.circuitBreaker.Execute(func() (interface{}, error) {
		numDeleted, err := s.redisClient.Del(ctx, key).Result()
		return numDeleted, err
	})
	numDeletedCast, ok := numDeleted.(int64)
	if !ok {
		return fmt.Errorf("unexpected type %T in RedisStore.Delete result", numDeleted)
	}

	cacheMiss = err != nil || numDeletedCast == 0
	if errors.Is(err, gobreaker.ErrOpenState) {
		reason = "circuit_breaker_open"
		return nil
	}

	return err
}

func (s *Store) applyHashTagM(keys []string) []string {
	keysCopy := make([]string, len(keys))
	for i, key := range keys {
		keysCopy[i] = s.applyHashTag(key)
	}

	return keysCopy
}

func (s *Store) applyHashTag(key string) string {
	// apply hash tag to beginning of each key if set
	if s.hashTag != "" {
		key = fmt.Sprintf("{%s}%s", s.hashTag, key)
	}
	return key
}
