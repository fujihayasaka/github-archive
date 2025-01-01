package quota

import (
	"context"
	"math"
	"math/rand"
	"os"
	"testing"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/stretchr/testify/require"
)

type testRateEstimator interface {
	RateEstimator

	SimulateClock(ctx context.Context)

	// AdvanceClock makes the simulated quota system think some time has passed.
	// It's a way to make it look (to the quota system) as if some time passed
	// between queries.
	AdvanceClock(ctx context.Context, seconds float64)
}

func testRedisRateEstimator(t *testing.T, ctx context.Context) *RedisRateEstimator {
	t.Helper()
	if os.Getenv("RUN_REDIS_TESTS") == "" {
		t.Skipf("RUN_REDIS_TESTS is not set, skipping %s", t.Name())
	}
	client := redis.NewClient(&redis.Options{Addr: "localhost:6380"})
	est, err := NewRedisRateEstimator(ctx, client)
	require.NoError(t, err)
	return est
}

// randomKey chooses a random key so that each of the tests can run concurrently
// without stepping on each other.
func randomKey() Key {
	return newBucket("query", userQueryPreCharge).KeyForActor(rand.Uint32())
}

func checkAllRateEstimators(t *testing.T, check func(*testing.T, context.Context, testRateEstimator, Key)) {
	t.Helper()
	t.Parallel()
	key := randomKey()

	t.Run("Memory", func(t *testing.T) {
		t.Parallel()
		ctx := context.Background()
		est := NewMemoryRateEstimator()
		est.SimulateClock(ctx)
		check(t, ctx, est, key)
	})

	t.Run("Redis", func(t *testing.T) {
		t.Parallel()
		ctx := context.Background()
		est := testRedisRateEstimator(t, ctx)
		est.SimulateClock(ctx)
		check(t, ctx, est, key)
	})
}

func TestCanConnectToRedis(t *testing.T) {
	// The underlying constuctor loads the Lua scripts into Redis, and therefore
	// verifies that the connection is valid.
	t.Parallel()
	ctx := context.Background()
	_ = testRedisRateEstimator(t, ctx)
}

func TestRedisNonSimulatedClock(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	est := testRedisRateEstimator(t, ctx)
	key := randomKey()
	// Verify that is we _don't_ simulate the clock in our Redis estimator, it
	// correctly returns a timestamp that is close to current time.
	_, rates, err := est.PreQueryCharge(ctx, key, 0, standardShortTermRateLimit, standardLongTermRateLimit)
	require.NoError(t, err)
	require.WithinDuration(t, time.Now(), rates.Time(), time.Duration(5)*time.Second)
}

func TestPreChargeNotAppliedWhenInViolation(t *testing.T) {
	// An amount of charge that would immediately put the user over the short-term rate limit.
	shortTermLambda := math.Log(2.0) / shortTermHalfLifeSeconds
	shortTermMaxCharge := (standardShortTermRateLimit / shortTermLambda) * 1.5

	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		// Put ourselves into violation of the rate limit.
		result, _, err := est.PreQueryCharge(ctx, key, shortTermMaxCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		_, before, _ := est.PreQueryCharge(ctx, key, 0, standardShortTermRateLimit, standardLongTermRateLimit)

		// Verify that the next request gets a rate limit exceeded error.
		result, _, err = est.PreQueryCharge(ctx, key, shortTermMaxCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaShortViolation)

		// Verify that the second request's pre_charge was not applied.
		_, after, _ := est.PreQueryCharge(ctx, key, 0, standardShortTermRateLimit, standardLongTermRateLimit)
		require.Equal(t, before.ShortTermRate, after.ShortTermRate)
		require.Equal(t, before.LongTermRate, after.LongTermRate)
	})
}

func TestAdjustCostToZero(t *testing.T) {
	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		result, rates, err := est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Equal(t, rates.ShortTermRate, 0.0)
		require.Equal(t, rates.LongTermRate, 0.0)

		// Adjust that query's cost to 0.
		est.AdvanceClock(ctx, 6.0)
		err = est.PostQueryAdjust(ctx, key, rates.timestamp, userQueryPreCharge, 0.0)
		require.NoError(t, err)

		// Rate should still be (very close to) 0.
		result, rates, err = est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.GreaterOrEqual(t, rates.ShortTermRate, 0.0)
		require.Less(t, rates.ShortTermRate, 0.01)
		require.GreaterOrEqual(t, rates.LongTermRate, 0.0)
		require.Less(t, rates.LongTermRate, 0.00001)
	})
}

