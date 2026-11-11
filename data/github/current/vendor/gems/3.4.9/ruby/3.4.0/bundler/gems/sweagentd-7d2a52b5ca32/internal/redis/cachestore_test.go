package redis

import (
	"context"
	"errors"
	"log"
	"strings"
	"testing"
	"time"

	"github.com/github/go-redis/testcontainers/rediscluster"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/observability"
	"github.com/redis/go-redis/v9"
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
		clusterURL, err := redis.ParseClusterURL(uri)
		if err != nil {
			log.Printf("Failed to parse cluster URL %s: %v", uri, err)
			return
		}
		uris[i] = clusterURL.Addrs[0]
	}
	clusterUris = uris
	redisConfig := &config.RedisConfig{Hosts: clusterUris}
	redisClient, err := NewClient(context.Background(), redisConfig, observability.NewNoopExporters())
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

func waitClusterOK(ctx context.Context, client redis.UniversalClient, timeout time.Duration) error {
	clusterClient, ok := client.(*redis.ClusterClient)
	if !ok {
		return errors.New("client is not a cluster client")
	}

	// Wait for all nodes to report cluster_state:ok and cluster_slots_assigned:16384
	// Get the status of each node
	deadline := time.Now().Add(timeout)
	for {
		allOK := true
		err := clusterClient.ForEachShard(ctx, func(ctx context.Context, n *redis.Client) error {
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

func TestRedis(t *testing.T) {
	t.Run("get existing key", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		// Set a value using the store first
		err := store.Set(ctx, "test-key", "test-value", 0)
		require.NoError(t, err)

		value, err := store.Get(ctx, "test-key")
		require.NoError(t, err)
		require.Equal(t, "test-value", value)
	})

	t.Run("get non-existing key", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		value, err := store.Get(ctx, "non-existing-key")
		require.NoError(t, err)
		require.Equal(t, "", value)
	})

	t.Run("context cancellation", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx, cancel := context.WithCancel(context.Background())
		cancel() // Cancel immediately

		_, err := store.Get(ctx, "test-key")
		require.Error(t, err)
		require.True(t, errors.Is(err, context.Canceled))
	})

	t.Run("get multiple existing keys", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		// Set values using the store
		values := map[string]string{
			"key1": "value1",
			"key2": "value2",
			"key3": "value3",
		}
		err := store.SetMultiple(ctx, values, 0)
		require.NoError(t, err)

		result, err := store.GetMultiple(ctx, []string{"key1", "key2", "key3"})
		require.NoError(t, err)
		require.Equal(t, values, result)
	})

	t.Run("get multiple with some missing keys", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		// Set only some values
		err := store.Set(ctx, "key1", "value1", 0)
		require.NoError(t, err)
		err = store.Set(ctx, "key3", "value3", 0)
		require.NoError(t, err)

		values, err := store.GetMultiple(ctx, []string{"key1", "key2", "key3"})
		require.NoError(t, err)
		expected := map[string]string{
			"key1": "value1",
			"key3": "value3",
		}
		require.Equal(t, expected, values)
	})

	t.Run("context cancellation", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx, cancel := context.WithCancel(context.Background())
		cancel() // Cancel immediately

		_, err := store.GetMultiple(ctx, []string{"key1", "key2"})
		require.Error(t, err)
		require.True(t, errors.Is(err, context.Canceled))
	})

	t.Run("set with expiration", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		err := store.Set(ctx, "test-key", "test-value", 1*time.Hour)
		require.NoError(t, err)

		// Verify the value was set by getting it back
		value, err := store.Get(ctx, "test-key")
		require.NoError(t, err)
		require.Equal(t, "test-value", value)

		// Verify TTL was set by checking with Redis client directly
		ttl := store.redisClient.TTL(ctx, store.applyHashTag("test-key")).Val()
		require.Greater(t, ttl, 50*time.Minute)
	})

	t.Run("delete", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		err := store.Set(ctx, "test-key", "test-value", 1*time.Hour)
		require.NoError(t, err)

		// Verify the value was set by getting it back
		value, err := store.Get(ctx, "test-key")
		require.NoError(t, err)
		require.Equal(t, "test-value", value)

		err = store.Delete(ctx, "test-key")
		require.NoError(t, err)

		// Verify the value was deleted by trying to get it back
		value, err = store.Get(ctx, "test-key")
		require.NoError(t, err)
		require.Equal(t, "", value)
	})

	t.Run("set without expiration", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		err := store.Set(ctx, "test-key", "test-value", -1)
		require.NoError(t, err)

		// Verify the value was set
		value, err := store.Get(ctx, "test-key")
		require.NoError(t, err)
		require.Equal(t, "test-value", value)

		// Verify no TTL was set
		result := store.redisClient.TTL(ctx, store.applyHashTag("test-key"))
		ttl := result.Val()
		require.Equal(t, time.Duration(-1), ttl) // -1 means no expiration
	})

	t.Run("context cancellation", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx, cancel := context.WithCancel(context.Background())
		cancel() // Cancel immediately

		err := store.Set(ctx, "test-key", "test-value", 1*time.Hour)
		require.Error(t, err)
		require.True(t, errors.Is(err, context.Canceled))
	})

	t.Run("set multiple with TTL", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		values := map[string]string{
			"key1": "value1",
			"key2": "value2",
			"key3": "value3",
		}

		err := store.SetMultiple(ctx, values, 1*time.Hour)
		require.NoError(t, err)

		// Verify all values were set
		result, err := store.GetMultiple(ctx, []string{"key1", "key2", "key3"})
		require.NoError(t, err)
		require.Equal(t, values, result)

		// Verify TTL was set for all keys
		for key := range values {
			ttl := store.redisClient.TTL(ctx, store.applyHashTag(key)).Val()
			require.Greater(t, ttl, 0*time.Minute)
		}
	})

	t.Run("set multiple without TTL", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		values := map[string]string{
			"key1": "value1",
			"key2": "value2",
		}

		err := store.SetMultiple(ctx, values, 0)
		require.NoError(t, err)

		// Verify all values were set
		result, err := store.GetMultiple(ctx, []string{"key1", "key2"})
		require.NoError(t, err)
		require.Equal(t, values, result)

		// Verify no TTL was set
		for key := range values {
			ttl := store.redisClient.TTL(ctx, store.applyHashTag(key)).Val()
			require.Equal(t, time.Duration(-1), ttl) // -1 means no expiration
		}
	})

	t.Run("set multiple with circuit breaker open", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		// Force circuit breaker to open by making failed requests
		for i := 0; i < 5; i++ {
			store.SetMultiple(ctx, map[string]string{"test-key": "test-value"}, 1*time.Hour)
		}

		values := map[string]string{"key1": "value1"}
		err := store.SetMultiple(ctx, values, 1*time.Hour)
		require.NoError(t, err) // Should return nil when circuit breaker is open
	})

	t.Run("metrics are recorded for operations", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx := context.Background()

		mockStatter := store.obsv.Statter.(*mockStatter)

		// Test Get operation
		err := store.Set(ctx, "test-key", "test-value", 0)
		require.NoError(t, err)
		_, err = store.Get(ctx, "test-key")
		require.NoError(t, err)

		require.Equal(t, int64(2), mockStatter.counters["cache_operation"])

		// Test SetMultiple operation
		err = store.SetMultiple(ctx, map[string]string{"test-key2": "test-value2"}, time.Hour)
		require.NoError(t, err)

		require.Equal(t, int64(3), mockStatter.counters["cache_operation"])
	})

	t.Run("respects context cancellation", func(t *testing.T) {
		store := setupTestRedisStore(t)
		ctx, cancel := context.WithCancel(context.Background())
		cancel() // Cancel immediately

		_, err := store.Get(ctx, "test-key")
		require.Error(t, err)
		require.True(t, errors.Is(err, context.Canceled))
	})
}

