package cache

import (
	"fmt"
	"maps"
	"sync"
	"time"
)

// MemoryCacheStore is a simple in-memory implementation of the cacheStore interface.
// It is intended for development and testing environments where Redis is not available.
// Note: This implementation does not respect TTL values for simplicity.
type MemoryCacheStore struct {
	data map[string]string
	mu   sync.RWMutex
}

// NewMemoryCacheStore creates a new in-memory cache store.
func NewMemoryCacheStore() *MemoryCacheStore {
	return &MemoryCacheStore{
		data: make(map[string]string),
	}
}

// Get retrieves the value for a given key.
// Returns the value and true if found, empty string and false otherwise.
func (m *MemoryCacheStore) Get(key string) (string, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	val, ok := m.data[key]
	return val, ok
}

// Set stores a value for a given key.
// Note: The TTL parameter is ignored in this implementation.
func (m *MemoryCacheStore) Set(key, value string, ttl time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.data[key] = value
}

// GetMultiple retrieves values for multiple keys.
// Returns a map of found key-value pairs and true if any keys were found, false otherwise.
func (m *MemoryCacheStore) GetMultiple(keys []string) (map[string]string, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	result := make(map[string]string)
	anyFound := false

	for _, key := range keys {
		if val, ok := m.data[key]; ok {
			result[key] = val
			anyFound = true
		}
	}

	return result, anyFound
}

// SetMultiple stores multiple key-value pairs.
// Note: The TTL parameter is ignored in this implementation.
func (m *MemoryCacheStore) SetMultiple(values map[string]string, ttl time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()

	maps.Copy(m.data, values)
}

// Incr increments a numeric value for a given key by delta.
// Returns the new value and true if successful, 0 and false otherwise.
func (m *MemoryCacheStore) Incr(key string, delta int64, ttl time.Duration) (int64, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	val, ok := m.data[key]
	if !ok {
		m.data[key] = "0"
		val = "0"
	}

	var current int64
	_, err := fmt.Sscanf(val, "%d", &current)
	if err != nil {
		return 0, false
	}

	current += delta
	m.data[key] = fmt.Sprintf("%d", current)
	return current, true
}

// Decr decrements a numeric value for a given key by delta.
// Returns the new value and true if successful, 0 and false otherwise.
func (m *MemoryCacheStore) Decr(key string, delta int64, ttl time.Duration) (int64, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	val, ok := m.data[key]
	if !ok {
		m.data[key] = "0"
		val = "0"
	}

	var current int64
	_, err := fmt.Sscanf(val, "%d", &current)
	if err != nil {
		return 0, false
	}

	current -= delta
	if current < 0 {
		current = 0
	}
	m.data[key] = fmt.Sprintf("%d", current)
	return current, true
}

// TestClear removes all entries from the cache. Use only in testing.
func (m *MemoryCacheStore) TestClear() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.data = make(map[string]string)
	return nil
}
