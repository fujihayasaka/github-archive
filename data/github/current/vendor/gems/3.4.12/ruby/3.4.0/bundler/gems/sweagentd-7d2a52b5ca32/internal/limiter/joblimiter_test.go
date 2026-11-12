package limiter

import (
	"context"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockStore is a mock implementation of the store interface for testing
type mockStore struct {
	actorJobCounts map[int64]sweagentd.JobCounts
	getError       error
}

func newMockStore() *mockStore {
	return &mockStore{
		actorJobCounts: make(map[int64]sweagentd.JobCounts),
	}
}

func (m *mockStore) GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration) (sweagentd.JobCounts, error) {
	counts := sweagentd.JobCounts{}
	if m.getError != nil {
		return counts, m.getError
	}
	counts, exists := m.actorJobCounts[actor]
	if !exists {
		return counts, nil
	}
	return counts, nil
}

func (m *mockStore) setActorJobCounts(actor int64, running, queued int) {
	m.actorJobCounts[actor] = sweagentd.JobCounts{
		Running: running,
		Queued:  queued,
	}
}

func (m *mockStore) setGetError(err error) {
	m.getError = err
}

func createTestJobLimiter() (*JobLimiter, *mockStore) {
	store := newMockStore()
	limiter := NewJobLimiter(store, 100, time.Minute)
	return limiter, store
}

func TestNewJobLimiter(t *testing.T) {
	store := newMockStore()
	limiter := NewJobLimiter(store, 50, time.Hour)

	require.NotNil(t, limiter)
	assert.Equal(t, store, limiter.store)
	assert.NotNil(t, limiter.jobs)
}

func TestDelayProcessing_NoRunningJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// No running jobs for this actor
	store.setActorJobCounts(actor, 0, 0)

	delay, shouldDelay := limiter.DelayProcessing(ctx, actor)

	assert.False(t, shouldDelay)
	assert.Equal(t, time.Duration(0), delay)
}

func TestDelayProcessing_BelowMaxJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Running jobs below the limit
	store.setActorJobCounts(actor, MaxRunningJobs-1, 0)

	delay, shouldDelay := limiter.DelayProcessing(ctx, actor)

	assert.False(t, shouldDelay)
	assert.Equal(t, time.Duration(0), delay)
}

func TestDelayProcessing_AtMaxJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Running jobs at the limit
	store.setActorJobCounts(actor, MaxRunningJobs, 0)

	delay, shouldDelay := limiter.DelayProcessing(ctx, actor)

	assert.True(t, shouldDelay)
	assert.Equal(t, JobRequeueDelay, delay)
}

func TestDelayProcessing_AboveMaxJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Running jobs above the limit
	store.setActorJobCounts(actor, MaxRunningJobs+5, 0)

	delay, shouldDelay := limiter.DelayProcessing(ctx, actor)

	assert.True(t, shouldDelay)
	assert.Equal(t, JobRequeueDelay, delay)
}

func TestDelayProcessing_StoreError(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Set an error to be returned by the store
	store.setGetError(assert.AnError)

	delay, shouldDelay := limiter.DelayProcessing(ctx, actor)

	assert.False(t, shouldDelay)
	assert.Equal(t, time.Duration(0), delay)
}

func TestDelayProcessing_CachedJobCount(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// First call - should query the store
	store.setActorJobCounts(actor, 5, 0)
	delay1, shouldDelay1 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay1)
	assert.Equal(t, time.Duration(0), delay1)

	// Second call - should use cached value (no refresh needed)
	// Change store value but it shouldn't be used due to caching
	store.setActorJobCounts(actor, MaxRunningJobs, 0)
	delay2, shouldDelay2 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay2) // Still using cached value of 5
	assert.Equal(t, time.Duration(0), delay2)
}

func TestIncrementRunningJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// First, trigger a DelayProcessing call to create a jobCount entry
	store.setActorJobCounts(actor, 5, 0)
	limiter.DelayProcessing(ctx, actor)

	// Now increment the running jobs
	limiter.IncrementRunningJobs(ctx, actor)

	// Verify the count was incremented by calling DelayProcessing again
	// Since we incremented from 5 to 6, and 6 < MaxRunningJobs, should not delay
	delay, shouldDelay := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay)
	assert.Equal(t, time.Duration(0), delay)
}

func TestIncrementRunningJobs_NoExistingEntry(t *testing.T) {
	limiter, _ := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Call increment without first calling DelayProcessing
	// This should not panic and should be a no-op
	require.NotPanics(t, func() {
		limiter.IncrementRunningJobs(ctx, actor)
	})
}

func TestDecrementRunningJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// First, trigger a DelayProcessing call to create a jobCount entry
	store.setActorJobCounts(actor, MaxRunningJobs, 0) // At the limit
	delay1, shouldDelay1 := limiter.DelayProcessing(ctx, actor)
	assert.True(t, shouldDelay1)
	assert.Equal(t, JobRequeueDelay, delay1)

	// Now decrement the running jobs
	limiter.DecrementRunningJobs(ctx, actor)

	// Update the store to reflect the decremented count
	// This simulates what would happen in reality when a job completes
	store.setActorJobCounts(actor, MaxRunningJobs-1, 0)

	// After decrementing, should be below the limit and not need delay
	delay2, shouldDelay2 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay2)
	assert.Equal(t, time.Duration(0), delay2)
}

