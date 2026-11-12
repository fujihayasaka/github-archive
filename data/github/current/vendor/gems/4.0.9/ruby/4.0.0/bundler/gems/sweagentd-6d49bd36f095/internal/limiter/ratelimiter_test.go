package limiter

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockClient implements the client interface for testing
type mockClient struct {
	rateLimits map[string]map[uint8]Rate // [ownerID:repoID]map[category]Rate
	err        error
}

func (m *mockClient) RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]Rate, error) {
	if m.err != nil {
		return nil, m.err
	}

	key := formatOwnerRepo(ownerID, repoID)
	if limits, ok := m.rateLimits[key]; ok {
		return limits, nil
	}

	// Return empty map if no limits set
	return make(map[uint8]Rate), nil
}

// mockClientWithCounter is a mock client that counts the number of times RateLimitsForRepo is called
type mockClientWithCounter struct {
	rateLimits map[string]map[uint8]Rate // [ownerID:repoID]map[category]Rate
	err        error
	callCount  *int
}

func (m *mockClientWithCounter) RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]Rate, error) {
	if m.callCount != nil {
		*m.callCount++
	}

	if m.err != nil {
		return nil, m.err
	}

	key := formatOwnerRepo(ownerID, repoID)
	if limits, ok := m.rateLimits[key]; ok {
		return limits, nil
	}

	// Return empty map if no limits set
	return make(map[uint8]Rate), nil
}

func formatOwnerRepo(ownerID, repoID int64) string {
	return string(rune(ownerID)) + ":" + string(rune(repoID))
}

func TestWaitToReceive(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

	t.Run("no secondary rate limit", func(t *testing.T) {
		duration, limited := limiter.WaitToReceive(context.Background(), 0)
		assert.False(t, limited, "expected not limited")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration")
	})

	t.Run("secondary rate limit in the future", func(t *testing.T) {
		resetTime := time.Now().Add(5 * time.Minute)
		limiter.SetSecondaryRateLimitReset(context.Background(), 0, resetTime)

		duration, limited := limiter.WaitToReceive(context.Background(), 0)
		assert.True(t, limited, "expected limited")
		assert.Positive(t, duration, "expected positive duration")
		// Should be approximately 5 minutes (allowing for small timing differences)
		assert.GreaterOrEqual(t, duration, 4*time.Minute, "expected duration >= 4 minutes")
		assert.LessOrEqual(t, duration, 6*time.Minute, "expected duration <= 6 minutes")
	})

	t.Run("secondary rate limit in the past", func(t *testing.T) {
		resetTime := time.Now().Add(-5 * time.Minute)
		limiter.SetSecondaryRateLimitReset(context.Background(), 0, resetTime)

		duration, limited := limiter.WaitToReceive(context.Background(), 0)
		assert.False(t, limited, "expected not limited")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration")
	})
}

func TestSetSecondaryRateLimitReset(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))
	resetTime := time.Now().Add(time.Hour)

	limiter.SetSecondaryRateLimitReset(context.Background(), 0, resetTime)

	// Verify it was set by checking WaitToReceive
	duration, limited := limiter.WaitToReceive(context.Background(), 0)
	assert.True(t, limited, "expected limited after setting reset time")
	assert.Positive(t, duration, "expected positive duration after setting reset time")
}

