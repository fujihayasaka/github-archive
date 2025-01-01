package rate

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"
)

func TestInMemoryLimiter(t *testing.T) {
	ctx := context.Background()

	limiter := newInMemoryRateLimiter(ctx, defaultQueueBuildBucketThreshold/10)
	first := limiter.Allow(ctx, 1)

	if !first {
		t.Fatalf("Allow()=%v, got %v", true, first)
	}
}

func TestInMemoryLimiter_Scan(t *testing.T) {
	d := 1 * time.Second
	ctx, cancel := context.WithCancel(context.Background())
	opts := []inMemoryRateLimiterOption{
		withResetFrequency(d),
	}
	limiter := newInMemoryRateLimiter(ctx, defaultQueueBuildBucketThreshold/10, opts...)

	limiter.Allow(ctx, 1)
	limiter.Allow(ctx, 2)
	limiter.Allow(ctx, 3)
	limiter.Allow(ctx, 4)
	time.Sleep(d + 1*time.Second) // Give extra leeway to the cleanup routine to finish
	cancel()                      // Cause the cleanup function to exit so we can read the entries
	limiter.lock.RLock()
	defer limiter.lock.RUnlock()

	if _, has := limiter.cache.Load(1); has {
		t.Fatal("Expected the cache to be empty after the scan before a reset")
	}
}

func TestInMemoryLimiter_Reset(t *testing.T) {
	ctx := context.Background()
	limiter := newInMemoryRateLimiter(ctx, defaultQueueBuildBucketThreshold/10)
	var repoID int64 = 1

	limiter.Allow(ctx, repoID)
	if _, hasBeforeReset := limiter.cache.Load(repoID); !hasBeforeReset {
		t.Fatalf("Expected Repository ID of %d to have a limiter assigned in the map", repoID)
	}

	limiter.Reset()
	if _, hasAfterReset := limiter.cache.Load(repoID); hasAfterReset {
		t.Fatalf("Expected Repository ID of %d to have its rate limiter reset", repoID)
	}
}

func TestInMemoryLimiter_ResetPerformance(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping test in short mode.")
	}

	tests := []struct {
		entries int64
	}{
		{
			entries: 1000,
		},
		{
			entries: 10000,
		},
		{
			entries: 100000,
		},
		{
			entries: 1000000,
		},
	}
	for _, tc := range tests {
		t.Run(fmt.Sprintf("entries_%d", tc.entries), func(t *testing.T) {
			ctx := context.Background()
			limiter := newInMemoryRateLimiter(ctx, defaultQueueBuildBucketThreshold/10)

			beforeAdds := time.Now()
			for repoID := int64(0); repoID < tc.entries; repoID++ {
				limiter.Allow(ctx, repoID)
			}
			afterAdds := time.Now()

			t.Logf("Adding %d entries takes %v seconds\n", tc.entries, afterAdds.Sub(beforeAdds).Seconds())

			// Lock to ensure writes are done
			limiter.lock.Lock()
			for repoID := int64(0); repoID < tc.entries; repoID++ {
				if _, has := limiter.cache.Load(repoID); !has {
					t.Fatalf("Expected heap to have %d entries", tc.entries)
				}
			}
			limiter.lock.Unlock()

			beforeReset := time.Now()
			limiter.Reset()
			afterReset := time.Now()

			t.Logf("Removing %d entries takes %v seconds\n", tc.entries, afterReset.Sub(beforeReset).Seconds())

			// Lock to ensure reset is done
			limiter.lock.Lock()
			for repoID := int64(0); repoID < tc.entries; repoID++ {
				if _, has := limiter.cache.Load(repoID); has {
					t.Fatal("Expected heap to be empty")
				}
			}
			limiter.lock.Unlock()
		})
	}
}

func TestInMemoryLimiter_Limited(t *testing.T) {
	tests := []struct {
		name              string
		repoID            int64
		numCommandsToSend int
		expectedAllows    int
		expectedRejects   int
	}{
		{
			name:              "allow all",
			repoID:            1,
			numCommandsToSend: 50,
			expectedAllows:    50,
		},
		{
			name:              "reject beyond threshold",
			repoID:            1,
			numCommandsToSend: 51,
			expectedAllows:    50,
			expectedRejects:   1,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()

			limiter := newInMemoryRateLimiter(ctx, defaultQueueBuildBucketThreshold/10)

			allowed := 0
			for i := 0; i < tc.numCommandsToSend; i++ {
				isAllowed := limiter.Allow(ctx, tc.repoID)
				if isAllowed {
					allowed++
				}
			}

			if tc.expectedAllows != allowed {
				t.Fatalf("Allow()=%v allowed expected, got %v", tc.expectedAllows, allowed)
			}

			if tc.expectedRejects != tc.numCommandsToSend-allowed {
				t.Fatalf("Allow()=%v denied expected, got %v", tc.expectedRejects, tc.numCommandsToSend-allowed)
			}
		})
	}
}

func Test_InMemoryLimiter_MultipleGlobalIDs(t *testing.T) {
	type perGlobalIDRequests struct {
		repoID            int64
		numCommandsToSend uint64
		expectedAllows    uint64
		expectedRejects   uint64
	}
	tests := []struct {
		name     string
		requests []perGlobalIDRequests
	}{
		{
			name: "reject second repository",
			requests: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 50,
					expectedAllows:    50,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 55,
					expectedAllows:    50,
					expectedRejects:   5,
				},
			},
		},
		{
			name: "allow all",
			requests: []perGlobalIDRequests{
				{
					repoID:            1,
					numCommandsToSend: 50,
					expectedAllows:    50,
					expectedRejects:   0,
				},
				{
					repoID:            2,
					numCommandsToSend: 1,
					expectedAllows:    1,
					expectedRejects:   0,
				},
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()

			limiter := newInMemoryRateLimiter(ctx, defaultQueueBuildBucketThreshold/10)

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