func TestDecrementRunningJobs_NoExistingEntry(t *testing.T) {
	limiter, _ := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Call decrement without first calling DelayProcessing
	// This should not panic and should be a no-op
	require.NotPanics(t, func() {
		limiter.DecrementRunningJobs(ctx, actor)
	})
}

func TestMultipleActors(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor1 := int64(123)
	actor2 := int64(456)

	// Set different job counts for different actors
	store.setActorJobCounts(actor1, MaxRunningJobs, 0) // At limit
	store.setActorJobCounts(actor2, 5, 0)              // Below limit

	// Actor1 should be delayed
	delay1, shouldDelay1 := limiter.DelayProcessing(ctx, actor1)
	assert.True(t, shouldDelay1)
	assert.Equal(t, JobRequeueDelay, delay1)

	// Actor2 should not be delayed
	delay2, shouldDelay2 := limiter.DelayProcessing(ctx, actor2)
	assert.False(t, shouldDelay2)
	assert.Equal(t, time.Duration(0), delay2)
}

func TestJobCountRefreshLogic(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a job count that's close to the limit
	store.setActorJobCounts(actor, MaxRunningJobs-2, 0)

	// First call should not delay
	delay1, shouldDelay1 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay1)
	assert.Equal(t, time.Duration(0), delay1)

	// Increment to get closer to the limit
	limiter.IncrementRunningJobs(ctx, actor)

	// Now change the store to have more jobs (simulating other jobs starting)
	store.setActorJobCounts(actor, MaxRunningJobs+1, 0)

	// The next call should refresh from the store and delay
	delay2, shouldDelay2 := limiter.DelayProcessing(ctx, actor)
	assert.True(t, shouldDelay2)
	assert.Equal(t, JobRequeueDelay, delay2)
}

func TestIncrementDecrementWorkflow(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a job count that won't trigger refresh logic when incremented
	store.setActorJobCounts(actor, 2, 0)

	// First call should not delay
	delay1, shouldDelay1 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay1)
	assert.Equal(t, time.Duration(0), delay1)

	// Increment a few times but stay well below the refresh threshold
	for range 3 {
		limiter.IncrementRunningJobs(ctx, actor)
	}

	// At this point the cached count should be 5 (2 + 3)
	// This is safely below the refresh threshold
	delay2, shouldDelay2 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay2)
	assert.Equal(t, time.Duration(0), delay2)

	// Decrement once
	limiter.DecrementRunningJobs(ctx, actor)

	// At this point the cached count should be 4 (5 - 1)
	// Should not delay
	delay3, shouldDelay3 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay3)
	assert.Equal(t, time.Duration(0), delay3)
}

func TestIncrementToLimit(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a job count that will reach exactly MaxRunningJobs when incremented
	// We need to account for the refresh logic triggering when close to the limit
	store.setActorJobCounts(actor, MaxRunningJobs, 0)

	// First call - should delay because we're already at the limit
	delay1, shouldDelay1 := limiter.DelayProcessing(ctx, actor)
	assert.True(t, shouldDelay1)
	assert.Equal(t, JobRequeueDelay, delay1)

	// Decrement to go below the limit
	limiter.DecrementRunningJobs(ctx, actor)

	// Update store to reflect this change (in real usage, the store would be updated
	// when the job actually completes)
	store.setActorJobCounts(actor, MaxRunningJobs-1, 0)

	// Should not delay anymore since we're below the limit
	delay2, shouldDelay2 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay2)
	assert.Equal(t, time.Duration(0), delay2)
}

func TestLRUCacheExpiry(t *testing.T) {
	store := newMockStore()

	// Create a limiter with a very short TTL for testing
	limiter := NewJobLimiter(store, 100, time.Millisecond)
	ctx := context.Background()
	actor := int64(123)

	// Set up initial job count
	store.setActorJobCounts(actor, 5, 0)

	// First call should create cache entry
	delay1, shouldDelay1 := limiter.DelayProcessing(ctx, actor)
	assert.False(t, shouldDelay1)
	assert.Equal(t, time.Duration(0), delay1)

	// Verify cache entry exists
	limiter.jobsMu.Lock()
	_, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.Unlock()
	assert.True(t, exists)

	// Wait for cache to expire
	time.Sleep(2 * time.Millisecond)

	// Change the store value
	store.setActorJobCounts(actor, MaxRunningJobs, 0)

	// Next call should refresh from store due to cache expiry
	delay2, shouldDelay2 := limiter.DelayProcessing(ctx, actor)
	assert.True(t, shouldDelay2, "Should delay because cache expired and store has MaxRunningJobs")
	assert.Equal(t, JobRequeueDelay, delay2)
}