func TestDelayProcessing(t *testing.T) {
	ctx := context.Background()

	t.Run("no rate limits", func(t *testing.T) {
		client := &mockClient{
			rateLimits: make(map[string]map[uint8]Rate),
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1, 2)
		assert.False(t, delayed, "expected not delayed")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration")
	})

	t.Run("rate limit not exceeded", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.False(t, delayed, "expected not delayed")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration")
	})

	t.Run("rate limit exceeded", func(t *testing.T) {
		resetTime := time.Now().Add(time.Hour)
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 0, Used: 100, Reset: resetTime},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed, "expected delayed")
		assert.Greater(t, duration, time.Second, "expected duration > 1 second (includes buffer)")
	})

	t.Run("multiple categories, one exceeded", func(t *testing.T) {
		resetTime := time.Now().Add(30 * time.Minute)
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
					2: {Limit: 100, Remaining: 0, Used: 100, Reset: resetTime},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1, 2)
		assert.True(t, delayed, "expected delayed")
		// Should be delayed by the second category's reset time
		assert.GreaterOrEqual(t, duration, 29*time.Minute, "expected duration >= 29 minutes")
		assert.LessOrEqual(t, duration, 31*time.Minute, "expected duration <= 31 minutes")
	})

	t.Run("client error", func(t *testing.T) {
		client := &mockClient{
			err: errors.New("client error"),
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.False(t, delayed, "expected not delayed on client error")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration on client error")
	})

	t.Run("secondary rate limit takes precedence over no primary limit", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		// Set secondary rate limit
		secondaryResetTime := time.Now().Add(15 * time.Minute)
		limiter.SetSecondaryRateLimitReset(ctx, 0, secondaryResetTime)

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed, "expected delayed due to secondary rate limit")
		assert.GreaterOrEqual(t, duration, 14*time.Minute, "expected duration >= 14 minutes")
		assert.LessOrEqual(t, duration, 16*time.Minute, "expected duration <= 16 minutes")
	})

	t.Run("secondary rate limit takes precedence over primary limit", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 0, Used: 100, Reset: time.Now().Add(5 * time.Minute)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		// Set secondary rate limit with longer duration
		secondaryResetTime := time.Now().Add(20 * time.Minute)
		limiter.SetSecondaryRateLimitReset(ctx, 0, secondaryResetTime)

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed, "expected delayed")
		// Should return secondary rate limit duration (20 min), not primary (5 min)
		assert.GreaterOrEqual(t, duration, 19*time.Minute, "expected duration >= 19 minutes (secondary)")
		assert.LessOrEqual(t, duration, 21*time.Minute, "expected duration <= 21 minutes (secondary)")
	})

	t.Run("expired secondary rate limit allows primary limit check", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 0, Used: 100, Reset: time.Now().Add(10 * time.Minute)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		// Set secondary rate limit that has already expired
		secondaryResetTime := time.Now().Add(-5 * time.Minute)
		limiter.SetSecondaryRateLimitReset(ctx, 0, secondaryResetTime)

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed, "expected delayed due to primary rate limit")
		// Should return primary rate limit duration (10 min), secondary is expired
		assert.GreaterOrEqual(t, duration, 9*time.Minute, "expected duration >= 9 minutes (primary)")
		assert.LessOrEqual(t, duration, 11*time.Minute, "expected duration <= 11 minutes (primary)")
	})

	t.Run("secondary rate limit checked before client call", func(t *testing.T) {
		callCount := 0
		client := &mockClientWithCounter{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
			callCount: &callCount,
		}

		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		// Set secondary rate limit
		secondaryResetTime := time.Now().Add(10 * time.Minute)
		limiter.SetSecondaryRateLimitReset(ctx, 0, secondaryResetTime)

		duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed, "expected delayed due to secondary rate limit")
		assert.GreaterOrEqual(t, duration, 9*time.Minute, "expected duration >= 9 minutes")

		// Client should not have been called because secondary rate limit was hit first
		assert.Equal(t, 0, callCount, "expected client not to be called when secondary rate limit is active")
	})
}

func TestGetRate(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
	category := uint8(1)

	t.Run("rate not found", func(t *testing.T) {
		rate, found := limiter.GetRate(context.Background(), target, category)
		assert.False(t, found, "expected not found")
		assert.Nil(t, rate, "expected nil rate")
	})

	t.Run("target exists but category not found", func(t *testing.T) {
		// Set a different category first
		limiter.SetRate(context.Background(), target, 2, Rate{Limit: 100, Remaining: 50})

		// Try to get a category that doesn't exist
		rate, found := limiter.GetRate(context.Background(), target, category)
		assert.False(t, found, "expected not found")
		assert.Nil(t, rate, "expected nil rate")
	})

	t.Run("rate found", func(t *testing.T) {
		expectedRate := Rate{Limit: 100, Remaining: 50, Used: 50}
		limiter.SetRate(context.Background(), target, category, expectedRate)

		rate, found := limiter.GetRate(context.Background(), target, category)
		assert.True(t, found, "expected found")
		require.NotNil(t, rate, "expected non-nil rate")
		assert.Equal(t, expectedRate, *rate, "expected rates to match")
	})
}

