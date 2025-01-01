package cachebreaker

import (
	"context"
	"errors"
	"testing"
	"time"

	circuit "github.com/rubyist/circuitbreaker"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachemem"
	"github.com/github/launch/pkg/cache/cachemock"
	"github.com/github/launch/pkg/cache/cachetest"
	"github.com/github/launch/utils/testutils"
)

const (
	KiB = 1 << 10
	MiB = 1 << 20
)

func TestWithExpiry(t *testing.T) {
	cachetest.TestWithExpiry(t, func(t *testing.T) cache.ExpiringCache {
		backend := cachemem.NewExpiringCache(10 * MiB)
		breaker := testutils.NewNoopBreaker()
		return CircuitBreaker(backend, breaker)
	})
}

func TestWithExpiryTimeout(t *testing.T) {
	cachetest.TestWithExpiry(t, func(t *testing.T) cache.ExpiringCache {
		backend := cachemem.NewExpiringCache(10 * MiB)
		breaker := testutils.NewNoopBreaker()
		return CircuitBreaker(backend, breaker, WithTimeouts(time.Second, time.Second))
	})
}

func TestCircuitBreaks(t *testing.T) {
	tests := []struct {
		name  string
		check func(t *testing.T, ctx context.Context)
	}{
		{
			name: "breaks opens up after too many errors",
			check: func(t *testing.T, ctx context.Context) {
				consecutiveErrors := 10
				backend := cachemock.NewExpiringCache(t)
				breaker := circuit.NewConsecutiveBreaker(int64(consecutiveErrors))

				cache := CircuitBreaker(backend, breaker)

				now := time.Now()
				wantKey := "hello"
				wantValue := []byte("world")
				expiresIn := time.Second

				backend.EXPECT().Get(ctx, wantKey, now).Return(nil, false, nil).Once()

				got, ok, err := cache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.False(t, ok)
				require.Nil(t, got)

				wantErr := errors.New("blow up")
				backend.EXPECT().Get(ctx, wantKey, now).Return(nil, false, wantErr).Times(consecutiveErrors)
				for i := 0; i < consecutiveErrors; i++ {
					got, ok, err = cache.Get(ctx, wantKey, now)
					require.Equal(t, wantErr, err)
					require.False(t, ok)
					require.Nil(t, got)
					if i < consecutiveErrors-1 {
						require.False(t, breaker.Tripped())
					}
				}
				require.True(t, breaker.Tripped())

				// circuit breaker should have opened and returned a non-error,
				// without hitting the backend (hence we don't provide a mocked call)
				got, ok, err = cache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.False(t, ok)
				require.Nil(t, got)
				require.True(t, breaker.Tripped())

				// the breakage should translate to `Set` as well
				err = cache.Set(ctx, wantKey, wantValue, now, expiresIn)
				require.NoError(t, err)
				require.True(t, breaker.Tripped())
			},
		},
		{
			name: "breaks recovers - get",
			check: func(t *testing.T, ctx context.Context) {
				consecutiveErrors := 10
				backend := cachemock.NewExpiringCache(t)
				breaker := circuit.NewConsecutiveBreaker(int64(consecutiveErrors))

				cache := CircuitBreaker(backend, breaker)

				now := time.Now()
				wantKey := "hello"

				// force the breaker to trip
				breaker.Trip()

				got, ok, err := cache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.False(t, ok)
				require.Nil(t, got)
				require.True(t, breaker.Tripped())

				// reset it
				breaker.Reset()

				// the breaker should let the call go thru and hit the backend
				backend.EXPECT().Get(ctx, wantKey, now).Return(nil, false, nil).Once()

				got, ok, err = cache.Get(ctx, wantKey, now)
				require.NoError(t, err)
				require.False(t, ok)
				require.Nil(t, got)
				require.False(t, breaker.Tripped())
			},
		},
		{
			name: "breaks recovers - set",
			check: func(t *testing.T, ctx context.Context) {
				consecutiveErrors := 10
				backend := cachemock.NewExpiringCache(t)
				breaker := circuit.NewConsecutiveBreaker(int64(consecutiveErrors))

				cache := CircuitBreaker(backend, breaker)

				now := time.Now()
				wantKey := "hello"
				wantValue := []byte("world")
				expiresIn := time.Second

				// force the breaker to trip
				breaker.Trip()

				err := cache.Set(ctx, wantKey, wantValue, now, expiresIn)
				require.NoError(t, err)
				require.True(t, breaker.Tripped())

				// reset it
				breaker.Reset()

				// the breaker should let the call go thru and hit the backend
				backend.EXPECT().Set(ctx, wantKey, wantValue, now, expiresIn).Return(nil).Once()

				err = cache.Set(ctx, wantKey, wantValue, now, expiresIn)
				require.NoError(t, err)
				require.False(t, breaker.Tripped())
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
