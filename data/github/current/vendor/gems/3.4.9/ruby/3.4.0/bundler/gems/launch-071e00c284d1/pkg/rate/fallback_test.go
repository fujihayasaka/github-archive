package rate

import (
	"context"
	"fmt"
	"runtime"
	"sync"
	"testing"
	"time"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/observability"
	"github.com/github/launch/utils/clock"
	"github.com/github/launch/utils/testutils"
)

func Test_FallbackRateLimiter_DarkMode(t *testing.T) {
	ctx := context.Background()

	client, cancel, err := launchredis.CreateRedisPoolConnectionForTest(t)
	if err != nil {
		t.Errorf("Could not open connection to Redis: %v", err)
	}
	defer cancel()

	breaker := testutils.NewNoopBreaker()

	opts := []RedisRateLimiterOption{
		WithDarkMode(),
		withClock(clock.NewMock(0)),
	}

	limiter := newFallbackRateLimiter(ctx, observability.NewTestObservability(), client, breaker, newTestKeyPrefix(), defaultQueueBuildBucketThreshold, defaultQueueBuildBucketWindowSize, getQueueBuildOverrides, opts...)

	if !limiter.useDarkMode {
		t.Fatalf("Expected fallthrough rate limiter to use dark mode")
	}
}

func Test_FallbackRateLimiter_DarkMode_ConfigSwitch(t *testing.T) {
	ctx := context.Background()

	client, cancel, err := launchredis.CreateRedisPoolConnectionForTest(t)
	if err != nil {
		t.Errorf("Could not open connection to Redis: %v", err)
	}
	defer cancel()

	breaker := testutils.NewNoopBreaker()

	opts := []RedisRateLimiterOption{
		withClock(clock.NewMock(0)),
	}

	testKeyPrefix := newTestKeyPrefix()

	limiter := newFallbackRateLimiter(ctx, observability.NewTestObservability(), client, breaker, testKeyPrefix, defaultQueueBuildBucketThreshold, defaultQueueBuildBucketWindowSize, getQueueBuildOverrides, opts...)

	if limiter.useDarkMode {
		t.Fatalf("Expected fallthrough rate limiter not to use dark mode initially")
	}

	client.Set(ctx, fmt.Sprintf(darkModeConfigKeyFormatter, testKeyPrefix), true, 10*time.Minute)

	limiter.checkForAndApplyConfigChanges(ctx)

	if !limiter.useDarkMode {
		t.Fatalf("Expected fallthrough rate limiter to use dark mode after changing the setting")
	}
}

