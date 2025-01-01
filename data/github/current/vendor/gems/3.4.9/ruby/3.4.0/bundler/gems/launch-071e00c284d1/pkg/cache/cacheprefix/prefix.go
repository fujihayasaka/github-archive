package cacheprefix

import (
	"context"
	"time"

	"github.com/github/launch/pkg/cache"
)

type prefixcache struct {
	prefix string
	cache  cache.ExpiringCache
}

func Prefix(cache cache.ExpiringCache, prefix string) cache.ExpiringCache {
	return &prefixcache{cache: cache, prefix: prefix}
}

func (px *prefixcache) Set(ctx context.Context, key string, value []byte, now time.Time, expiresIn time.Duration) (err error) {
	return px.cache.Set(ctx, px.prefix+key, value, now, expiresIn)
}

func (px *prefixcache) Get(ctx context.Context, key string, now time.Time) (value *cache.ExpiringValue, found bool, err error) {
	return px.cache.Get(ctx, px.prefix+key, now)
}