func TestGetRates(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	t.Run("no rates found", func(t *testing.T) {
		rates, found := limiter.GetRates(context.Background(), target, 1, 2, 3)
		assert.False(t, found, "expected not found")
		assert.Nil(t, rates, "expected nil rates")
	})

	t.Run("partial rates found", func(t *testing.T) {
		limiter.SetRate(context.Background(), target, 1, Rate{Limit: 100, Remaining: 50})
		limiter.SetRate(context.Background(), target, 3, Rate{Limit: 200, Remaining: 100})

		rates, found := limiter.GetRates(context.Background(), target, 1, 2, 3)
		assert.True(t, found, "expected found")
		assert.Len(t, rates, 2, "expected 2 rates")
		assert.Contains(t, rates, uint8(1), "expected category 1 to be present")
		assert.Contains(t, rates, uint8(3), "expected category 3 to be present")
		assert.NotContains(t, rates, uint8(2), "expected category 2 to be absent")
	})
}

func TestSetRate(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
	category := uint8(1)
	rate := Rate{Limit: 100, Remaining: 50, Used: 50}

	limiter.SetRate(context.Background(), target, category, rate)

	retrievedRate, found := limiter.GetRate(context.Background(), target, category)
	assert.True(t, found, "expected rate to be found after setting")
	require.NotNil(t, retrievedRate, "expected non-nil rate")
	assert.Equal(t, rate, *retrievedRate, "expected rates to match")
}

func TestSetRates(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
	rates := map[uint8]Rate{
		1: {Limit: 100, Remaining: 50, Used: 50},
		2: {Limit: 200, Remaining: 100, Used: 100},
	}

	limiter.SetRates(context.Background(), target, rates)

	retrievedRates, found := limiter.GetRates(context.Background(), target, 1, 2)
	assert.True(t, found, "expected rates to be found after setting")
	assert.Len(t, retrievedRates, 2, "expected 2 rates")
	for category, expectedRate := range rates {
		actualRate, ok := retrievedRates[category]
		assert.True(t, ok, "expected category %d to be present", category)
		assert.Equal(t, expectedRate, actualRate, "expected rates to match for category %d", category)
	}
}

func TestSetRatesOverwriting(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	// Set initial rate
	limiter.SetRate(context.Background(), target, 1, Rate{Limit: 50, Remaining: 25})

	// Set new rates that include the same category
	newRates := map[uint8]Rate{
		1: {Limit: 100, Remaining: 50, Used: 50},
		2: {Limit: 200, Remaining: 100, Used: 100},
	}
	limiter.SetRates(context.Background(), target, newRates)

	// Verify the rate was overwritten
	rate, found := limiter.GetRate(context.Background(), target, 1)
	assert.True(t, found, "expected rate to be found")
	assert.Equal(t, 100, rate.Limit, "expected limit to be overwritten")
}

func TestOwnerIDTarget(t *testing.T) {
	ownerID := int64(12345)
	expected := "app:0:type:installation:id:12345"
	actual := sweagentd.ClientTargetForInstallationByOwnerID(0, ownerID).Key()
	assert.Equal(t, expected, actual, "expected formatted owner ID target to match")
}

func TestOwnerNameTarget(t *testing.T) {
	ownerName := "github"
	expected := "app:0:type:installation:name:github"
	actual := sweagentd.ClientTargetForInstallationByOwnerName(0, ownerName).Key()
	assert.Equal(t, expected, actual, "expected formatted owner name target to match")
}

func TestUserIDTarget(t *testing.T) {
	userID := int64(67890)
	expected := "app:0:type:user:id:67890"
	actual := sweagentd.ClientTargetForUser(0, userID).Key()
	assert.Equal(t, expected, actual, "expected formatted user ID target to match")
}