// TestDelayProcessing_ConcurrentSameActor tests that multiple goroutines
// calling DelayProcessing for the same actor work correctly with proper locking
func TestDelayProcessing_ConcurrentSameActor(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Set job count below the limit
	store.setActorJobCounts(actor, 5, 0)

	const numGoroutines = 20
	results := make([]struct {
		delay       time.Duration
		shouldDelay bool
	}, numGoroutines)

	// Use a channel to synchronize goroutine starts
	start := make(chan struct{})
	done := make(chan struct{})

	// Launch multiple goroutines that call DelayProcessing concurrently
	for i := range numGoroutines {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start
			delay, shouldDelay := limiter.DelayProcessing(ctx, actor)
			results[idx] = struct {
				delay       time.Duration
				shouldDelay bool
			}{delay, shouldDelay}
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numGoroutines {
		<-done
	}

	// All should have returned the same result (no delay since count is below limit)
	for i, result := range results {
		assert.False(t, result.shouldDelay, "Goroutine %d should not delay", i)
		assert.Equal(t, time.Duration(0), result.delay, "Goroutine %d should have zero delay", i)
	}

	// Verify that the cache was populated correctly
	limiter.jobsMu.RLock()
	jc, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()

	assert.True(t, exists, "Cache entry should exist for actor")
	assert.Equal(t, 5, jc.get(running), "Cached running count should be 5")
}

// TestDelayProcessing_ConcurrentDifferentActors tests that multiple goroutines
// calling DelayProcessing for different actors work correctly
func TestDelayProcessing_ConcurrentDifferentActors(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()

	const numActors = 10
	const goroutinesPerActor = 5

	// Set up different job counts for each actor
	actors := make([]int64, numActors)
	expectedResults := make([]bool, numActors)
	for i := range numActors {
		actors[i] = int64(100 + i)
		if i%2 == 0 {
			// Even actors are below the limit
			store.setActorJobCounts(actors[i], MaxRunningJobs-2, 0)
			expectedResults[i] = false // should not delay
		} else {
			// Odd actors are at or above the limit
			store.setActorJobCounts(actors[i], MaxRunningJobs+1, 0)
			expectedResults[i] = true // should delay
		}
	}

	results := make([][]struct {
		delay       time.Duration
		shouldDelay bool
	}, numActors)
	for i := range results {
		results[i] = make([]struct {
			delay       time.Duration
			shouldDelay bool
		}, goroutinesPerActor)
	}

	start := make(chan struct{})
	done := make(chan struct{})

	// Launch goroutines for each actor
	for actorIdx := range numActors {
		for goroutineIdx := range goroutinesPerActor {
			go func(aIdx, gIdx int) {
				defer func() {
					done <- struct{}{}
				}()
				<-start // Wait for signal to start
				delay, shouldDelay := limiter.DelayProcessing(ctx, actors[aIdx])
				results[aIdx][gIdx] = struct {
					delay       time.Duration
					shouldDelay bool
				}{delay, shouldDelay}
			}(actorIdx, goroutineIdx)
		}
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	totalGoroutines := numActors * goroutinesPerActor
	for range totalGoroutines {
		<-done
	}

	// Verify results for each actor
	for actorIdx := range numActors {
		for goroutineIdx := range goroutinesPerActor {
			result := results[actorIdx][goroutineIdx]
			assert.Equal(t, expectedResults[actorIdx], result.shouldDelay,
				"Actor %d goroutine %d delay result mismatch", actorIdx, goroutineIdx)

			if expectedResults[actorIdx] {
				assert.Equal(t, JobRequeueDelay, result.delay,
					"Actor %d goroutine %d should have requeue delay", actorIdx, goroutineIdx)
			} else {
				assert.Equal(t, time.Duration(0), result.delay,
					"Actor %d goroutine %d should have zero delay", actorIdx, goroutineIdx)
			}
		}
	}

	// Verify cache entries were created for all actors
	limiter.jobsMu.RLock()
	for actorIdx := range numActors {
		jc, exists := limiter.jobs.Get(actors[actorIdx])
		assert.True(t, exists, "Cache entry should exist for actor %d", actorIdx)
		if exists {
			expectedCount := MaxRunningJobs - 2
			if actorIdx%2 == 1 {
				expectedCount = MaxRunningJobs + 1
			}
			assert.Equal(t, expectedCount, jc.get(running),
				"Cached running count should match for actor %d", actorIdx)
		}
	}
	limiter.jobsMu.RUnlock()
}

// TestDelayProcessing_ConcurrentIncrementDecrement tests concurrent calls to
// DelayProcessing along with Increment/Decrement operations
func TestDelayProcessing_ConcurrentIncrementDecrement(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a moderate job count
	store.setActorJobCounts(actor, 5, 0)

	const numOperations = 50
	start := make(chan struct{})
	done := make(chan struct{})

	delayResults := make([]bool, numOperations)
	operationResults := make([]string, numOperations)

	// Launch goroutines that perform different operations
	for i := range numOperations {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start

			switch idx % 4 {
			case 0, 1:
				// DelayProcessing calls
				_, shouldDelay := limiter.DelayProcessing(ctx, actor)
				delayResults[idx] = shouldDelay
				operationResults[idx] = "delay"
			case 2:
				// Increment calls
				limiter.IncrementRunningJobs(ctx, actor)
				operationResults[idx] = "increment"
			case 3:
				// Decrement calls
				limiter.DecrementRunningJobs(ctx, actor)
				operationResults[idx] = "decrement"
			}
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numOperations {
		<-done
	}

	// The test is successful if it doesn't deadlock and all operations complete
	// We can't make strong assertions about the exact results since they depend
	// on timing, but we can verify basic properties

	// Count operation types
	delayCount := 0
	incrementCount := 0
	decrementCount := 0

	for i, op := range operationResults {
		switch op {
		case "delay":
			delayCount++
		case "increment":
			incrementCount++
		case "decrement":
			decrementCount++
		}

		// Ensure we got some result for delay operations
		if op == "delay" {
			// delayResults[i] can be either true or false, both are valid
			_ = delayResults[i]
		}
	}

	// Verify we had the expected distribution of operations
	// Due to timing in concurrent execution, we allow some variance
	expectedDelayCount := numOperations / 2
	expectedIncrementCount := numOperations / 4
	expectedDecrementCount := numOperations / 4

	// Allow for ±2 operations variance due to timing
	assert.InDelta(t, expectedDelayCount, delayCount, 2, "Expected delay operation count")
	assert.InDelta(t, expectedIncrementCount, incrementCount, 2, "Expected increment operation count")
	assert.InDelta(t, expectedDecrementCount, decrementCount, 2, "Expected decrement operation count")

	// Verify cache entry exists
	limiter.jobsMu.RLock()
	_, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()
	assert.True(t, exists, "Cache entry should exist after concurrent operations")
}

// TestDelayProcessing_ConcurrentStoreErrors tests concurrent DelayProcessing calls
// when the store returns errors
func TestDelayProcessing_ConcurrentStoreErrors(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Set the store to return an error
	store.setGetError(assert.AnError)

	const numGoroutines = 10
	results := make([]struct {
		delay       time.Duration
		shouldDelay bool
	}, numGoroutines)

	start := make(chan struct{})
	done := make(chan struct{})

	// Launch multiple goroutines that call DelayProcessing concurrently
	for i := range numGoroutines {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start
			delay, shouldDelay := limiter.DelayProcessing(ctx, actor)
			results[idx] = struct {
				delay       time.Duration
				shouldDelay bool
			}{delay, shouldDelay}
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numGoroutines {
		<-done
	}

	// All should have returned no delay (error case)
	for i, result := range results {
		assert.False(t, result.shouldDelay, "Goroutine %d should not delay on error", i)
		assert.Equal(t, time.Duration(0), result.delay, "Goroutine %d should have zero delay on error", i)
	}

	// Verify that no cache entry was created due to the error
	limiter.jobsMu.RLock()
	_, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()
	assert.False(t, exists, "Cache entry should not exist when store returns error")
}

// TestDelayProcessing_RaceBetweenCacheAndStore tests the race condition
// between cache operations and store fetches
func TestDelayProcessing_RaceBetweenCacheAndStore(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a job count that might trigger refresh logic
	store.setActorJobCounts(actor, MaxRunningJobs-1, 0)

	const numGoroutines = 20
	results := make([]struct {
		delay       time.Duration
		shouldDelay bool
	}, numGoroutines)

	start := make(chan struct{})
	done := make(chan struct{})

	// Launch goroutines that call DelayProcessing and then immediately increment
	for i := range numGoroutines {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start

			// Call DelayProcessing
			delay, shouldDelay := limiter.DelayProcessing(ctx, actor)
			results[idx] = struct {
				delay       time.Duration
				shouldDelay bool
			}{delay, shouldDelay}

			// Immediately increment to potentially trigger refresh logic
			limiter.IncrementRunningJobs(ctx, actor)
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numGoroutines {
		<-done
	}

	// The test is successful if it doesn't deadlock or panic
	// Results may vary due to timing, but all operations should complete

	// Verify that a cache entry exists
	limiter.jobsMu.RLock()
	jc, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()

	assert.True(t, exists, "Cache entry should exist after concurrent operations")
	if exists {
		// The running count should be >= original count due to increments
		assert.GreaterOrEqual(t, jc.get(running), MaxRunningJobs-1,
			"Running count should be at least the original count")
	}
}

// ===== Queued Jobs Tests =====

func TestQueuedJobsExceeded_NoQueuedJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// No queued jobs for this actor
	store.setActorJobCounts(actor, 0, 0)

	exceeded := limiter.QueuedJobsExceeded(ctx, actor)

	assert.False(t, exceeded)
}

func TestQueuedJobsExceeded_BelowMaxJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Queued jobs below the limit
	store.setActorJobCounts(actor, 0, MaxQueuedJobs-1)

	exceeded := limiter.QueuedJobsExceeded(ctx, actor)

	assert.False(t, exceeded)
}

func TestQueuedJobsExceeded_AtMaxJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Queued jobs at the limit
	store.setActorJobCounts(actor, 0, MaxQueuedJobs)

	exceeded := limiter.QueuedJobsExceeded(ctx, actor)

	assert.True(t, exceeded)
}

func TestQueuedJobsExceeded_AboveMaxJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Queued jobs above the limit
	store.setActorJobCounts(actor, 0, MaxQueuedJobs+5)

	exceeded := limiter.QueuedJobsExceeded(ctx, actor)

	assert.True(t, exceeded)
}

func TestQueuedJobsExceeded_StoreError(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Set an error to be returned by the store
	store.setGetError(assert.AnError)

	exceeded := limiter.QueuedJobsExceeded(ctx, actor)

	assert.False(t, exceeded)
}

func TestQueuedJobsExceeded_CachedJobCount(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// First call - should query the store
	store.setActorJobCounts(actor, 0, 5)
	exceeded1 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded1)

	// Second call - should use cached value (no refresh needed)
	// Change store value but it shouldn't be used due to caching
	store.setActorJobCounts(actor, 0, MaxQueuedJobs)
	exceeded2 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded2) // Still using cached value of 5
}

func TestIncrementQueuedJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// First, trigger a QueuedJobsExceeded call to create a jobCount entry
	store.setActorJobCounts(actor, 0, 5)
	limiter.QueuedJobsExceeded(ctx, actor)

	// Now increment the queued jobs
	limiter.IncrementQueuedJobs(ctx, actor)

	// Verify the count was incremented by calling QueuedJobsExceeded again
	// Since we incremented from 5 to 6, and 6 < MaxQueuedJobs, should not exceed
	exceeded := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded)
}

func TestIncrementQueuedJobs_NoExistingEntry(t *testing.T) {
	limiter, _ := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Call increment without first calling QueuedJobsExceeded
	// This should not panic and should be a no-op
	require.NotPanics(t, func() {
		limiter.IncrementQueuedJobs(ctx, actor)
	})
}

func TestDecrementQueuedJobs(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// First, trigger a QueuedJobsExceeded call to create a jobCount entry
	store.setActorJobCounts(actor, 0, MaxQueuedJobs) // At the limit
	exceeded1 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.True(t, exceeded1)

	// Now decrement the queued jobs
	limiter.DecrementQueuedJobs(ctx, actor)

	// Update the store to reflect the decremented count
	// This simulates what would happen in reality when a job is dequeued
	store.setActorJobCounts(actor, 0, MaxQueuedJobs-1)

	// After decrementing, should be below the limit and not exceed
	exceeded2 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded2)
}

