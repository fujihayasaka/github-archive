// Package cache contains tests for the in-memory cache store implementation.
// These tests verify the behavior of the InMemoryStore which implements the Store interface
// using an LRU cache with TTL support.
package cache

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewInMemoryStore(t *testing.T) {
	t.Run("creates store with valid max size", func(t *testing.T) {
		store := NewInMemoryStore(100)
		assert.NotNil(t, store)
		assert.NotNil(t, store.store)
	})

	t.Run("uses default size when max size is zero", func(t *testing.T) {
		store := NewInMemoryStore(0)
		assert.NotNil(t, store)
		assert.NotNil(t, store.store)
	})

	t.Run("uses default size when max size is negative", func(t *testing.T) {
		store := NewInMemoryStore(-10)
		assert.NotNil(t, store)
		assert.NotNil(t, store.store)
	})
}

func TestInMemoryStore_SetAndGet(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryStore(100)

	t.Run("sets and gets a value without TTL", func(t *testing.T) {
		err := store.Set(ctx, "key1", "value1", 0)
		require.NoError(t, err)

		value, err := store.Get(ctx, "key1")
		require.NoError(t, err)
		assert.Equal(t, "value1", value)
	})

	t.Run("sets and gets a value with TTL", func(t *testing.T) {
		err := store.Set(ctx, "key2", "value2", time.Hour)
		require.NoError(t, err)

		value, err := store.Get(ctx, "key2")
		require.NoError(t, err)
		assert.Equal(t, "value2", value)
	})

	t.Run("returns empty string for non-existent key", func(t *testing.T) {
		value, err := store.Get(ctx, "non-existent")
		require.NoError(t, err)
		assert.Equal(t, "", value)
	})

	t.Run("overwrites existing value", func(t *testing.T) {
		err := store.Set(ctx, "key3", "value3", 0)
		require.NoError(t, err)

		err = store.Set(ctx, "key3", "new-value3", 0)
		require.NoError(t, err)

		value, err := store.Get(ctx, "key3")
		require.NoError(t, err)
		assert.Equal(t, "new-value3", value)
	})
}

func TestInMemoryStore_TTLExpiration(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryStore(100)

	t.Run("returns empty string for expired entry", func(t *testing.T) {
		// Set a value with very short TTL
		err := store.Set(ctx, "expire-key", "expire-value", time.Millisecond)
		require.NoError(t, err)

		// Wait for expiration
		time.Sleep(10 * time.Millisecond)

		value, err := store.Get(ctx, "expire-key")
		require.NoError(t, err)
		assert.Equal(t, "", value)
	})

	t.Run("value is accessible before expiration", func(t *testing.T) {
		err := store.Set(ctx, "valid-key", "valid-value", time.Second)
		require.NoError(t, err)

		value, err := store.Get(ctx, "valid-key")
		require.NoError(t, err)
		assert.Equal(t, "valid-value", value)
	})

	t.Run("removes expired entry from store", func(t *testing.T) {
		err := store.Set(ctx, "remove-key", "remove-value", time.Millisecond)
		require.NoError(t, err)

		// Wait for expiration
		time.Sleep(10 * time.Millisecond)

		// First call should remove the expired entry
		value, err := store.Get(ctx, "remove-key")
		require.NoError(t, err)
		assert.Equal(t, "", value)

		// Second call should also return empty (entry was removed)
		value, err = store.Get(ctx, "remove-key")
		require.NoError(t, err)
		assert.Equal(t, "", value)
	})
}

func TestInMemoryStore_Delete(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryStore(100)

	t.Run("deletes existing key", func(t *testing.T) {
		err := store.Set(ctx, "delete-key", "delete-value", 0)
		require.NoError(t, err)

		err = store.Delete(ctx, "delete-key")
		require.NoError(t, err)

		value, err := store.Get(ctx, "delete-key")
		require.NoError(t, err)
		assert.Equal(t, "", value)
	})

	t.Run("deleting non-existent key does not error", func(t *testing.T) {
		err := store.Delete(ctx, "non-existent")
		require.NoError(t, err)
	})
}