func TestRateLimiterConcurrency(t *testing.T) {
	// Test concurrent access to the rate limiter
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	// Run multiple goroutines concurrently
	done := make(chan bool, 10)
	for i := range 10 {
		go func(category uint8) {
			defer func() { done <- true }()

			// Set and get rates concurrently
			rate := Rate{Limit: 100, Remaining: int(category), Used: int(100 - category)}
			limiter.SetRate(context.Background(), target, category, rate)

			retrievedRate, found := limiter.GetRate(context.Background(), target, category)
			assert.True(t, found, "expected rate to be found for category %d", category)
			assert.Equal(t, int(category), retrievedRate.Remaining, "expected remaining to match for category %d", category)
		}(uint8(i))
	}

	// Wait for all goroutines to complete
	for range 10 {
		<-done
	}
}

func TestRateIsLimited(t *testing.T) {
	t.Run("not limited - has remaining requests", func(t *testing.T) {
		rate := Rate{
			Limit:     100,
			Remaining: 50,
			Used:      50,
			Reset:     time.Now().Add(time.Hour),
		}

		duration, limited := rate.IsLimited()
		assert.False(t, limited, "expected not limited")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration")
	})

	t.Run("not limited - zero remaining but reset time passed", func(t *testing.T) {
		rate := Rate{
			Limit:     100,
			Remaining: 0,
			Used:      100,
			Reset:     time.Now().Add(-time.Hour), // Reset time in the past
		}

		duration, limited := rate.IsLimited()
		assert.False(t, limited, "expected not limited")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration")
	})

	t.Run("not limited - zero reset time", func(t *testing.T) {
		rate := Rate{
			Limit:     100,
			Remaining: 0,
			Used:      100,
			Reset:     time.Time{}, // Zero time
		}

		duration, limited := rate.IsLimited()
		assert.False(t, limited, "expected not limited")
		assert.Equal(t, time.Duration(0), duration, "expected 0 duration")
	})

	t.Run("limited - zero remaining and reset time in future", func(t *testing.T) {
		resetTime := time.Now().Add(30 * time.Minute)
		rate := Rate{
			Limit:     100,
			Remaining: 0,
			Used:      100,
			Reset:     resetTime,
		}

		duration, limited := rate.IsLimited()
		assert.True(t, limited, "expected limited")
		assert.Positive(t, duration, "expected positive duration")
		// Should be approximately 30 minutes (allowing for small timing differences)
		assert.GreaterOrEqual(t, duration, 29*time.Minute, "expected duration >= 29 minutes")
		assert.LessOrEqual(t, duration, 31*time.Minute, "expected duration <= 31 minutes")
	})
}

