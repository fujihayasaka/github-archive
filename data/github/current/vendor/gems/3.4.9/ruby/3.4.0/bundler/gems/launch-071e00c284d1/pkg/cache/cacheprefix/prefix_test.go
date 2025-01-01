package cacheprefix

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/cache/cachetest"
)

const (
	KiB = 1 << 10
	MiB = 1 << 20
)

func TestWithExpiry(t *testing.T) {
	cachetest.TestWithExpiry(t, func(t *testing.T) cache.ExpiringCache {
		cache := cachemem.NewExpiringCache(10 * MiB)
		return Prefix(cache, "/hello/world/")
	})
}

func TestPrefix(t *testing.T) {
	tests := []struct {
		name  string
		check func(t *testing.T, ctx context.Context)
	}{
		{
			name: "seggregate caches with prefix",
			check: func(t *testing.T, ctx context.Context) {
				shared := cachemem.NewExpiringCache(1 * KiB)

				now := time.Now()
				wantKey := "hello"
				wantValue := []byte("world")
				wantExpiry := now.Add(time.Second)

				myCache := Prefix(shared, "antoine/")

				// using myCache, i can read my writes
				err := myCache.Set(ctx, wantKey, wantValue, now, wantExpiry.Sub(now))
				require.NoError(t, err)

				got, ok, err := myCache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.True(t, ok)
				require.Equal(t, wantValue, got.Value)
				require.Equal(t, wantExpiry, got.Expiry)

				yourCache := Prefix(shared, "you/")

				// but using your cache, you can't read my writes
				got, ok, err = yourCache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.False(t, ok)
				require.Nil(t, got)

				// and you can't overwrite stuff in my keyspace
				yourValue := []byte("le monde")
				err = yourCache.Set(ctx, wantKey, yourValue, now, wantExpiry.Sub(now))
				require.NoError(t, err)

				got, ok, err = myCache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.True(t, ok)
				require.Equal(t, wantValue, got.Value)
				require.Equal(t, wantExpiry, got.Expiry)
			},
		},
	}
	ctx := context.Background()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Helper()
			tt.check(t, ctx)
		})
	}
}
