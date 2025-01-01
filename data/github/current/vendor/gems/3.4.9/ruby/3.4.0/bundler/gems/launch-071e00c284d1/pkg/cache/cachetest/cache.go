package cachetest

import (
	"bytes"
	"context"
	"fmt"
	"math/rand"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/cache"
)

type testOpts struct {
	sleepUntil          func(time.Time) time.Time
	equalWithinDuration time.Duration
}

func UseRealTime() TestOption {
	return func(opts *testOpts) {
		opts.sleepUntil = func(t time.Time) time.Time {
			return <-time.After(time.Until(t))
		}
		opts.equalWithinDuration = 100 * time.Millisecond
	}
}

type TestOption func(*testOpts)

func TestWithExpiry(t *testing.T, cacher func(t *testing.T) cache.ExpiringCache, opts ...TestOption) {
	t.Helper()

	opt := &testOpts{
		sleepUntil: func(until time.Time) time.Time {
			return until
		},
		equalWithinDuration: time.Duration(0),
	}
	for _, o := range opts {
		o(opt)
	}

	tests := []struct {
		name    string
		actions func(t *testing.T, ctx context.Context, c cache.ExpiringCache)
	}{
		{
			name: "can get what we set",
			actions: func(t *testing.T, ctx context.Context, c cache.ExpiringCache) {
				now := time.Now()
				key := "hello"
				want := []byte("world")
				expiresIn := 20 * time.Second
				wantExpiry := now.Add(expiresIn)
				err := c.Set(ctx, key, want, now, expiresIn)
				require.NoError(t, err)

				got, found, err := c.Get(ctx, key, now)
				require.NoError(t, err)
				require.True(t, found)
				require.Equal(t, want, got.Value)
				require.WithinDuration(t, wantExpiry, got.Expiry, opt.equalWithinDuration)
			},
		},
		{
			name: "entries expire",
			actions: func(t *testing.T, ctx context.Context, c cache.ExpiringCache) {
				now := time.Now()
				key := "hello"
				want := []byte("world")
				expiresIn := 200 * time.Millisecond
				wantExpiry := now.Add(expiresIn)
				err := c.Set(ctx, key, want, now, expiresIn)
				require.NoError(t, err)

				now = opt.sleepUntil(now.Add(expiresIn / 2))

				got, found, err := c.Get(ctx, key, now)
				require.NoError(t, err)
				require.True(t, found)
				require.Equal(t, want, got.Value)
				require.WithinDuration(t, wantExpiry, got.Expiry, opt.equalWithinDuration)

				now = opt.sleepUntil(now.Add(expiresIn/2 + time.Millisecond))

				got, found, err = c.Get(ctx, key, now)
				require.NoError(t, err)
				require.False(t, found)
				require.Nil(t, got)
			},
		},
		// concurrency tests: we're just trying to provoke race conditions here for the race detector
		{
			name: "basic concurrency no collision",
			actions: func(t *testing.T, ctx context.Context, c cache.ExpiringCache) {
				now := time.Now()
				concurrency := 100
				minOps := 10
				maxOps := 100

				useCache := func(id int, c cache.ExpiringCache) error {
					key := "key" + strconv.Itoa(id)
					value := []byte("value" + strconv.Itoa(id))
					expiresIn := time.Duration(id+1) * time.Second
					for i := 0; i < minOps+rand.Intn(maxOps-minOps); i++ {
						if err := c.Set(ctx, key, value, now, expiresIn); err != nil {
							return err
						}
						v, ok, err := c.Get(ctx, key, now)
						if err != nil {
							return err
						}
						if !ok {
							return fmt.Errorf("value we just `set` can't be found: goroutine %d key %v", id, key)
						}
						if !bytes.Equal(v.Value, value) {
							return fmt.Errorf("value we just `set` was `get` back but has different value")
						}
					}
					return nil
				}

				start := make(chan struct{})
				errc := make(chan error, concurrency)
				var wg sync.WaitGroup
				for i := 0; i < concurrency; i++ {
					wg.Add(1)
					go func(i int) {
						defer wg.Done()
						<-start

						errc <- useCache(i, c)
					}(i)
				}

				close(start)
				wg.Wait()
				close(errc)
				for err := range errc {
					require.NoError(t, err)
				}
			},
		},
		{
			name: "basic concurrency with collisions",
			actions: func(t *testing.T, ctx context.Context, c cache.ExpiringCache) {
				now := time.Now()
				concurrency := 100
				keyRange := 10
				minOps := 10
				maxOps := 100

				var (
					totalReads     int64
					readYourWrites int64
				)

				useCache := func(id int, c cache.ExpiringCache) error {
					value := []byte("value" + strconv.Itoa(id))
					expiresIn := time.Duration(id+1) * time.Second
					for i := 0; i < minOps+rand.Intn(maxOps-minOps); i++ {
						key := "key" + strconv.Itoa(rand.Intn(keyRange))
						if err := c.Set(ctx, key, value, now, expiresIn); err != nil {
							return err
						}
						v, ok, err := c.Get(ctx, key, now)
						if err != nil {
							return err
						}
						if !ok {
							return fmt.Errorf("value we just `set` can't be found: goroutine %d key %v", id, key)
						}
						atomic.AddInt64(&totalReads, 1)
						if bytes.Equal(v.Value, value) {
							atomic.AddInt64(&readYourWrites, 1)
						}
					}
					return nil
				}

				start := make(chan struct{})
				errc := make(chan error, concurrency)
				var wg sync.WaitGroup
				for i := 0; i < concurrency; i++ {
					wg.Add(1)
					go func(i int) {
						defer wg.Done()
						<-start

						errc <- useCache(i, c)
					}(i)
				}

				close(start)
				wg.Wait()
				close(errc)
				for err := range errc {
					require.NoError(t, err)
				}

				t.Logf("	        total reads: %d", totalReads)
				t.Logf("	read what you wrote: %d", readYourWrites)
				t.Logf("	read what you wrote: %f %%", float64(readYourWrites)/float64(totalReads)*100)
			},
		},
	}
	ctx := context.Background()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.actions(t, ctx, cacher(t))
		})
	}
}