func TestWaitToReceiveConcurrency(t *testing.T) {
	store := cache.NewMemoryCacheStore()
	limiter := NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

	t.Run("concurrent WaitToReceive calls with no secondary limit", func(t *testing.T) {
		const numGoroutines = 100
		done := make(chan struct{}, numGoroutines)
		results := make([]bool, numGoroutines)

		// Run many concurrent WaitToReceive calls
		for i := range numGoroutines {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, limited := limiter.WaitToReceive(context.Background(), 0)
				assert.False(t, limited, "expected not limited for goroutine %d", index)
				assert.Equal(t, time.Duration(0), duration, "expected 0 duration for goroutine %d", index)

				results[index] = limited
			}(i)
		}

		// Wait for all goroutines to complete
		for range numGoroutines {
			<-done
		}

		// Verify all calls returned not limited
		for i, limited := range results {
			assert.False(t, limited, "goroutine %d should not be limited", i)
		}
	})

	t.Run("concurrent WaitToReceive calls with secondary limit set", func(t *testing.T) {
		const numGoroutines = 50
		resetTime := time.Now().Add(5 * time.Minute)

		// Set secondary rate limit
		limiter.SetSecondaryRateLimitReset(context.Background(), 0, resetTime)

		done := make(chan struct{}, numGoroutines)
		limitedResults := make([]bool, numGoroutines)
		durationResults := make([]time.Duration, numGoroutines)

		// Run many concurrent WaitToReceive calls
		for i := range numGoroutines {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, limited := limiter.WaitToReceive(context.Background(), 0)
				limitedResults[index] = limited
				durationResults[index] = duration
			}(i)
		}

		// Wait for all goroutines to complete
		for range numGoroutines {
			<-done
		}

		// Verify all calls returned limited with similar durations
		for i := range limitedResults {
			assert.True(t, limitedResults[i], "goroutine %d should be limited", i)
			assert.Positive(t, durationResults[i], "goroutine %d should have positive duration", i)
			// All durations should be approximately the same (within 1 second due to timing)
			assert.GreaterOrEqual(t, durationResults[i], 4*time.Minute, "goroutine %d duration should be >= 4 minutes", i)
			assert.LessOrEqual(t, durationResults[i], 6*time.Minute, "goroutine %d duration should be <= 6 minutes", i)
		}
	})

	t.Run("concurrent SetSecondaryRateLimitReset and WaitToReceive", func(t *testing.T) {
		const numSetters = 10
		const numGetters = 20

		done := make(chan struct{}, numSetters+numGetters)

		// Start setters
		for i := range numSetters {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				// Each setter sets a different reset time
				resetTime := time.Now().Add(time.Duration(index+1) * time.Minute)
				limiter.SetSecondaryRateLimitReset(context.Background(), 0, resetTime)
			}(i)
		}

		// Start getters
		for i := range numGetters {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				// Each getter calls WaitToReceive
				duration, limited := limiter.WaitToReceive(context.Background(), 0)

				// We can't predict exact values due to concurrency, but we can verify
				// that the method doesn't panic or deadlock
				if limited {
					assert.Positive(t, duration, "if limited, duration should be positive for getter %d", index)
				} else {
					assert.Equal(t, time.Duration(0), duration, "if not limited, duration should be 0 for getter %d", index)
				}
			}(i)
		}

		// Wait for all goroutines to complete
		for range numSetters + numGetters {
			<-done
		}
	})
}

func TestDelayProcessingMetrics(t *testing.T) {
	ctx := context.Background()

	type counterCall struct {
		key  string
		tags map[string]string
	}

	newObsvWithCounter := func(t *testing.T) (observability.Exporters, *[]counterCall) {
		t.Helper()
		calls := &[]counterCall{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				*calls = append(*calls, counterCall{key: key, tags: tags})
			},
		}
		return obsv, calls
	}

	t.Run("emits secondary_cache metric when secondary limit active", func(t *testing.T) {
		obsv, calls := newObsvWithCounter(t)
		store := cache.NewMemoryCacheStore()
		client := &mockClient{rateLimits: make(map[string]map[uint8]Rate)}
		l := NewCacheRateLimiter(client, obsv, store, agenticapptest.NewTestProvider(t))

		l.SetSecondaryRateLimitReset(ctx, 0, time.Now().Add(10*time.Minute))
		// Clear the cache_update metric from SetSecondaryRateLimitReset
		*calls = (*calls)[:0]

		_, delayed := l.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed)
		require.Len(t, *calls, 1)
		assert.Equal(t, "rate_limit.delay_processing.delayed", (*calls)[0].key)
		assert.Equal(t, "secondary", (*calls)[0].tags["limit_type"])
		assert.Equal(t, "secondary_cache", (*calls)[0].tags["source"])
	})

	t.Run("emits primary_cache metric when primary limit exceeded", func(t *testing.T) {
		obsv, calls := newObsvWithCounter(t)
		store := cache.NewMemoryCacheStore()
		client := &mockClient{rateLimits: make(map[string]map[uint8]Rate)}
		l := NewCacheRateLimiter(client, obsv, store, agenticapptest.NewTestProvider(t))

		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
		l.SetRate(ctx, target, 1, Rate{Limit: 100, Remaining: 0, Used: 100, Reset: time.Now().Add(time.Hour)})
		*calls = (*calls)[:0]

		_, delayed := l.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed)
		require.Len(t, *calls, 1)
		assert.Equal(t, "rate_limit.delay_processing.delayed", (*calls)[0].key)
		assert.Equal(t, "primary", (*calls)[0].tags["limit_type"])
		assert.Equal(t, "primary_cache", (*calls)[0].tags["source"])
	})

	t.Run("emits fallback_client metric when client reports limit exceeded", func(t *testing.T) {
		obsv, calls := newObsvWithCounter(t)
		store := cache.NewMemoryCacheStore()
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 0, Used: 100, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		l := NewCacheRateLimiter(client, obsv, store, agenticapptest.NewTestProvider(t))

		_, delayed := l.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.True(t, delayed)

		var delayedCalls []counterCall
		for _, c := range *calls {
			if c.key == "rate_limit.delay_processing.delayed" {
				delayedCalls = append(delayedCalls, c)
			}
		}
		require.Len(t, delayedCalls, 1)
		assert.Equal(t, "primary", delayedCalls[0].tags["limit_type"])
		assert.Equal(t, "fallback_client", delayedCalls[0].tags["source"])
	})

	t.Run("no metric emitted when not delayed", func(t *testing.T) {
		obsv, calls := newObsvWithCounter(t)
		store := cache.NewMemoryCacheStore()
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		l := NewCacheRateLimiter(client, obsv, store, agenticapptest.NewTestProvider(t))

		_, delayed := l.DelayProcessing(ctx, 0, 123, 456, 1)
		assert.False(t, delayed)

		for _, c := range *calls {
			assert.NotEqual(t, "rate_limit.delay_processing.delayed", c.key)
		}
	})
}