func TestAsymptoticRate(t *testing.T) {
	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		var result QuotaResult
		var rates *RateEstimate
		var err error
		for i := 0; i < 600; i++ {
			result, rates, err = est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
			require.NoError(t, err)
			require.Equal(t, result, QuotaOk)

			est.AdvanceClock(ctx, 1.0)
			err = est.PostQueryAdjust(ctx, key, rates.timestamp, userQueryPreCharge, 1000.0)
			require.NoError(t, err)

			est.AdvanceClock(ctx, 1.0)
		}

		// The short-term rate should quickly converge to the true usage rate,
		// 1000 every 2 seconds, or 500 per second.
		require.Greater(t, rates.ShortTermRate, 495.0)
		require.Less(t, rates.ShortTermRate, 505.0)

		// The long-term rate needs 12 hours of data to converge, so it should
		// still be close to 0.
		require.Less(t, rates.LongTermRate, 60.0)
		require.Greater(t, rates.LongTermRate, 0.0)

		// A week later, both rates should be very close to zero.
		est.AdvanceClock(ctx, 7.0*24.0*60.0*60.0)
		result, rates, err = est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Zero(t, rates.ShortTermRate)
		require.Less(t, rates.LongTermRate, 0.001)
	})
}

func TestAdjustWithConcurrentQueries(t *testing.T) {
	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		// Four queries come in concurrently.
		est.AdvanceClock(ctx, 289.0) // t=289
		result, rates1, err := est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Zero(t, rates1.ShortTermRate)
		result, rates2, err := est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Positive(t, rates2.ShortTermRate)
		est.AdvanceClock(ctx, 4.0) // t=293
		result, rates3, err := est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Positive(t, rates3.ShortTermRate)
		result, rates4, err := est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Positive(t, rates4.ShortTermRate)

		// The actual cost of the queries proves to be less than we reserved,
		// so refund some quota.
		est.AdvanceClock(ctx, 15.0) // t=308
		_ = est.PostQueryAdjust(ctx, key, rates1.timestamp, userQueryPreCharge, 121)
		_ = est.PostQueryAdjust(ctx, key, rates3.timestamp, userQueryPreCharge, 111)
		_ = est.PostQueryAdjust(ctx, key, rates4.timestamp, userQueryPreCharge, 197)
		_ = est.PostQueryAdjust(ctx, key, rates2.timestamp, userQueryPreCharge, 177)

		// But the overall rate estimate should still be positive.
		est.AdvanceClock(ctx, 9.0) // t=317
		result, rates5, err := est.PreQueryCharge(ctx, key, userQueryPreCharge, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Positive(t, rates5.ShortTermRate)
	})
}

func TestResetRates(t *testing.T) {
	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		// Ensure that resetting works when there are no rates set yet.
		require.NoError(t, est.ResetRates(ctx, key))

		// Ensure that resetting works when there is a rate set.
		result, _, err := est.PreQueryCharge(ctx, key, 5, standardShortTermRateLimit, standardLongTermRateLimit)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.NoError(t, est.ResetRates(ctx, key))
	})

}

func TestBanTime(t *testing.T) {
	est := RateEstimate{
		key:           userQueryBucket.KeyForActor(7),
		timestamp:     0.0,
		PreCharge:     0.0,
		ShortTermRate: 8.0 * standardShortTermRateLimit,
		LongTermRate:  standardLongTermRateLimit,
	}
	require.Greater(t, est.BanTime(standardShortTermRateLimit, standardLongTermRateLimit), 2.99*shortTermHalfLifeSeconds)
	require.Less(t, est.BanTime(standardShortTermRateLimit, standardLongTermRateLimit), 3.01*shortTermHalfLifeSeconds)

	est.LongTermRate = 2.0 * standardLongTermRateLimit
	require.Greater(t, est.BanTime(standardShortTermRateLimit, standardLongTermRateLimit), 0.99*longTermHalfLifeSeconds)
	require.Less(t, est.BanTime(standardShortTermRateLimit, standardLongTermRateLimit), 1.01*longTermHalfLifeSeconds)

	est.ShortTermRate = 0.9 * standardShortTermRateLimit
	est.LongTermRate = 0.3 * standardLongTermRateLimit
	require.Zero(t, est.BanTime(standardShortTermRateLimit, standardLongTermRateLimit))
}
