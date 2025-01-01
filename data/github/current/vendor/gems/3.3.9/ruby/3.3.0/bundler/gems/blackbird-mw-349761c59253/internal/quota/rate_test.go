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
	return Bucket("query").KeyForActor(rand.Uint32())
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
	_, rates, err := est.PreQueryCharge(ctx, key, 0)
	require.NoError(t, err)
	require.WithinDuration(t, time.Now(), rates.Time(), time.Duration(5)*time.Second)
}

func TestPreChargeNotAppliedWhenInViolation(t *testing.T) {
	// An amount of charge that would immediately put the user over the short-term rate limit.
	shortTermLambda := math.Log(2.0) / shortTermHalfLifeSeconds
	shortTermMaxCharge := (shortTermRateLimit / shortTermLambda) * 1.5

	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		// Put ourselves into violation of the rate limit.
		result, _, err := est.PreQueryCharge(ctx, key, shortTermMaxCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		_, before, _ := est.PreQueryCharge(ctx, key, 0)

		// Verify that the next request gets a rate limit exceeded error.
		result, _, err = est.PreQueryCharge(ctx, key, shortTermMaxCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaShortViolation)

		// Verify that the second request's pre_charge was not applied.
		_, after, _ := est.PreQueryCharge(ctx, key, 0)
		require.Equal(t, before.ShortTermRate, after.ShortTermRate)
		require.Equal(t, before.LongTermRate, after.LongTermRate)
	})
}

func TestAdjustCostToZero(t *testing.T) {
	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		result, rates, err := est.PreQueryCharge(ctx, key, userQueryPreCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Equal(t, rates.ShortTermRate, 0.0)
		require.Equal(t, rates.LongTermRate, 0.0)

		// Adjust that query's cost to 0.
		est.AdvanceClock(ctx, 6.0)
		err = est.PostQueryAdjust(ctx, key, rates.timestamp, userQueryPreCharge, 0.0)
		require.NoError(t, err)

		// Rate should still be (very close to) 0.
		result, rates, err = est.PreQueryCharge(ctx, key, userQueryPreCharge)
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
			result, rates, err = est.PreQueryCharge(ctx, key, userQueryPreCharge)
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
		result, rates, err = est.PreQueryCharge(ctx, key, userQueryPreCharge)
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
		result, rates1, err := est.PreQueryCharge(ctx, key, userQueryPreCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Zero(t, rates1.ShortTermRate)
		result, rates2, err := est.PreQueryCharge(ctx, key, userQueryPreCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Positive(t, rates2.ShortTermRate)
		est.AdvanceClock(ctx, 4.0) // t=293
		result, rates3, err := est.PreQueryCharge(ctx, key, userQueryPreCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Positive(t, rates3.ShortTermRate)
		result, rates4, err := est.PreQueryCharge(ctx, key, userQueryPreCharge)
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
		result, rates5, err := est.PreQueryCharge(ctx, key, userQueryPreCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.Positive(t, rates5.ShortTermRate)
	})
}

func getShortTermRate(t *testing.T, ctx context.Context, est RateEstimator, key Key) float64 {
	t.Helper()
	_, rates, err := est.PreQueryCharge(ctx, key, 0)
	require.NoError(t, err)
	return rates.ShortTermRate
}

func TestConcurrentAccessibleReposAPIRequestScenario(t *testing.T) {
	checkAllRateEstimators(t, func(t *testing.T, ctx context.Context, est testRateEstimator, key Key) {
		// A user triggers 5 concurrent requests that must all be authorized.
		est.AdvanceClock(ctx, 300.0) // t=300

		rates := make([]*RateEstimate, 5)
		for i := 0; i < 5; i++ {
			result, est, err := est.PreQueryCharge(ctx, key, AccessibleResourcesPreCharge)
			require.NoError(t, err)
			require.Equal(t, result, QuotaOk)
			require.LessOrEqual(t, est.ShortTermRate, float64(shortTermRateLimit))
			rates[i] = est
		}

		// But a sixth would be rejected.
		require.Greater(t, getShortTermRate(t, ctx, est, key), float64(shortTermRateLimit))

		// Advancing the clock by 10 seconds (rails global timeout), the user's
		// short-term rate is still greater than the short-term limit.
		est.AdvanceClock(ctx, 10.0) // t=310
		require.Greater(t, getShortTermRate(t, ctx, est, key), float64(shortTermRateLimit))

		// The first request returns. The precharge cost is fully refunded.
		_ = est.PostQueryAdjust(ctx, key, rates[0].timestamp, AccessibleResourcesPreCharge, 0)

		// The user's short term quota is now below the short term rate limit.
		require.LessOrEqual(t, getShortTermRate(t, ctx, est, key), float64(shortTermRateLimit))

		// The user is now able to issue a new fifth concurrent API request.
		result, rates6, err := est.PreQueryCharge(ctx, key, AccessibleResourcesPreCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.LessOrEqual(t, rates6.ShortTermRate, float64(shortTermRateLimit))

		// But the user would still not be able to issue a sixth concurrent request.
		require.Greater(t, getShortTermRate(t, ctx, est, key), float64(shortTermRateLimit))

		// Advancing the clock by 5 seconds, the user's short-term quota is now less
		// than the short-term limit. There are still five concurrent API requests inflight.
		// The first batch of requests was issued at t=300, and the most recent valid request
		// was issued at t=310. This means the user's short-term rate will decay naturally
		// 15 seconds after the first request is made.
		est.AdvanceClock(ctx, 5.0) // t=315
		// The user is now able to issue a new fifth concurrent API request.
		result, rates7, err := est.PreQueryCharge(ctx, key, AccessibleResourcesPreCharge)
		require.NoError(t, err)
		require.Equal(t, result, QuotaOk)
		require.LessOrEqual(t, rates7.ShortTermRate, float64(shortTermRateLimit))

		// But the user would still not be able to issue a sixth concurrent request.
		require.Greater(t, getShortTermRate(t, ctx, est, key), float64(shortTermRateLimit))
	})
}

func TestBanTime(t *testing.T) {
	est := RateEstimate{
		key:           Bucket("query").KeyForActor(7),
		timestamp:     0.0,
		PreCharge:     0.0,
		ShortTermRate: 8.0 * shortTermRateLimit,
		LongTermRate:  longTermRateLimit,
	}
	require.Greater(t, est.BanTime(), 2.99*shortTermHalfLifeSeconds)
	require.Less(t, est.BanTime(), 3.01*shortTermHalfLifeSeconds)

	est.LongTermRate = 2.0 * longTermRateLimit
	require.Greater(t, est.BanTime(), 0.99*longTermHalfLifeSeconds)
	require.Less(t, est.BanTime(), 1.01*longTermHalfLifeSeconds)

	est.ShortTermRate = 0.9 * shortTermRateLimit
	est.LongTermRate = 0.3 * longTermRateLimit
	require.Zero(t, est.BanTime())
}
