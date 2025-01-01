package rate

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/go-redis/redismock/v9"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/observability"
	"github.com/github/launch/utils/clock"
	"github.com/github/launch/utils/testutils"
)

var (
	testRepoID    = int64(3)
	testThreshold = uint64(500)
)

func newTestKeyPrefix() string {
	return fmt.Sprintf("launch:test_limiter:%s", uuid.New().String())
}

func Test_RedisRateLimiter(t *testing.T) {
	tests := []struct {
		name               string
		threshold          uint64
		numCommandsToSend  uint64
		shouldCircuitBreak bool
		repoID             int64
		expectedAllows     uint64
		expectedRejects    uint64
		useDarkMode        bool
		override           func(int64) (uint64, bool)
	}{
		{
			name:               "allow all",
			threshold:          500,
			numCommandsToSend:  500,
			shouldCircuitBreak: false,
			repoID:             1,
			expectedAllows:     500,
		},
		{
			name:               "allow all when circuit breaker open",
			threshold:          10,
			numCommandsToSend:  500,
			shouldCircuitBreak: true,
			repoID:             1,
			expectedAllows:     500,
		},
		{
			name:               "reject beyond threshold",
			threshold:          500,
			numCommandsToSend:  501,
			shouldCircuitBreak: false,
			repoID:             1,
			expectedAllows:     500,
			expectedRejects:    1,
		},
		{
			name:               "dark mode does not affect rate limit", // dark mode is handled by the fallback rate limiter
			threshold:          2,
			numCommandsToSend:  10,
			shouldCircuitBreak: false,
			repoID:             1,
			expectedAllows:     2,
			expectedRejects:    8,
			useDarkMode:        true,
		},
		{
			name:               "reject with 0 override",
			threshold:          500,
			numCommandsToSend:  500,
			shouldCircuitBreak: false,
			repoID:             1,
			expectedAllows:     0,
			expectedRejects:    500,
			override:           func(_ int64) (uint64, bool) { return 0, true },
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()

			client, cancel, err := launchredis.CreateRedisPoolConnectionForTest(t)
			if err != nil {
				t.Errorf("Could not open connection to Redis: %v", err)
			}
			defer cancel()

			ch := make(chan bool, tc.numCommandsToSend)
			breaker := testutils.NewNoopBreaker()
			if tc.shouldCircuitBreak {
				breaker.Trip()
			}
			opts := []RedisRateLimiterOption{
				WithThreshold(tc.threshold),
				withClock(clock.NewMock(0)),
			}
			if tc.useDarkMode {
				opts = append(opts, WithDarkMode())
			}

			override := func(repoDatabaseID int64) (uint64, bool) { return 0, false }
			if tc.override != nil {
				override = tc.override
			}

			limiter := newRedisRateLimiter(observability.NewTestObservability(), client, breaker, newTestKeyPrefix(), tc.threshold, 10 /* seconds per bucket */, override, opts...)

			wg := &sync.WaitGroup{}
			wg.Add(int(tc.numCommandsToSend))
			go func(w *sync.WaitGroup) {
				for i := uint64(0); i < tc.numCommandsToSend; i++ {
					ch <- limiter.Allow(ctx, tc.repoID)
					w.Done()
				}
				close(ch)
			}(wg)
			wg.Wait()

			var commandsAllowed uint64 = 0
			var commandsRejected uint64 = 0
			for i := range ch {
				if i {
					commandsAllowed++
				} else {
					commandsRejected++
				}
			}

			if tc.numCommandsToSend != commandsAllowed+commandsRejected {
				t.Fatalf("Expected %d commands to be sent: got %d", tc.numCommandsToSend, commandsAllowed+commandsRejected)
			}
			if tc.shouldCircuitBreak && tc.numCommandsToSend != commandsAllowed {
				t.Fatalf("Expected %d commands to be sent when circuit breaker is open: got %d", tc.numCommandsToSend, commandsAllowed)
			}
			if !tc.shouldCircuitBreak && tc.expectedAllows != commandsAllowed {
				t.Fatalf("Expected %d commands to be allowed: got %v", tc.expectedAllows, commandsAllowed)
			}
			if !tc.shouldCircuitBreak && tc.expectedRejects != commandsRejected {
				t.Fatalf("Expected %d commands to be rejected: got %v", tc.expectedRejects, commandsRejected)
			}
		})
	}
}