func TestCacheUpdateMetrics(t *testing.T) {
	ctx := context.Background()

	type counterCall struct {
		key  string
		tags map[string]string
	}

	newObsvWithCounter := func(t *testing.T) (observability.Exporters, *[]counterCall) {
		t.Helper()
		calls := &[]counterCall{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				*calls = append(*calls, counterCall{key: key, tags: tags})
			},
		}
		return obsv, calls
	}

	t.Run("SetSecondaryRateLimitReset emits cache_update metric", func(t *testing.T) {
		obsv, calls := newObsvWithCounter(t)
		store := cache.NewMemoryCacheStore()
		client := &mockClient{rateLimits: make(map[string]map[uint8]Rate)}
		l := NewCacheRateLimiter(client, obsv, store, agenticapptest.NewTestProvider(t))

		l.SetSecondaryRateLimitReset(ctx, 0, time.Now().Add(10*time.Minute))
		require.Len(t, *calls, 1)
		assert.Equal(t, "rate_limit.cache_update", (*calls)[0].key)
		assert.Equal(t, "secondary", (*calls)[0].tags["limit_type"])
	})

	t.Run("SetRate emits cache_update metric when exhausted", func(t *testing.T) {
		obsv, calls := newObsvWithCounter(t)
		store := cache.NewMemoryCacheStore()
		client := &mockClient{rateLimits: make(map[string]map[uint8]Rate)}
		l := NewCacheRateLimiter(client, obsv, store, agenticapptest.NewTestProvider(t))

		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
		l.SetRate(ctx, target, 1, Rate{Limit: 100, Remaining: 0, Used: 100, Reset: time.Now().Add(time.Hour)})
		require.Len(t, *calls, 1)
		assert.Equal(t, "rate_limit.cache_update", (*calls)[0].key)
		assert.Equal(t, "primary", (*calls)[0].tags["limit_type"])
	})

	t.Run("SetRate does not emit metric when not exhausted", func(t *testing.T) {
		obsv, calls := newObsvWithCounter(t)
		store := cache.NewMemoryCacheStore()
		client := &mockClient{rateLimits: make(map[string]map[uint8]Rate)}
		l := NewCacheRateLimiter(client, obsv, store, agenticapptest.NewTestProvider(t))

		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)
		l.SetRate(ctx, target, 1, Rate{Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)})
		assert.Empty(t, *calls)
	})
}

