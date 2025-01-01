package cachethru

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
		local := cachemem.NewExpiringCache(1 * KiB)   // small local cache
		remote := cachemem.NewExpiringCache(10 * MiB) // larger remote cache
		return WriteThru(local, remote)
	})
}

func TestWriteThru(t *testing.T) {
	tests := []struct {
		name  string
		check func(t *testing.T, ctx context.Context)
	}{
		{
			name: "fills back local from remote",
			check: func(t *testing.T, ctx context.Context) {
				local := cachemem.NewExpiringCache(1 * KiB)
				remote := cachemem.NewExpiringCache(1 * KiB)

				now := time.Now()
				wantKey := "hello"
				wantValue := []byte("world")
				wantExpiry := now.Add(time.Second)

				err := remote.Set(ctx, wantKey, wantValue, now, wantExpiry.Sub(now))
				require.NoError(t, err)

				cache := WriteThru(local, remote)

				// at first the local cache doesn't have a copy
				got, ok, err := local.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.False(t, ok)
				require.Nil(t, got)

				// using the write thru cache, we should get the value
				// from the remote cache
				got, ok, err = cache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.True(t, ok)
				require.Equal(t, wantValue, got.Value)
				require.Equal(t, wantExpiry, got.Expiry)

				// and that should have filled back the local cache
				got, ok, err = local.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.True(t, ok)
				require.Equal(t, wantValue, got.Value)
				require.Equal(t, wantExpiry, got.Expiry)
			},
		},
		{
			name: "writes to both local and remote",
			check: func(t *testing.T, ctx context.Context) {
				local := cachemem.NewExpiringCache(1 * KiB)
				remote := cachemem.NewExpiringCache(1 * KiB)
				cache := WriteThru(local, remote)

				now := time.Now()
				wantKey := "hello"
				wantValue := []byte("world")
				wantExpiry := now.Add(time.Second)

				// write-thru
				err := cache.Set(ctx, wantKey, wantValue, now, wantExpiry.Sub(now))
				require.NoError(t, err)

				// both caches should get filled

				got, ok, err := local.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.True(t, ok)
				require.Equal(t, wantValue, got.Value)
				require.Equal(t, wantExpiry, got.Expiry)

				got, ok, err = remote.Get(ctx, wantKey, now)
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
