package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/go-redis/redis/v8"
	lru "github.com/hashicorp/golang-lru/v2"
)

// KVRedis is a Redis implementation of KV
type (
	KVRedis struct {
		client   *redis.Client
		intCache *lru.Cache[string, int64]
		strCache *lru.Cache[string, string]
		logger   log.Logger
		statter  stats.Client
	}
)

const maxCacheEntries = 100_000

var _ KVResolver = &KVRedis{}

// NewKVRedis creates a new KVRedis
func NewKVRedis(client *redis.Client, logger log.Logger, statter stats.Client) (*KVRedis, error) {
	intCache, err := lru.New[string, int64](maxCacheEntries)
	if err != nil {
		return nil, fmt.Errorf("failed to create int cache: %w", err)
	}
	strCache, err := lru.New[string, string](maxCacheEntries)
	if err != nil {
		return nil, fmt.Errorf("failed to create string cache: %w", err)
	}
	logger = logger.WithFields(kvp.String("component", "kvredis"))
	return &KVRedis{
		client:   client,
		intCache: intCache,
		strCache: strCache,
		logger:   logger,
		statter:  statter,
	}, nil
}

// AddInt64Resource adds a resource whose value is an int64 to Redis
func (k *KVRedis) AddInt64Resource(ctx context.Context, namespace, key string, value int64) error {
	key = namespace + ":int64:" + key
	k.logger.Info("adding int64 resource",
		kvp.String("namespace", namespace), kvp.Int64("value", value), kvp.String("key", key))
	if r := k.client.Set(ctx, key, value, 0); r.Err() != nil {
		return fmt.Errorf("failed to set key %s: %w", key, r.Err())
	}
	return nil
}

// ResolveInt64Resource resolves a resource whose value is an int64 from Redis
func (k *KVRedis) ResolveInt64Resource(ctx context.Context, namespace, key string) (int64, error) {
	key = namespace + ":int64:" + key
	logger := k.logger.WithFields(kvp.String("namespace", namespace), kvp.String("key", key))
	if v, ok := k.intCache.Get(key); ok {
		logger.Debug("got int64 resource from cache", kvp.Int64("value", v))
		return v, nil
	}
	r := k.client.Get(ctx, key)
	if r.Err() != nil {
		return 0, fmt.Errorf("failed to get key %s: %w", key, r.Err())
	}
	v, err := r.Int64()
	if err != nil {
		return 0, fmt.Errorf("failed to convert value to int64 from redis: %w", err)
	}
	logger.Info("got int64 resource", kvp.Int64("value", v))
	if v > 0 {
		_ = k.intCache.Add(key, v)
	}
	return v, nil
}

// AddStringResource adds a resource whose value is a string to Redis
func (k *KVRedis) AddStringResource(ctx context.Context, namespace, key, value string) error {
	key = namespace + ":str:" + key
	k.logger.Info("adding string resource",
		kvp.String("namespace", namespace), kvp.String("value", value), kvp.String("key", key))
	if r := k.client.Set(ctx, key, value, 0); r.Err() != nil {
		return fmt.Errorf("failed to set key %s: %w", key, r.Err())
	}
	return nil
}

// ResolveStringResource resolves a resource whose value is a string from Redis
func (k *KVRedis) ResolveStringResource(ctx context.Context, namespace, key string) (string, error) {
	key = namespace + ":str:" + key
	logger := k.logger.WithFields(kvp.String("namespace", namespace), kvp.String("key", key))
	if v, ok := k.strCache.Get(key); ok {
		logger.Debug("got string resource from cache", kvp.String("value", v))
		return v, nil
	}
	r := k.client.Get(ctx, key)
	if r.Err() != nil {
		return "", fmt.Errorf("failed to get key %s: %w", key, r.Err())
	}
	v, err := r.Result()
	if err != nil {
		return "", fmt.Errorf("failed to convert value to string from redis: %w", err)
	}
	logger.Info("got string resource", kvp.String("value", v))
	if v != "" {
		_ = k.strCache.Add(key, v)
	}
	return v, nil
}

// ResourceExists checks if a string or int resource exists in Redis
func (k *KVRedis) ResourceExists(ctx context.Context, namespace, key string) (bool, error) {
	strKey := namespace + ":str:" + key
	strResp := k.client.Exists(ctx, strKey)
	if strResp.Err() != nil {
		return false, fmt.Errorf("failed to check if key %s exists: %w", strKey, strResp.Err())
	}

	logger := k.logger.WithFields(kvp.String("namespace", namespace), kvp.String("key", strKey))
	logger.Info("checked if resource exists", kvp.Bool("exists", strResp.Val() == 1))
	if strResp.Val() == 1 {
		return true, nil
	}

	intKey := namespace + ":int64:" + key
	intResp := k.client.Exists(ctx, intKey)
	if intResp.Err() != nil {
		return false, fmt.Errorf("failed to check if key %s exists: %w", intKey, intResp.Err())
	}

	logger.Info("checked if resource exists", kvp.Bool("exists", intResp.Val() == 1))

	return intResp.Val() == 1, nil
}