func TestDelayProcessingConcurrency(t *testing.T) {
	ctx := context.Background()

	t.Run("concurrent DelayProcessing calls with same arguments", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		const numGoroutines = 100
		done := make(chan struct{}, numGoroutines)
		delayedResults := make([]bool, numGoroutines)
		durationResults := make([]time.Duration, numGoroutines)

		// Run many concurrent DelayProcessing calls with same arguments
		for i := range numGoroutines {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
				delayedResults[index] = delayed
				durationResults[index] = duration
			}(i)
		}

		// Wait for all goroutines to complete
		for range numGoroutines {
			<-done
		}

		// Verify all calls returned consistent results (not delayed)
		for i := range delayedResults {
			assert.False(t, delayedResults[i], "goroutine %d should not be delayed", i)
			assert.Equal(t, time.Duration(0), durationResults[i], "goroutine %d should have 0 duration", i)
		}
	})

	t.Run("concurrent DelayProcessing calls with different arguments", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 0, Used: 100, Reset: time.Now().Add(time.Hour)},
				},
				formatOwnerRepo(789, 101): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		const numGoroutines = 50
		done := make(chan struct{}, numGoroutines*2)

		// Results for owner 123 (rate limited)
		delayedResults123 := make([]bool, numGoroutines)
		durationResults123 := make([]time.Duration, numGoroutines)

		// Results for owner 789 (not rate limited)
		delayedResults789 := make([]bool, numGoroutines)
		durationResults789 := make([]time.Duration, numGoroutines)

		// Run concurrent calls for owner 123 (rate limited)
		for i := range numGoroutines {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
				delayedResults123[index] = delayed
				durationResults123[index] = duration
			}(i)
		}

		// Run concurrent calls for owner 789 (not rate limited)
		for i := range numGoroutines {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 789, 101, 1)
				delayedResults789[index] = delayed
				durationResults789[index] = duration
			}(i)
		}

		// Wait for all goroutines to complete
		for range numGoroutines * 2 {
			<-done
		}

		// Verify owner 123 results (should be delayed)
		for i := range delayedResults123 {
			assert.True(t, delayedResults123[i], "owner 123 goroutine %d should be delayed", i)
			assert.Positive(t, durationResults123[i], "owner 123 goroutine %d should have positive duration", i)
		}

		// Verify owner 789 results (should not be delayed)
		for i := range delayedResults789 {
			assert.False(t, delayedResults789[i], "owner 789 goroutine %d should not be delayed", i)
			assert.Equal(t, time.Duration(0), durationResults789[i], "owner 789 goroutine %d should have 0 duration", i)
		}
	})

	t.Run("concurrent DelayProcessing with client calls", func(t *testing.T) {
		// Use a client that has no pre-cached rate limits to force client calls
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(111, 222): {
					1: {Limit: 100, Remaining: 10, Used: 90, Reset: time.Now().Add(time.Hour)},
				},
				formatOwnerRepo(333, 444): {
					1: {Limit: 100, Remaining: 0, Used: 100, Reset: time.Now().Add(30 * time.Minute)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		const numGoroutines = 30
		done := make(chan struct{}, numGoroutines*2)

		// Run concurrent calls for different owners that will trigger client calls
		for i := range numGoroutines {
			// Calls for owner 111 (not rate limited)
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 111, 222, 1)
				assert.False(t, delayed, "owner 111 goroutine %d should not be delayed", index)
				assert.Equal(t, time.Duration(0), duration, "owner 111 goroutine %d should have 0 duration", index)
			}(i)

			// Calls for owner 333 (rate limited)
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 333, 444, 1)
				assert.True(t, delayed, "owner 333 goroutine %d should be delayed", index)
				assert.Positive(t, duration, "owner 333 goroutine %d should have positive duration", index)
			}(i)
		}

		// Wait for all goroutines to complete
		for range numGoroutines * 2 {
			<-done
		}
	})

	t.Run("concurrent DelayProcessing with SetRate operations", func(t *testing.T) {
		client := &mockClient{
			rateLimits: make(map[string]map[uint8]Rate),
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		const numSetters = 10
		const numProcessors = 20
		target := sweagentd.ClientTargetForInstallationByOwnerID(0, 555)

		done := make(chan struct{}, numSetters+numProcessors)

		// Start setters that update rate limits
		for i := range numSetters {
			go func(ctx context.Context, index int) {
				defer func() { done <- struct{}{} }()

				// Each setter updates the rate limit with different values
				rate := Rate{
					Limit:     100,
					Remaining: index % 10, // Some will be 0 (rate limited), others > 0
					Used:      100 - (index % 10),
					Reset:     time.Now().Add(time.Duration(index+1) * time.Minute),
				}
				limiter.SetRate(ctx, target, 1, rate)
			}(ctx, i)
		}

		// Start processors that call DelayProcessing
		for i := range numProcessors {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 555, 666, 1)

				// We can't predict exact values due to concurrency, but we can verify
				// that the method doesn't panic or deadlock
				if delayed {
					assert.Positive(t, duration, "if delayed, duration should be positive for processor %d", index)
				} else {
					assert.Equal(t, time.Duration(0), duration, "if not delayed, duration should be 0 for processor %d", index)
				}
			}(i)
		}

		// Wait for all goroutines to complete
		for range numSetters + numProcessors {
			<-done
		}
	})

	t.Run("concurrent DelayProcessing with secondary rate limit set", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		const numGoroutines = 100
		secondaryResetTime := time.Now().Add(10 * time.Minute)

		// Set secondary rate limit
		limiter.SetSecondaryRateLimitReset(ctx, 0, secondaryResetTime)

		done := make(chan struct{}, numGoroutines)
		delayedResults := make([]bool, numGoroutines)
		durationResults := make([]time.Duration, numGoroutines)

		// Run many concurrent DelayProcessing calls
		for i := range numGoroutines {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)
				delayedResults[index] = delayed
				durationResults[index] = duration
			}(i)
		}

		// Wait for all goroutines to complete
		for range numGoroutines {
			<-done
		}

		// Verify all calls returned delayed due to secondary rate limit
		for i := range delayedResults {
			assert.True(t, delayedResults[i], "goroutine %d should be delayed by secondary rate limit", i)
			assert.GreaterOrEqual(t, durationResults[i], 9*time.Minute, "goroutine %d duration should be >= 9 minutes", i)
			assert.LessOrEqual(t, durationResults[i], 11*time.Minute, "goroutine %d duration should be <= 11 minutes", i)
		}
	})

	t.Run("concurrent DelayProcessing and SetSecondaryRateLimitReset", func(t *testing.T) {
		client := &mockClient{
			rateLimits: map[string]map[uint8]Rate{
				formatOwnerRepo(123, 456): {
					1: {Limit: 100, Remaining: 50, Used: 50, Reset: time.Now().Add(time.Hour)},
				},
			},
		}
		store := cache.NewMemoryCacheStore()
		limiter := NewCacheRateLimiter(client, observability.NewNoopExporters(), store, agenticapptest.NewTestProvider(t))

		const numSetters = 10
		const numProcessors = 30

		done := make(chan struct{}, numSetters+numProcessors)

		// Start setters that update secondary rate limit
		for i := range numSetters {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				// Some set future reset times, some set past times
				var resetTime time.Time
				if index%2 == 0 {
					resetTime = time.Now().Add(time.Duration(index+1) * time.Minute)
				} else {
					resetTime = time.Now().Add(-time.Duration(index+1) * time.Minute)
				}
				limiter.SetSecondaryRateLimitReset(ctx, 0, resetTime)
			}(i)
		}

		// Start processors that call DelayProcessing
		for i := range numProcessors {
			go func(index int) {
				defer func() { done <- struct{}{} }()

				duration, delayed := limiter.DelayProcessing(ctx, 0, 123, 456, 1)

				// We can't predict exact values due to concurrency, but we can verify
				// that the method doesn't panic or deadlock
				if delayed {
					assert.Positive(t, duration, "if delayed, duration should be positive for processor %d", index)
				} else {
					assert.Equal(t, time.Duration(0), duration, "if not delayed, duration should be 0 for processor %d", index)
				}
			}(i)
		}

		// Wait for all goroutines to complete
		for range numSetters + numProcessors {
			<-done
		}
	})
}