func Test_RedisRateLimiter_MultipleGlobalIDs(t *testing.T) {
	type perGlobalIDRequests struct {
		repoID            int64
		numCommandsToSend uint64
		expectedAllows    uint64
		expectedRejects   uint64
	}
	tests := []struct {
		name               string
		threshold          uint64
		shouldCircuitBreak bool
		useDarkMode        bool
		override           func(int64) (uint64, bool)
		requests           []perGlobalIDRequests
	}{
		{
			name:               "allow all",
			threshold:          5,
			shouldCircuitBreak: false,
			override: func(repoID int64) (uint64, bool) {
				if repoID == 2 {
					return 3, true
				}
				return 0, false
			},
			requests: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 5,
					expectedAllows:    5,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 6,
					expectedAllows:    3,
					expectedRejects:   3,
				},
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()

			client, cancel, err := launchredis.CreateRedisPoolConnectionForTest(t)
			if err != nil {
				t.Errorf("Could not open connection to Redis: %v", err)
			}
			defer cancel()

			breaker := testutils.NewNoopBreaker()
			if tc.shouldCircuitBreak {
				breaker.Trip()
			}
			opts := []RedisRateLimiterOption{
				withClock(clock.NewMock(0)),
			}
			if tc.useDarkMode {
				opts = append(opts, WithDarkMode())
			}

			override := func(repoDatabaseID int64) (uint64, bool) { return 0, false }
			if tc.override != nil {
				override = tc.override
			}

			limiter := newRedisRateLimiter(observability.NewTestObservability(), client, breaker, newTestKeyPrefix(), tc.threshold, 10 /* seconds per bucket */, override, opts...)

			errCh := make(chan error, len(tc.requests))
			testWg := &sync.WaitGroup{}
			testWg.Add(len(tc.requests))

			for _, req := range tc.requests {
				go func(t *testing.T, request perGlobalIDRequests, outerWg *sync.WaitGroup) {
					defer outerWg.Done()

					ch := make(chan bool, request.numCommandsToSend)

					wg := &sync.WaitGroup{}
					wg.Add(int(request.numCommandsToSend))
					go func(w *sync.WaitGroup) {
						for i := uint64(0); i < request.numCommandsToSend; i++ {
							ch <- limiter.Allow(ctx, request.repoID)
							w.Done()
						}
						close(ch)
					}(wg)
					wg.Wait()

					var commandsAllowed uint64 = 0
					var commandsRejected uint64 = 0
					for i := range ch {
						if i {
							commandsAllowed++
						} else {
							commandsRejected++
						}
					}

					if request.numCommandsToSend != commandsAllowed+commandsRejected {
						errCh <- fmt.Errorf("Expected %d commands to be sent: got %d", request.numCommandsToSend, commandsAllowed+commandsRejected)
						return
					}
					if tc.shouldCircuitBreak && request.numCommandsToSend != commandsAllowed {
						errCh <- fmt.Errorf("Expected %d commands to be sent when circuit breaker is open: got %d", request.numCommandsToSend, commandsAllowed)
						return
					}
					if !tc.shouldCircuitBreak && request.expectedAllows != commandsAllowed {
						errCh <- fmt.Errorf("Expected %d commands to be allowed: got %v", request.expectedAllows, commandsAllowed)
						return
					}
					if !tc.shouldCircuitBreak && request.expectedRejects != commandsRejected {
						errCh <- fmt.Errorf("Expected %d commands to be rejected: got %v", request.expectedRejects, commandsRejected)
						return
					}

					errCh <- nil
				}(t, req, testWg)
			}

			testWg.Wait()
			close(errCh)
			for testErr := range errCh {
				if testErr != nil {
					t.Error(testErr)
				}
			}
		})
	}
}

