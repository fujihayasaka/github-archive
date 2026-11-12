package cache

import (
	"context"
	"errors"
	"log"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/github/go-redis/testcontainers/rediscluster"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/redis"
	goredis "github.com/redis/go-redis/v9"
	"github.com/sony/gobreaker"
	"github.com/stretchr/testify/require"
)

var clusterUris []string

func TestMain(m *testing.M) {
	ctx := context.Background()
	containers, err := rediscluster.NewRedisClusterContainers(ctx)
	if err != nil {
		log.Printf("Failed to create Redis cluster containers: %v", err)
		// return which will cause an os.Exit without a 0 value, failing. We do this here and further down the
		// block because of linter rules and the deferral we want to finish executing.
		return
	}

	defer func() {
		err := containers.Terminate(ctx)
		if err != nil {
			log.Printf("Failed to terminate Redis cluster containers: %v", err)
		}
	}()

	uris, err := containers.ExternalClusterURIs(ctx)
	if err != nil {
		log.Printf("Failed to get external cluster URIs: %v", err)
		return
	}

	for i, uri := range uris {
		clusterURL, err := goredis.ParseClusterURL(uri)
		if err != nil {
			log.Printf("Failed to parse cluster URL %s: %v", uri, err)
			return
		}
		uris[i] = clusterURL.Addrs[0]
	}
	clusterUris = uris
	redisConfig := &config.RedisConfig{Hosts: clusterUris}
	redisClient, err := redis.NewClient(context.Background(), redisConfig, observability.NewNoopExporters())
	if err != nil {
		log.Printf("Failed to create Redis client: %v", err)
		return
	}

	// This timeout should not be hit, if it is getting hit something unexpected is making the redis cluster take too long to start.
	err = waitClusterOK(ctx, redisClient, 30*time.Second)
	if err != nil {
		log.Printf("Redis cluster did not become ready in time: %v", err)
		return
	}

	m.Run()
}

