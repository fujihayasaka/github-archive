package cache

import (
	"context"
	"sync"
	"time"

	"github.com/go-redis/redis/v8"
)

// Store defines a basic interface to a cache.
type Store interface {
	Get(ctx context.Context, key string) ([]byte, error)
	Set(ctx context.Context, key string, val []byte, ttl time.Duration) error
}

// Redis is a cache.Store implementation using Redis as the backing store.
type Redis struct {
	client *redis.Client
}

func NewRedis(c *redis.Client) *Redis {
	return &Redis{c}
}

type KeyNotPresentType string

const KeyNotPresent KeyNotPresentType = KeyNotPresentType("key not present in cache")

func (e KeyNotPresentType) Error() string {
	return string(e)
}

func (c *Redis) Get(ctx context.Context, key string) ([]byte, error) {
	val, err := c.client.Get(ctx, key).Result()
	if err == redis.Nil {
		return nil, KeyNotPresent
	}
	return []byte(val), err
}

func (c *Redis) Set(ctx context.Context, key string, val []byte, ttl time.Duration) error {
	_, err := c.client.Set(ctx, key, val, ttl).Result()
	return err
}

// InMemory is a cache.Store implementation using an in-memory map.
type InMemory struct {
	mutex sync.Mutex
	m     map[string][]byte
}

func NewInMemory() *InMemory {
	return &InMemory{mutex: sync.Mutex{}, m: make(map[string][]byte)}
}

func (c *InMemory) Get(ctx context.Context, key string) ([]byte, error) {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	val, ok := c.m[key]
	if !ok {
		return nil, KeyNotPresent
	}
	return val, nil
}

func (c *InMemory) Set(ctx context.Context, key string, val []byte, ttl time.Duration) error {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	c.m[key] = val
	return nil
}