func Test_FallbackRateLimiter(t *testing.T) {
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
			name:               "test multiple repos",
			threshold:          5,
			shouldCircuitBreak: false,
			requests: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 5,
					expectedAllows:    5,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 10,
					expectedAllows:    5,
					expectedRejects:   5,
				},
			},
		},
		{
			name:               "use custom overrides",
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

		{
			name:               "allow all while in dark mode",
			threshold:          5,
			shouldCircuitBreak: false,
			useDarkMode:        true,
			requests: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 500,
					expectedAllows:    500,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 40,
					expectedAllows:    40,
					expectedRejects:   0,
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

			limiter := newFallbackRateLimiter(ctx, observability.NewTestObservability(), client, breaker, newTestKeyPrefix(), defaultQueueBuildBucketThreshold, defaultQueueBuildBucketWindowSize, override, opts...)

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

func Test_FallbackRateLimiter_Failover(t *testing.T) {
	type perGlobalIDRequests struct {
		repoID            int64
		numCommandsToSend uint64
		expectedAllows    uint64
		expectedRejects   uint64
	}
	tests := []struct {
		name           string
		threshold      uint64
		requestsBefore []perGlobalIDRequests
		requestsAfter  []perGlobalIDRequests
	}{
		{
			name:      "test multiple repos",
			threshold: 10,
			requestsBefore: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 20,
					expectedAllows:    10,
					expectedRejects:   10,
				},
				{
					repoID:            2,
					numCommandsToSend: 10,
					expectedAllows:    10,
					expectedRejects:   0,
				},
			},
			requestsAfter: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 20,
					expectedAllows:    20,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 10,
					expectedAllows:    10,
					expectedRejects:   0,
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

			opts := []RedisRateLimiterOption{
				WithThreshold(tc.threshold),
				withClock(clock.NewMock(0)),
			}

			limiter := newFallbackRateLimiter(ctx, observability.NewTestObservability(), client, breaker, newTestKeyPrefix(), defaultQueueBuildBucketThreshold, defaultQueueBuildBucketWindowSize, getQueueBuildOverrides, opts...)

			errCh := make(chan error, len(tc.requestsBefore))
			testWg := &sync.WaitGroup{}
			testWg.Add(len(tc.requestsBefore))

			for _, req := range tc.requestsBefore {
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
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be sent: got %d", line, request.numCommandsToSend, commandsAllowed+commandsRejected)
						return
					}
					if request.expectedAllows != commandsAllowed {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be allowed: got %v", line, request.expectedAllows, commandsAllowed)
						return
					}
					if request.expectedRejects != commandsRejected {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d, Expected %d commands to be rejected: got %v", line, request.expectedRejects, commandsRejected)
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

			errCh = make(chan error, len(tc.requestsAfter))
			testWg.Add(len(tc.requestsAfter))

			breaker.Trip()

			for _, req := range tc.requestsAfter {
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
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be sent: got %d", line, request.numCommandsToSend, commandsAllowed+commandsRejected)
						return
					}
					if request.expectedAllows != commandsAllowed {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be allowed: got %v", line, request.expectedAllows, commandsAllowed)
						return
					}
					if request.expectedRejects != commandsRejected {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be rejected: got %v", line, request.expectedRejects, commandsRejected)
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

func Test_FallbackRateLimiter_FailoverResets(t *testing.T) {
	type perGlobalIDRequests struct {
		repoID            int64
		numCommandsToSend uint64
		expectedAllows    uint64
		expectedRejects   uint64
	}
	tests := []struct {
		name      string
		threshold uint64
		requests  []perGlobalIDRequests
	}{
		{
			name:      "test multiple repos",
			threshold: 100,
			requests: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 25,
					expectedAllows:    25,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 45,
					expectedAllows:    45,
					expectedRejects:   0,
				},
				{
					repoID:            3,
					numCommandsToSend: 101,
					expectedAllows:    100,
					expectedRejects:   1,
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

			opts := []RedisRateLimiterOption{
				WithThreshold(tc.threshold),
				withClock(clock.NewMock(0)),
			}

			limiter := newFallbackRateLimiter(ctx, observability.NewTestObservability(), client, breaker, newTestKeyPrefix(), defaultQueueBuildBucketThreshold, defaultQueueBuildBucketWindowSize, getQueueBuildOverrides, opts...)

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
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be sent: got %d", line, request.numCommandsToSend, commandsAllowed+commandsRejected)
						return
					}
					if request.expectedAllows != commandsAllowed {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be allowed: got %v", line, request.expectedAllows, commandsAllowed)
						return
					}
					if request.expectedRejects != commandsRejected {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d, Expected %d commands to be rejected: got %v", line, request.expectedRejects, commandsRejected)
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

			breaker.Trip()

			for _, req := range tc.requests {
				if _, hasAfterReset := limiter.localRateLimiter.cache.Load(req.repoID); hasAfterReset {
					t.Errorf("Expected Repository ID of %d to have its rate limiter reset", req.repoID)
				}
			}
		})
	}
}

func Test_FallbackRateLimiter_FailoverResetsBackToRedis(t *testing.T) {
	type perGlobalIDRequests struct {
		repoID            int64
		numCommandsToSend uint64
		expectedAllows    uint64
		expectedRejects   uint64
	}
	tests := []struct {
		name      string
		threshold uint64
		requests  []perGlobalIDRequests
	}{
		{
			name:      "test multiple repos",
			threshold: 100,
			requests: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 25,
					expectedAllows:    25,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 45,
					expectedAllows:    45,
					expectedRejects:   0,
				},
				{
					repoID:            3,
					numCommandsToSend: 101,
					expectedAllows:    100,
					expectedRejects:   1,
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

			opts := []RedisRateLimiterOption{
				WithThreshold(tc.threshold),
				withClock(clock.NewMock(0)),
			}

			limiter := newFallbackRateLimiter(ctx, observability.NewTestObservability(), client, breaker, newTestKeyPrefix(), defaultQueueBuildBucketThreshold, defaultQueueBuildBucketWindowSize, getQueueBuildOverrides, opts...)
			breakerCh := breaker.Subscribe()

			errCh := make(chan error, len(tc.requests))
			testWg := &sync.WaitGroup{}
			testWg.Add(len(tc.requests))

			// Trip then reset the breaker to make sure the Redis client is used after flipping.
			breaker.Trip()
			breaker.Reset()

		breakerChannelLabel:
			for {
				select {
				case event := <-breakerCh:
					if event == circuit.BreakerReset {
						time.Sleep(500 * time.Microsecond)
						break breakerChannelLabel
					}
				}
			}

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
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be sent: got %d", line, request.numCommandsToSend, commandsAllowed+commandsRejected)
						return
					}
					if request.expectedAllows != commandsAllowed {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d: Expected %d commands to be allowed: got %v", line, request.expectedAllows, commandsAllowed)
						return
					}
					if request.expectedRejects != commandsRejected {
						_, _, line, _ := runtime.Caller(0)
						errCh <- fmt.Errorf("Check line %d, Expected %d commands to be rejected: got %v", line, request.expectedRejects, commandsRejected)
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

			for _, req := range tc.requests {
				if _, hasAfterReset := limiter.localRateLimiter.cache.Load(req.repoID); hasAfterReset {
					t.Errorf("Expected Repository ID of %d to have its rate limiter reset", req.repoID)
				}
			}
		})
	}
}
