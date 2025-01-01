package utils

import (
	"time"

	gocache "github.com/patrickmn/go-cache"
)

const (
	NoExpiration      time.Duration = gocache.NoExpiration
	DefaultExpiration time.Duration = gocache.DefaultExpiration
)

type Cache[K ~string, V any] struct {
	cache     *gocache.Cache
	zeroValue V
}

func NewCache[K ~string, V any](defaultExpiration, cleanupInterval time.Duration) *Cache[K, V] {
	return &Cache[K, V]{
		cache: gocache.New(defaultExpiration, cleanupInterval),
	}
}

func (c *Cache[K, V]) Put(key K, value V, d time.Duration) {
	c.cache.Set(string(key), value, d)
}

func (c *Cache[K, V]) Get(key K) (V, bool) {
	v, found := c.cache.Get(string(key))
	if found {
		return v.(V), true
	}
	return c.zeroValue, false
}
