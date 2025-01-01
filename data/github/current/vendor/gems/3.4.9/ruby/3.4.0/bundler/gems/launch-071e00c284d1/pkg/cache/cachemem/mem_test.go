package cachemem

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachetest"
)

func TestWithExpiry(t *testing.T) {
	cachetest.TestWithExpiry(t, func(t *testing.T) cache.ExpiringCache {
		return NewExpiringCache(1 << 30)
	})
}

func TestEviction(t *testing.T) {
	tests := []struct {
		name      string
		cacheSize int
		actions   func(t *testing.T, ctx context.Context, c *expiringCache)
	}{
		{
			name:      "value too big for cache",
			cacheSize: 8,
			actions: func(t *testing.T, ctx context.Context, c *expiringCache) {
				now := time.Now()
				key := "hello"
				want := []byte("world")
				expiresIn := time.Second
				err := c.Set(ctx, key, want, now, expiresIn)
				require.Equal(t, ErrValueToBigForCache, err)

			},
		},
		{
			name:      "evict first value",
			cacheSize: 12,
			actions: func(t *testing.T, ctx context.Context, c *expiringCache) {
				now := time.Now()
				key1 := "hello1"
				err := c.Set(ctx, key1, []byte("world"), now, time.Second)
				require.NoError(t, err)

				key2 := "hello2"
				err = c.Set(ctx, key2, []byte("world1"), now, time.Second)
				require.NoError(t, err)

				v, ok, err := c.Get(ctx, key1, now)
				require.NoError(t, err)
				require.False(t, ok, "key 1 isn't expired but should have been evicted")
				require.Nil(t, v)
			},
		},
		{
			name:      "evict expired value first",
			cacheSize: 25,
			actions: func(t *testing.T, ctx context.Context, c *expiringCache) {
				now := time.Now()
				key1 := "hello1"
				want1 := []byte("world1")
				expires1 := 10 * time.Second
				err := c.Set(ctx, key1, want1, now, expires1)
				require.NoError(t, err)

				key2 := "hello2"
				want2 := []byte("world2")
				err = c.Set(ctx, key2, want2, now, time.Second)
				require.NoError(t, err)

				key3 := "hello3"
				want3 := []byte("world3")
				now3 := now.Add(2 * time.Second)
				expires3 := time.Second
				err = c.Set(ctx, key3, want3, now3, expires3)
				require.NoError(t, err)

				v, ok, err := c.Get(ctx, key1, now)
				require.NoError(t, err)
				require.True(t, ok, "key 1 isn't expired so shouldn't have been evicted")
				require.Equal(t, want1, v.Value)
				require.Equal(t, now.Add(expires1), v.Expiry)

				v, ok, err = c.Get(ctx, key2, now)
				require.NoError(t, err)
				require.False(t, ok, "key 2 *is* expired so *should* have been evicted")
				require.Nil(t, v)

				v, ok, err = c.Get(ctx, key3, now)
				require.NoError(t, err)
				require.True(t, ok, "key 3 isn't expired so shouldn't have been evicted")
				require.Equal(t, want3, v.Value)
				require.Equal(t, now3.Add(expires3), v.Expiry)
			},
		},
		{
			name:      "evict expired values first, then in order of soonest",
			cacheSize: 25,
			actions: func(t *testing.T, ctx context.Context, c *expiringCache) {
				now := time.Now()
				key1 := "hello1"
				want1 := []byte("world1")
				err := c.Set(ctx, key1, want1, now, 10*time.Second)
				require.NoError(t, err)

				key2 := "hello2"
				want2 := []byte("world2")
				err = c.Set(ctx, key2, want2, now, time.Second)
				require.NoError(t, err)

				key3 := "hello3"
				want3 := []byte("world is kinda big")
				now3 := now.Add(9 * time.Second)
				expiry3 := 2 * time.Second
				err = c.Set(ctx, key3, want3, now3, expiry3)
				require.NoError(t, err)

				v, ok, err := c.Get(ctx, key1, now)
				require.NoError(t, err)
				require.False(t, ok, "key 1 isn't expired but cache was too full so so it should have been evicted")
				require.Empty(t, v)

				v, ok, err = c.Get(ctx, key2, now)
				require.NoError(t, err)
				require.False(t, ok, "key 2 *is* expired so was have been evicted")
				require.Empty(t, v)

				v, ok, err = c.Get(ctx, key3, now)
				require.NoError(t, err)
				require.True(t, ok, "key 3 isn't expired so shouldn't have been evicted")
				require.Equal(t, want3, v.Value)
				require.Equal(t, now3.Add(expiry3), v.Expiry)
			},
		},
		{
			name:      "evicts expired values as we fill the cache",
			cacheSize: 100,
			actions: func(t *testing.T, ctx context.Context, c *expiringCache) {
				now := time.Now()
				key1 := "hello1"
				want1 := []byte("world1")
				err := c.Set(ctx, key1, want1, now, 10*time.Second)
				require.NoError(t, err)

				// check content
				require.Contains(t, c.cache, key1)

				key2 := "hello2"
				want2 := []byte("world2")
				err = c.Set(ctx, key2, want2, now, time.Second)
				require.NoError(t, err)

				// check content
				require.Contains(t, c.cache, key1)
				require.Contains(t, c.cache, key2)

				key3 := "hello3"
				want3 := []byte("world3")
				now3 := now.Add(9 * time.Second) // advance time past key2's eviction
				expiry3 := 2 * time.Second
				err = c.Set(ctx, key3, want3, now3, expiry3) // should cause key2's eviction
				require.NoError(t, err)

				// check content
				require.Contains(t, c.cache, key1)
				require.NotContains(t, c.cache, key2) // evicted
				require.Contains(t, c.cache, key3)
			},
		},
	}
	ctx := context.Background()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Helper()
			tt.actions(t, ctx, newCacheWithExpiry(tt.cacheSize))
		})
	}
}