func Test_RedisRateLimiter_RedisCommands(t *testing.T) {
	boom := errors.New("boom")

	cases := []struct {
		name                  string
		setup                 func(redismock.ClientMock, string)
		isAllowed             bool
		expectBreakerFailures bool
	}{
		{
			name: "success",
			setup: func(mock redismock.ClientMock, key string) {
				mock.ExpectGet(key).SetVal("0")
				mock.ExpectTxPipeline()
				mock.ExpectIncr(key).SetVal(1)
				mock.ExpectExpire(key, defaultExpirationInSec*time.Second).SetVal(true)
				mock.ExpectTxPipelineExec().SetVal(nil)
			},
			isAllowed:             true,
			expectBreakerFailures: false,
		},
		{
			name: "success on nil get",
			setup: func(mock redismock.ClientMock, key string) {
				mock.ExpectGet(key).SetErr(redis.Nil)
				mock.ExpectTxPipeline()
				mock.ExpectIncr(key).SetVal(1)
				mock.ExpectExpire(key, defaultExpirationInSec*time.Second).SetVal(true)
				mock.ExpectTxPipelineExec().SetVal(nil)
			},
			isAllowed:             true,
			expectBreakerFailures: false,
		},
		{
			name: "blocks over threshold",
			setup: func(mock redismock.ClientMock, key string) {
				mock.ExpectGet(key).SetVal(fmt.Sprintf("%d", testThreshold+1))
			},
			isAllowed:             false,
			expectBreakerFailures: false,
		},
		{
			name: "get failure",
			setup: func(mock redismock.ClientMock, key string) {
				mock.ExpectGet(key).SetErr(boom)
			},
			isAllowed:             true,
			expectBreakerFailures: true,
		},
		{
			name: "incr failure",
			setup: func(mock redismock.ClientMock, key string) {
				mock.ExpectGet(key).SetVal("0")
				mock.ExpectTxPipeline()
				mock.ExpectIncr(key).SetErr(boom)
			},
			isAllowed:             true,
			expectBreakerFailures: true,
		},
		{
			name: "exp failure",
			setup: func(mock redismock.ClientMock, key string) {
				mock.ExpectGet(key).SetVal("0")
				mock.ExpectTxPipeline()
				mock.ExpectIncr(key).SetVal(1)
				mock.ExpectExpire(key, defaultExpirationInSec*time.Second).SetErr(boom)
			},
			isAllowed:             true,
			expectBreakerFailures: true,
		},
		{
			name: "pipeline exec failure",
			setup: func(mock redismock.ClientMock, key string) {
				mock.ExpectGet(key).SetVal("0")
				mock.ExpectTxPipeline()
				mock.ExpectIncr(key).SetVal(1)
				mock.ExpectExpire(key, defaultExpirationInSec*time.Second).SetVal(true)
				mock.ExpectTxPipelineExec().SetErr(boom)
			},
			isAllowed:             true,
			expectBreakerFailures: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client, mock := redismock.NewClientMock()
			clockMock := clock.NewMock(0)

			keyPrefix := newTestKeyPrefix()
			bucket := clockMock.Now().Second() / 10
			key := fmt.Sprintf("{%s:r_%d}%d", keyPrefix, testRepoID, bucket)

			tc.setup(mock, key)

			noopBreaker := testutils.NewNoopBreaker()

			limiter := newRedisRateLimiter(
				observability.NewTestObservability(),
				client,
				noopBreaker,
				keyPrefix,
				testThreshold,
				10, /* seconds per bucket */
				func(repoDatabaseID int64) (uint64, bool) { return 0, false },
				[]RedisRateLimiterOption{
					withClock(clockMock),
				}...,
			)

			limiterAllowed := limiter.Allow(context.Background(), testRepoID)
			assert.Equal(t, tc.isAllowed, limiterAllowed, "expected limiter.Allow to return %v", tc.isAllowed)

			err := mock.ExpectationsWereMet()
			require.NoError(t, err, "redis expectations were not met: %v", err)

			if tc.expectBreakerFailures {
				assert.NotZero(t, noopBreaker.Failures())
			} else {
				assert.Zero(t, noopBreaker.Failures())
			}
		})
	}
}
