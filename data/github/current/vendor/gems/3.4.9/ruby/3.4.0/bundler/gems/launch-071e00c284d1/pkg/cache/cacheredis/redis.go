package cacheredis

import (
	"context"
	"time"

	"github.com/pkg/errors"
	"github.com/redis/go-redis/v9"

	"github.com/github/launch/pkg/cache"
)

var _ cache.ExpiringCache = (*expiringCache)(nil)

type expiringCache struct {
	client redis.UniversalClient
}

func NewExpiringCache(client redis.UniversalClient) cache.ExpiringCache {
	return &expiringCache{
		client: client,
	}
}

func (c *expiringCache) Set(ctx context.Context, key string, value []byte, _ time.Time, expiresIn time.Duration) (err error) {
	resp := c.client.Set(ctx, key, value, expiresIn)
	if resp.Err() != nil {
		return errors.Wrap(err, "executing SET with PX expiry on redis")
	}
	return nil
}

func (c *expiringCache) Get(ctx context.Context, key string, now time.Time) (value *cache.ExpiringValue, found bool, err error) {
	pipeline := c.client.Pipeline()
	get := pipeline.Get(ctx, key)
	ttl := pipeline.PTTL(ctx, key)

	if _, err := pipeline.Exec(ctx); err != nil {
		// Get call may fail before PTTL.
		if err == redis.Nil {
			return nil, false, nil
		}
		return nil, false, err
	}

	// Should be caught by Exec error checking but extra check can't hurt
	if get.Err() == redis.Nil {
		return nil, false, nil
	}
	b, err := get.Bytes()
	if err != nil {
		return nil, false, err
	}

	if ttl.Err() != nil {
		return nil, false, err
	}
	// Command returns -2 if key not found, -1 if the key exists but has no associated expire
	if ttl.Val() < 0*time.Millisecond {
		return nil, false, err
	}

	value = &cache.ExpiringValue{
		Value:  b,
		Expiry: now.Add(ttl.Val()),
	}

	return value, true, nil
}