func setupTestRedisStore(t *testing.T) *Store {
	t.Helper()
	redisConfig := &config.RedisConfig{Hosts: clusterUris}
	redisClient, err := NewClient(context.Background(), redisConfig, observability.NewNoopExporters())
	require.NoError(t, err)

	// Create circuit breaker with test-friendly settings
	cb := gobreaker.NewCircuitBreaker(gobreaker.Settings{
		Name:        "test-redis",
		MaxRequests: 3,
		Interval:    10 * time.Second,
		Timeout:     5 * time.Second,
	})

	// Create mock observability
	obsv := &observability.Exporters{
		Statter: &mockStatter{},
	}

	store := NewStore(redisClient, cb, obsv, t.Name())

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

// mockStatter implements the stats.Client interface for testing
type mockStatter struct {
	stats.NullClient

	counters map[string]int64
	gauges   map[string]int64
	timings  map[string][]time.Duration
}

func (m *mockStatter) Counter(name string, tags stats.Tags, value int64) {
	if m.counters == nil {
		m.counters = make(map[string]int64)
	}
	m.counters[name] += value
}

func (m *mockStatter) Gauge(name string, tags stats.Tags, value int64) {
	if m.gauges == nil {
		m.gauges = make(map[string]int64)
	}
	m.gauges[name] = value
}

func (m *mockStatter) Timing(name string, tags stats.Tags, value time.Duration) {
	if m.timings == nil {
		m.timings = make(map[string][]time.Duration)
	}
	m.timings[name] = append(m.timings[name], value)
}

func (m *mockStatter) WithTags(tags stats.Tags) stats.Client {
	return m
}