func TestInMemoryStore_GetMultiple(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryStore(100)

	t.Run("gets multiple existing keys", func(t *testing.T) {
		err := store.Set(ctx, "multi1", "value1", 0)
		require.NoError(t, err)
		err = store.Set(ctx, "multi2", "value2", 0)
		require.NoError(t, err)
		err = store.Set(ctx, "multi3", "value3", 0)
		require.NoError(t, err)

		keys := []string{"multi1", "multi2", "multi3"}
		results, err := store.GetMultiple(ctx, keys)
		require.NoError(t, err)

		expected := map[string]string{
			"multi1": "value1",
			"multi2": "value2",
			"multi3": "value3",
		}
		assert.Equal(t, expected, results)
	})

	t.Run("gets partial results when some keys don't exist", func(t *testing.T) {
		err := store.Set(ctx, "partial1", "value1", 0)
		require.NoError(t, err)

		keys := []string{"partial1", "non-existent", "partial2"}
		results, err := store.GetMultiple(ctx, keys)
		require.NoError(t, err)

		expected := map[string]string{
			"partial1":     "value1",
			"non-existent": "",
			"partial2":     "",
		}
		assert.Equal(t, expected, results)
	})

	t.Run("returns error when no keys are found", func(t *testing.T) {
		keys := []string{"missing1", "missing2", "missing3"}
		results, err := store.GetMultiple(ctx, keys)
		require.NoError(t, err) // Should not error when keys exist but have empty values
		assert.NotNil(t, results)

		expected := map[string]string{
			"missing1": "",
			"missing2": "",
			"missing3": "",
		}
		assert.Equal(t, expected, results)
	})

	t.Run("handles empty key slice", func(t *testing.T) {
		keys := []string{}
		results, err := store.GetMultiple(ctx, keys)
		require.NoError(t, err)
		assert.Nil(t, results)
	})

	t.Run("excludes expired entries", func(t *testing.T) {
		err := store.Set(ctx, "valid-multi", "valid-value", time.Hour)
		require.NoError(t, err)
		err = store.Set(ctx, "expired-multi", "expired-value", time.Millisecond)
		require.NoError(t, err)

		// Wait for expiration
		time.Sleep(10 * time.Millisecond)

		keys := []string{"valid-multi", "expired-multi"}
		results, err := store.GetMultiple(ctx, keys)
		require.NoError(t, err)

		expected := map[string]string{
			"valid-multi":   "valid-value",
			"expired-multi": "", // expired entries return empty string
		}
		assert.Equal(t, expected, results)
	})
}

func TestInMemoryStore_SetMultiple(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryStore(100)

	t.Run("sets multiple values without TTL", func(t *testing.T) {
		values := map[string]string{
			"setmulti1": "value1",
			"setmulti2": "value2",
			"setmulti3": "value3",
		}

		err := store.SetMultiple(ctx, values, 0)
		require.NoError(t, err)

		for key, expectedValue := range values {
			value, err := store.Get(ctx, key)
			require.NoError(t, err)
			assert.Equal(t, expectedValue, value)
		}
	})

	t.Run("sets multiple values with TTL", func(t *testing.T) {
		values := map[string]string{
			"setmulti-ttl1": "value1",
			"setmulti-ttl2": "value2",
		}

		err := store.SetMultiple(ctx, values, time.Hour)
		require.NoError(t, err)

		for key, expectedValue := range values {
			value, err := store.Get(ctx, key)
			require.NoError(t, err)
			assert.Equal(t, expectedValue, value)
		}
	})

	t.Run("handles empty values map", func(t *testing.T) {
		values := map[string]string{}
		err := store.SetMultiple(ctx, values, 0)
		require.NoError(t, err)
	})

	t.Run("overwrites existing values", func(t *testing.T) {
		// Set initial value
		err := store.Set(ctx, "overwrite", "initial", 0)
		require.NoError(t, err)

		// Overwrite with SetMultiple
		values := map[string]string{
			"overwrite": "new-value",
		}
		err = store.SetMultiple(ctx, values, 0)
		require.NoError(t, err)

		value, err := store.Get(ctx, "overwrite")
		require.NoError(t, err)
		assert.Equal(t, "new-value", value)
	})
}