func waitClusterOK(ctx context.Context, client goredis.UniversalClient, timeout time.Duration) error {
	clusterClient, ok := client.(*goredis.ClusterClient)
	if !ok {
		return errors.New("client is not a cluster client")
	}

	// Wait for all nodes to report cluster_state:ok and cluster_slots_assigned:16384
	// Get the status of each node
	deadline := time.Now().Add(timeout)
	for {
		allOK := true
		err := clusterClient.ForEachShard(ctx, func(ctx context.Context, n *goredis.Client) error {
			// Run inside the container so we see the cluster network/ports
			exec := n.ClusterInfo(ctx)
			result, err := exec.Result()
			if err != nil || result == "" ||
				!strings.Contains(result, "cluster_state:ok") || !strings.Contains(result, "cluster_slots_assigned:16384") {
				// If any shard doesn't report the above two statuses, we're not OK
				allOK = false
			}

			return nil
		})
		if allOK && err == nil {
			return nil
		}
		if time.Now().After(deadline) {
			return errors.New("redis cluster not ready before timeout")
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func TestRedisCacheStore(t *testing.T) {
	t.Run("get existing key", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		// Set a value using the store first
		store.Set("test-key", "test-value", 0)

		value, exists := store.Get("test-key")
		require.True(t, exists)
		require.Equal(t, "test-value", value)
	})

	t.Run("get non-existing key", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		value, exists := store.Get("non-existing-key")
		require.False(t, exists)
		require.Equal(t, "", value)
	})

	t.Run("set with expiration", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		store.Set("test-key", "test-value", 1*time.Hour)

		// Verify the value was set by getting it back
		value, exists := store.Get("test-key")
		require.True(t, exists)
		require.Equal(t, "test-value", value)

		// Verify TTL was set by checking with Redis client directly
		ttl := store.redisClient.TTL(context.Background(), "test-key").Val()
		require.Greater(t, ttl, 50*time.Minute)
	})

	t.Run("set without expiration", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		store.Set("test-key", "test-value", 0)

		// Verify the value was set
		value, exists := store.Get("test-key")
		require.True(t, exists)
		require.Equal(t, "test-value", value)

		// Verify no TTL was set
		result := store.redisClient.TTL(context.Background(), "test-key")
		ttl := result.Val()
		require.Equal(t, time.Duration(-1), ttl) // -1 means no expiration
	})

	t.Run("metrics are recorded for operations", func(t *testing.T) {
		var mockCounters map[string]int64
		mockStatter := &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				if mockCounters == nil {
					mockCounters = make(map[string]int64)
				}
				mockCounters[key] += value
			},
		}

		store := setupTestRedisStore(t, mockStatter)

		// Test Get operation
		store.Set("test-key", "test-value", 0)
		_, exists := store.Get("test-key")
		require.True(t, exists)

		require.Equal(t, int64(2), mockCounters["cache_operation"])

		// Test SetMultiple operation
		store.SetMultiple(map[string]string{"test-key2": "test-value2"}, time.Hour)
		require.Equal(t, int64(3), mockCounters["cache_operation"])
	})

	t.Run("increment non-existing key", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		value, ok := store.Incr("counter", 5, 0)

		require.True(t, ok)
		require.Equal(t, int64(5), value)

		// Verify the value was set
		result, exists := store.Get("counter")
		require.True(t, exists)
		require.Equal(t, "5", result)
	})

	t.Run("increment existing key", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		store.Set("counter", "10", 0)

		value, ok := store.Incr("counter", 3, 0)
		require.True(t, ok)
		require.Equal(t, int64(13), value)

		// Verify the value was updated
		result, exists := store.Get("counter")
		require.True(t, exists)
		require.Equal(t, "13", result)
	})

	t.Run("increment with TTL", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		value, ok := store.Incr("counter", 1, time.Second*10)
		require.True(t, ok)
		require.Equal(t, int64(1), value)

		// Check TTL was set (miniredis supports TTL)
		ttl := store.redisClient.TTL(context.Background(), "counter").Val()
		require.True(t, ttl > 0 && ttl <= time.Second*10)
	})

	t.Run("concurrent increments are atomic", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		key := "atomic_counter"
		numGoroutines := 100
		incrementsPerGoroutine := 10

		var wg sync.WaitGroup

		for range numGoroutines {
			wg.Go(func() {
				for range incrementsPerGoroutine {
					_, ok := store.Incr(key, 1, 0)
					require.True(t, ok)
				}
			})
		}

		wg.Wait()

		expectedValue := int64(numGoroutines * incrementsPerGoroutine)
		result, exists := store.Get(key)
		require.True(t, exists)
		require.Equal(t, "1000", result) // 100 goroutines × 10 increments each

		value, ok := store.Incr(key, 0, 0) // Increment by 0 to just get current value
		require.True(t, ok)
		require.Equal(t, expectedValue, value)
	})

	t.Run("decrement non-existent key", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)

		// Decrement non-existent key
		newVal, ok := store.Decr("counter", 5, 0)
		require.True(t, ok)
		require.Equal(t, int64(0), newVal)

		val, exists := store.Get("counter")
		require.True(t, exists)
		require.Equal(t, "0", val)
	})

	t.Run("decrement existing key", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		store.Set("counter", "10", 0)

		newVal, ok := store.Decr("counter", 3, 0)
		require.True(t, ok)
		require.Equal(t, int64(7), newVal)

		val, exists := store.Get("counter")
		require.True(t, exists)
		require.Equal(t, "7", val)
	})

	t.Run("decrement never goes below zero", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		store.Set("counter", "3", 0)

		newVal, ok := store.Decr("counter", 10, 0)
		require.True(t, ok)
		require.Equal(t, int64(0), newVal)

		val, exists := store.Get("counter")
		require.True(t, exists)
		require.Equal(t, "0", val)
	})

	t.Run("decrement with TTL", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		store.Set("counter", "15", 0)
		value, ok := store.Decr("counter", 5, time.Second*10)
		require.True(t, ok)
		require.Equal(t, int64(10), value)

		// Check TTL was set (miniredis supports TTL)
		ttl := store.redisClient.TTL(context.Background(), "counter").Val()
		require.True(t, ttl > 0 && ttl <= time.Second*10)
	})

	t.Run("concurrent decrements are atomic", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		key := "atomic_counter"
		store.Set(key, "1500", 0) // Start with 1500 as the initial value
		numGoroutines := 100
		decrementsPerGoroutine := 10

		var wg sync.WaitGroup

		for range numGoroutines {
			wg.Go(func() {
				for range decrementsPerGoroutine {
					_, ok := store.Decr(key, 1, 0)
					require.True(t, ok)
				}
			})
		}

		wg.Wait()

		result, exists := store.Get(key)
		require.True(t, exists)
		require.Equal(t, "500", result)

		value, ok := store.Decr(key, 0, 0) // Decrement by 0 to just get current value
		require.True(t, ok)
		require.Equal(t, int64(500), value)
	})

	t.Run("mixed concurrent increments and decrements are atomic", func(t *testing.T) {
		store := setupTestRedisStore(t, nil)
		key := "atomic_counter"
		store.Set(key, "2000", 0) // Start with 2000 as the initial value to avoid being floored
		numGoroutines := 100
		incrementsPerGoroutine := 5
		decrementsPerGoroutine := 10

		var wg sync.WaitGroup

		for range numGoroutines {
			wg.Go(func() {
				for range incrementsPerGoroutine {
					_, ok := store.Incr(key, 1, 0)
					require.True(t, ok)
				}
			})

			wg.Go(func() {
				for range decrementsPerGoroutine {
					_, ok := store.Decr(key, 1, 0)
					require.True(t, ok)
				}
			})
		}

		wg.Wait()

		result, exists := store.Get(key)
		require.True(t, exists)
		require.Equal(t, "1500", result) // 2000 initial value + (100*5) - (100*10) = 1500
	})
}

func setupTestRedisStore(t *testing.T, statter stats.Client) *RedisStore {
	t.Helper()
	redisConfig := &config.RedisConfig{Hosts: clusterUris}
	redisClient, err := redis.NewClient(context.Background(), redisConfig, observability.NewNoopExporters())
	require.NoError(t, err)

	// Create circuit breaker with test-friendly settings
	cb := gobreaker.NewCircuitBreaker(gobreaker.Settings{
		Name:        "test-redis",
		MaxRequests: 3,
		Interval:    10 * time.Second,
		Timeout:     5 * time.Second,
	})

	// Create mock observability with noop tracer
	obsv := observability.NewNoopExporters()
	if statter != nil {
		obsv.Statter = statter
	}

	store := NewRedisStore(context.Background(), redisClient, cb, obsv)

	t.Cleanup(func() {
		flushAllResult := redisClient.FlushAll(context.Background())
		err := flushAllResult.Err()
		if err != nil {
			t.Logf("error calling FlushAll on redis : %v", err)
		}

		flushDBresult := redisClient.FlushDB(context.Background())
		err = flushDBresult.Err()
		if err != nil {
			t.Logf("error calling FlushDB on redis : %v", err)
		}

		redisClient.Close()
	})

	return store
}