func TestDecrementQueuedJobs_NoExistingEntry(t *testing.T) {
	limiter, _ := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Call decrement without first calling QueuedJobsExceeded
	// This should not panic and should be a no-op
	require.NotPanics(t, func() {
		limiter.DecrementQueuedJobs(ctx, actor)
	})
}

func TestQueuedJobsExceeded_MultipleActors(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor1 := int64(123)
	actor2 := int64(456)

	// Set different job counts for different actors
	store.setActorJobCounts(actor1, 0, MaxQueuedJobs) // At limit
	store.setActorJobCounts(actor2, 0, 5)             // Below limit

	// Actor1 should be exceeded
	exceeded1 := limiter.QueuedJobsExceeded(ctx, actor1)
	assert.True(t, exceeded1)

	// Actor2 should not be exceeded
	exceeded2 := limiter.QueuedJobsExceeded(ctx, actor2)
	assert.False(t, exceeded2)
}

func TestQueuedJobsIncrementDecrementWorkflow(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a job count that won't trigger refresh logic when incremented
	store.setActorJobCounts(actor, 0, 2)

	// First call should not exceed
	exceeded1 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded1)

	// Increment a few times but stay well below the limit
	for range 3 {
		limiter.IncrementQueuedJobs(ctx, actor)
	}

	// At this point the cached count should be 5 (2 + 3)
	exceeded2 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded2)

	// Decrement once
	limiter.DecrementQueuedJobs(ctx, actor)

	// At this point the cached count should be 4 (5 - 1)
	// Should not exceed
	exceeded3 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded3)
}

func TestQueuedJobsIncrementToLimit(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a job count that will reach exactly MaxQueuedJobs when incremented
	store.setActorJobCounts(actor, 0, MaxQueuedJobs)

	// First call - should exceed because we're already at the limit
	exceeded1 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.True(t, exceeded1)

	// Decrement to go below the limit
	limiter.DecrementQueuedJobs(ctx, actor)

	// Update store to reflect this change
	store.setActorJobCounts(actor, 0, MaxQueuedJobs-1)

	// Should not exceed anymore since we're below the limit
	exceeded2 := limiter.QueuedJobsExceeded(ctx, actor)
	assert.False(t, exceeded2)
}

// ===== Concurrent Queued Jobs Tests =====

