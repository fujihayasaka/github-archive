package cache

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestTTLCache(t *testing.T) {
	cache := NewTTLCache[int, string](10 * time.Second)

	var now time.Time
	cache.now = func() time.Time { return now }

	// initially the cache is empty
	now = time.Now()
	_, ok := cache.Get(1)
	require.False(t, ok)

	// insert an entry for 2
	now = now.Add(3 * time.Second)
	cache.Insert(2, "two")

	// get cached entry for 2
	now = now.Add(5 * time.Second)
	value, ok := cache.Get(2)
	require.True(t, ok)
	require.Equal(t, "two", value)

	// insert entry for 1
	now = now.Add(5 * time.Second)
	cache.Insert(1, "one")

	// get cached entry for 1
	now = now.Add(2 * time.Second)
	value, ok = cache.Get(1)
	require.True(t, ok)
	require.Equal(t, "one", value)

	// entry for 2 has expired
	now = now.Add(2 * time.Second)
	_, ok = cache.Get(2)
	require.False(t, ok)
}