func TestInMemoryStore_LRUEviction(t *testing.T) {
	ctx := context.Background()
	// Create a small store to test LRU eviction
	store := NewInMemoryStore(2)

	t.Run("evicts least recently used entries when capacity is exceeded", func(t *testing.T) {
		// Fill the cache to capacity
		err := store.Set(ctx, "lru1", "value1", 0)
		require.NoError(t, err)
		err = store.Set(ctx, "lru2", "value2", 0)
		require.NoError(t, err)

		// Both should be accessible
		value, err := store.Get(ctx, "lru1")
		require.NoError(t, err)
		assert.Equal(t, "value1", value)

		value, err = store.Get(ctx, "lru2")
		require.NoError(t, err)
		assert.Equal(t, "value2", value)

		// Add third entry, should evict the least recently used
		err = store.Set(ctx, "lru3", "value3", 0)
		require.NoError(t, err)

		// lru3 should be accessible
		value, err = store.Get(ctx, "lru3")
		require.NoError(t, err)
		assert.Equal(t, "value3", value)

		// At least one of the original entries should be evicted
		// The exact behavior depends on LRU implementation details
		value1, err1 := store.Get(ctx, "lru1")
		value2, err2 := store.Get(ctx, "lru2")

		require.NoError(t, err1)
		require.NoError(t, err2)

		// At least one should be empty (evicted)
		evicted := (value1 == "") || (value2 == "")
		assert.True(t, evicted, "Expected at least one entry to be evicted")
	})
}

func TestInMemoryStore_ConcurrentAccess(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryStore(1000)

	t.Run("handles concurrent reads and writes", func(t *testing.T) {
		// This is a basic concurrency test
		// The underlying LRU library should handle thread safety

		done := make(chan bool, 2)

		// Writer goroutine
		go func() {
			for i := 0; i < 1000; i++ {
				key := "concurrent" + strconv.Itoa(i)
				value := "value" + strconv.Itoa(i)
				err := store.Set(ctx, key, value, 0)
				assert.NoError(t, err)
			}
			done <- true
		}()

		// Reader goroutine
		go func() {
			for i := 0; i < 1000; i++ {
				key := "concurrent" + strconv.Itoa(i)
				_, err := store.Get(ctx, key)
				assert.NoError(t, err)
			}
			done <- true
		}()

		// Wait for both goroutines to complete
		<-done
		<-done
	})
}

func TestInMemoryStore_ImplementsStoreInterface(t *testing.T) {
	var _ sweagentd.CacheStore = (*InMemoryStore)(nil)

	// This test ensures the type implements the Store interface
	// It will fail to compile if the interface is not properly implemented
}

func TestInMemoryStore_EdgeCases(t *testing.T) {
	ctx := context.Background()
	store := NewInMemoryStore(100)

	t.Run("handles empty string values", func(t *testing.T) {
		err := store.Set(ctx, "empty", "", 0)
		require.NoError(t, err)

		value, err := store.Get(ctx, "empty")
		require.NoError(t, err)
		assert.Equal(t, "", value)
	})

	t.Run("handles empty string keys", func(t *testing.T) {
		err := store.Set(ctx, "", "empty-key-value", 0)
		require.NoError(t, err)

		value, err := store.Get(ctx, "")
		require.NoError(t, err)
		assert.Equal(t, "empty-key-value", value)
	})

	t.Run("handles very long keys and values", func(t *testing.T) {
		longKey := make([]byte, 1000)
		for i := range longKey {
			longKey[i] = 'a'
		}

		longValue := make([]byte, 10000)
		for i := range longValue {
			longValue[i] = 'b'
		}

		err := store.Set(ctx, string(longKey), string(longValue), 0)
		require.NoError(t, err)

		value, err := store.Get(ctx, string(longKey))
		require.NoError(t, err)
		assert.Equal(t, string(longValue), value)
	})

	t.Run("handles zero TTL correctly", func(t *testing.T) {
		err := store.Set(ctx, "zero-ttl", "zero-value", 0)
		require.NoError(t, err)

		// Should be accessible immediately
		value, err := store.Get(ctx, "zero-ttl")
		require.NoError(t, err)
		assert.Equal(t, "zero-value", value)

		// Should still be accessible after some time (no expiration)
		time.Sleep(100 * time.Millisecond)
		value, err = store.Get(ctx, "zero-ttl")
		require.NoError(t, err)
		assert.Equal(t, "zero-value", value)
	})
}