func TestQueuedJobsExceeded_ConcurrentSameActor(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Set job count below the limit
	store.setActorJobCounts(actor, 0, 5)

	const numGoroutines = 20
	results := make([]bool, numGoroutines)

	// Use a channel to synchronize goroutine starts
	start := make(chan struct{})
	done := make(chan struct{})

	// Launch multiple goroutines that call QueuedJobsExceeded concurrently
	for i := range numGoroutines {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start
			exceeded := limiter.QueuedJobsExceeded(ctx, actor)
			results[idx] = exceeded
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numGoroutines {
		<-done
	}

	// All should have returned the same result (not exceeded since count is below limit)
	for i, result := range results {
		assert.False(t, result, "Goroutine %d should not exceed", i)
	}

	// Verify that the cache was populated correctly
	limiter.jobsMu.RLock()
	jc, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()

	assert.True(t, exists, "Cache entry should exist for actor")
	assert.Equal(t, 5, jc.get(queued), "Cached queued count should be 5")
}

func TestQueuedJobsExceeded_ConcurrentDifferentActors(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()

	const numActors = 10
	const goroutinesPerActor = 5

	// Set up different job counts for each actor
	actors := make([]int64, numActors)
	expectedResults := make([]bool, numActors)
	for i := range numActors {
		actors[i] = int64(100 + i)
		if i%2 == 0 {
			// Even actors are below the limit
			store.setActorJobCounts(actors[i], 0, MaxQueuedJobs-2)
			expectedResults[i] = false // should not exceed
		} else {
			// Odd actors are at or above the limit
			store.setActorJobCounts(actors[i], 0, MaxQueuedJobs+1)
			expectedResults[i] = true // should exceed
		}
	}

	results := make([][]bool, numActors)
	for i := range results {
		results[i] = make([]bool, goroutinesPerActor)
	}

	start := make(chan struct{})
	done := make(chan struct{})

	// Launch goroutines for each actor
	for actorIdx := range numActors {
		for goroutineIdx := range goroutinesPerActor {
			go func(aIdx, gIdx int) {
				defer func() {
					done <- struct{}{}
				}()
				<-start // Wait for signal to start
				exceeded := limiter.QueuedJobsExceeded(ctx, actors[aIdx])
				results[aIdx][gIdx] = exceeded
			}(actorIdx, goroutineIdx)
		}
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	totalGoroutines := numActors * goroutinesPerActor
	for range totalGoroutines {
		<-done
	}

	// Verify results for each actor
	for actorIdx := range numActors {
		for goroutineIdx := range goroutinesPerActor {
			result := results[actorIdx][goroutineIdx]
			assert.Equal(t, expectedResults[actorIdx], result,
				"Actor %d goroutine %d exceeded result mismatch", actorIdx, goroutineIdx)
		}
	}

	// Verify cache entries were created for all actors
	limiter.jobsMu.RLock()
	for actorIdx := range numActors {
		jc, exists := limiter.jobs.Get(actors[actorIdx])
		assert.True(t, exists, "Cache entry should exist for actor %d", actorIdx)
		if exists {
			expectedCount := MaxQueuedJobs - 2
			if actorIdx%2 == 1 {
				expectedCount = MaxQueuedJobs + 1
			}
			assert.Equal(t, expectedCount, jc.get(queued),
				"Cached queued count should match for actor %d", actorIdx)
		}
	}
	limiter.jobsMu.RUnlock()
}

func TestQueuedJobsExceeded_ConcurrentIncrementDecrement(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a moderate job count
	store.setActorJobCounts(actor, 0, 5)

	const numOperations = 50
	start := make(chan struct{})
	done := make(chan struct{})

	exceededResults := make([]bool, numOperations)
	operationResults := make([]string, numOperations)

	// Launch goroutines that perform different operations
	for i := range numOperations {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start

			switch idx % 4 {
			case 0, 1:
				// QueuedJobsExceeded calls
				exceeded := limiter.QueuedJobsExceeded(ctx, actor)
				exceededResults[idx] = exceeded
				operationResults[idx] = "exceeded"
			case 2:
				// Increment calls
				limiter.IncrementQueuedJobs(ctx, actor)
				operationResults[idx] = "increment"
			case 3:
				// Decrement calls
				limiter.DecrementQueuedJobs(ctx, actor)
				operationResults[idx] = "decrement"
			}
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numOperations {
		<-done
	}

	// Count operation types
	exceededCount := 0
	incrementCount := 0
	decrementCount := 0

	for i, op := range operationResults {
		switch op {
		case "exceeded":
			exceededCount++
		case "increment":
			incrementCount++
		case "decrement":
			decrementCount++
		}

		// Ensure we got some result for exceeded operations
		if op == "exceeded" {
			// exceededResults[i] can be either true or false, both are valid
			_ = exceededResults[i]
		}
	}

	// Verify we had the expected distribution of operations
	expectedExceededCount := numOperations / 2
	expectedIncrementCount := numOperations / 4
	expectedDecrementCount := numOperations / 4

	// Allow for ±2 operations variance due to timing
	assert.InDelta(t, expectedExceededCount, exceededCount, 2, "Expected exceeded operation count")
	assert.InDelta(t, expectedIncrementCount, incrementCount, 2, "Expected increment operation count")
	assert.InDelta(t, expectedDecrementCount, decrementCount, 2, "Expected decrement operation count")

	// Verify cache entry exists
	limiter.jobsMu.RLock()
	_, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()
	assert.True(t, exists, "Cache entry should exist after concurrent operations")
}

func TestQueuedJobsExceeded_ConcurrentStoreErrors(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Set the store to return an error
	store.setGetError(assert.AnError)

	const numGoroutines = 10
	results := make([]bool, numGoroutines)

	start := make(chan struct{})
	done := make(chan struct{})

	// Launch multiple goroutines that call QueuedJobsExceeded concurrently
	for i := range numGoroutines {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start
			exceeded := limiter.QueuedJobsExceeded(ctx, actor)
			results[idx] = exceeded
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numGoroutines {
		<-done
	}

	// All should have returned false (error case - fail open)
	for i, result := range results {
		assert.False(t, result, "Goroutine %d should not exceed on error", i)
	}

	// Verify that no cache entry was created due to the error
	limiter.jobsMu.RLock()
	_, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()
	assert.False(t, exists, "Cache entry should not exist when store returns error")
}

func TestQueuedJobsExceeded_RaceBetweenCacheAndStore(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with a job count that might trigger refresh logic
	store.setActorJobCounts(actor, 0, MaxQueuedJobs-1)

	const numGoroutines = 20
	results := make([]bool, numGoroutines)

	start := make(chan struct{})
	done := make(chan struct{})

	// Launch goroutines that call QueuedJobsExceeded and then immediately increment
	for i := range numGoroutines {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start

			// Call QueuedJobsExceeded
			exceeded := limiter.QueuedJobsExceeded(ctx, actor)
			results[idx] = exceeded

			// Immediately increment to potentially trigger refresh logic
			limiter.IncrementQueuedJobs(ctx, actor)
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numGoroutines {
		<-done
	}

	// The test is successful if it doesn't deadlock or panic
	// Results may vary due to timing, but all operations should complete

	// Verify that a cache entry exists
	limiter.jobsMu.RLock()
	jc, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()

	assert.True(t, exists, "Cache entry should exist after concurrent operations")
	if exists {
		// The queued count should be >= original count due to increments
		assert.GreaterOrEqual(t, jc.get(queued), MaxQueuedJobs-1,
			"Queued count should be at least the original count")
	}
}

// ===== Mixed Running and Queued Jobs Tests =====

func TestMixed_ConcurrentRunningAndQueuedOperations(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with moderate counts for both running and queued jobs
	store.setActorJobCounts(actor, 5, 10)

	const numOperations = 60
	start := make(chan struct{})
	done := make(chan struct{})

	operationResults := make([]string, numOperations)

	// Launch goroutines that perform mixed operations
	for i := range numOperations {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start

			switch idx % 6 {
			case 0:
				// DelayProcessing calls
				limiter.DelayProcessing(ctx, actor)
				operationResults[idx] = "delay"
			case 1:
				// QueuedJobsExceeded calls
				limiter.QueuedJobsExceeded(ctx, actor)
				operationResults[idx] = "exceeded"
			case 2:
				// IncrementRunningJobs calls
				limiter.IncrementRunningJobs(ctx, actor)
				operationResults[idx] = "inc_running"
			case 3:
				// DecrementRunningJobs calls
				limiter.DecrementRunningJobs(ctx, actor)
				operationResults[idx] = "dec_running"
			case 4:
				// IncrementQueuedJobs calls
				limiter.IncrementQueuedJobs(ctx, actor)
				operationResults[idx] = "inc_queued"
			case 5:
				// DecrementQueuedJobs calls
				limiter.DecrementQueuedJobs(ctx, actor)
				operationResults[idx] = "dec_queued"
			}
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numOperations {
		<-done
	}

	// Count operation types
	delayCount := 0
	exceededCount := 0
	incRunningCount := 0
	decRunningCount := 0
	incQueuedCount := 0
	decQueuedCount := 0

	for _, op := range operationResults {
		switch op {
		case "delay":
			delayCount++
		case "exceeded":
			exceededCount++
		case "inc_running":
			incRunningCount++
		case "dec_running":
			decRunningCount++
		case "inc_queued":
			incQueuedCount++
		case "dec_queued":
			decQueuedCount++
		}
	}

	// Verify we had the expected distribution of operations
	expectedPerOperation := numOperations / 6

	// Allow for ±2 operations variance due to timing
	assert.InDelta(t, expectedPerOperation, delayCount, 2, "Expected delay operation count")
	assert.InDelta(t, expectedPerOperation, exceededCount, 2, "Expected exceeded operation count")
	assert.InDelta(t, expectedPerOperation, incRunningCount, 2, "Expected inc_running operation count")
	assert.InDelta(t, expectedPerOperation, decRunningCount, 2, "Expected dec_running operation count")
	assert.InDelta(t, expectedPerOperation, incQueuedCount, 2, "Expected inc_queued operation count")
	assert.InDelta(t, expectedPerOperation, decQueuedCount, 2, "Expected dec_queued operation count")

	// Verify cache entry exists
	limiter.jobsMu.RLock()
	jc, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()
	assert.True(t, exists, "Cache entry should exist after concurrent operations")

	// Verify both running and queued counts are tracked
	if exists {
		assert.NotNil(t, jc, "Job count should not be nil")
		// The actual values may vary due to concurrent modifications, just verify they're reasonable
		running := jc.get(running)
		queued := jc.get(queued)
		assert.GreaterOrEqual(t, running, 0, "Running count should be non-negative")
		assert.GreaterOrEqual(t, queued, 0, "Queued count should be non-negative")
	}
}

func TestMixed_MultipleActorsConcurrentMixedOperations(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()

	const numActors = 5
	const goroutinesPerActor = 12

	// Set up different job counts for different actors
	actors := make([]int64, numActors)
	for i := range numActors {
		actors[i] = int64(200 + i)
		// Each actor starts with different counts
		store.setActorJobCounts(actors[i], i*2, i*3)
	}

	start := make(chan struct{})
	done := make(chan struct{})

	// Launch goroutines for each actor performing mixed operations
	for actorIdx := range numActors {
		for goroutineIdx := range goroutinesPerActor {
			go func(aIdx, gIdx int) {
				defer func() {
					done <- struct{}{}
				}()
				<-start // Wait for signal to start

				// Each goroutine performs a different operation based on its index
				switch gIdx % 6 {
				case 0:
					limiter.DelayProcessing(ctx, actors[aIdx])
				case 1:
					limiter.QueuedJobsExceeded(ctx, actors[aIdx])
				case 2:
					limiter.IncrementRunningJobs(ctx, actors[aIdx])
				case 3:
					limiter.DecrementRunningJobs(ctx, actors[aIdx])
				case 4:
					limiter.IncrementQueuedJobs(ctx, actors[aIdx])
				case 5:
					limiter.DecrementQueuedJobs(ctx, actors[aIdx])
				}
			}(actorIdx, goroutineIdx)
		}
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	totalGoroutines := numActors * goroutinesPerActor
	for range totalGoroutines {
		<-done
	}

	// Verify cache entries were created for all actors
	limiter.jobsMu.RLock()
	for actorIdx := range numActors {
		jc, exists := limiter.jobs.Get(actors[actorIdx])
		assert.True(t, exists, "Cache entry should exist for actor %d", actorIdx)
		if exists {
			// Verify both running and queued counts exist and are reasonable
			running := jc.get(running)
			queued := jc.get(queued)
			assert.GreaterOrEqual(t, running, 0, "Running count should be non-negative for actor %d", actorIdx)
			assert.GreaterOrEqual(t, queued, 0, "Queued count should be non-negative for actor %d", actorIdx)
		}
	}
	limiter.jobsMu.RUnlock()
}

func TestMixed_ConcurrentRefreshScenario(t *testing.T) {
	limiter, store := createTestJobLimiter()
	ctx := context.Background()
	actor := int64(123)

	// Start with counts that might trigger refresh logic for both running and queued
	store.setActorJobCounts(actor, MaxRunningJobs-2, MaxQueuedJobs-2)

	const numGoroutines = 30
	start := make(chan struct{})
	done := make(chan struct{})

	// Launch goroutines that perform mixed operations
	for i := range numGoroutines {
		go func(idx int) {
			defer func() {
				done <- struct{}{}
			}()
			<-start // Wait for signal to start

			// Perform operations that might trigger refresh
			switch idx % 3 {
			case 0:
				limiter.DelayProcessing(ctx, actor)
				limiter.IncrementRunningJobs(ctx, actor)
			case 1:
				limiter.QueuedJobsExceeded(ctx, actor)
				limiter.IncrementQueuedJobs(ctx, actor)
			default:
				// Mix of both
				limiter.DelayProcessing(ctx, actor)
				limiter.QueuedJobsExceeded(ctx, actor)
				limiter.IncrementRunningJobs(ctx, actor)
				limiter.IncrementQueuedJobs(ctx, actor)
			}
		}(i)
	}

	// Start all goroutines at once
	close(start)

	// Wait for all goroutines to complete
	for range numGoroutines {
		<-done
	}

	// The test is successful if it doesn't deadlock or panic
	// Verify that a cache entry exists
	limiter.jobsMu.RLock()
	jc, exists := limiter.jobs.Get(actor)
	limiter.jobsMu.RUnlock()

	assert.True(t, exists, "Cache entry should exist after concurrent operations")
	if exists {
		// Both counts should have increased due to increments
		running := jc.get(running)
		queued := jc.get(queued)
		assert.GreaterOrEqual(t, running, MaxRunningJobs-2,
			"Running count should be at least the original count")
		assert.GreaterOrEqual(t, queued, MaxQueuedJobs-2,
			"Queued count should be at least the original count")
	}
}
