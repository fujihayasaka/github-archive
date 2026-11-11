package cache

import (
	"context"
	"time"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/hashicorp/golang-lru/v2/expirable"
)

// InMemoryStore is a memory-based implementation of the Store interface.
type InMemoryStore struct {
	store *expirable.LRU[string, *cacheEntry]
}

var _ sweagentd.CacheStore = (*InMemoryStore)(nil)

type cacheEntry struct {
	value     string
	expiresAt time.Time
}

// NewInMemoryStore creates an in-memory cache with the provided maximum size.
// TTL is handled per-entry (provided to Set). The underlying LRU enforces the
// maximum size; expired entries are purged on access.
func NewInMemoryStore(maxSize int) *InMemoryStore {
	if maxSize <= 0 {
		maxSize = 4000
	}

	lru := expirable.NewLRU[string, *cacheEntry](maxSize, nil, 0)
	return &InMemoryStore{store: lru}
}

// Get retrieves a value from the cache.
func (m *InMemoryStore) Get(ctx context.Context, key string) (string, error) {
	entry, ok := m.store.Get(key)
	if !ok || entry == nil {
		return "", nil
	}

	if entry.expiresAt.IsZero() || time.Now().Before(entry.expiresAt) {
		return entry.value, nil
	}

	m.store.Remove(key)
	return "", nil
}

// Set sets a value in the cache with an optional TTL.
func (m *InMemoryStore) Set(ctx context.Context, key, value string, ttl time.Duration) error {
	var expiresAt time.Time
	if ttl > 0 {
		expiresAt = time.Now().Add(ttl)
	}
	entry := &cacheEntry{value: value, expiresAt: expiresAt}
	m.store.Add(key, entry)
	return nil
}

// GetMultiple retrieves multiple values from the cache.
func (m *InMemoryStore) GetMultiple(ctx context.Context, keys []string) (map[string]string, error) {
	results := make(map[string]string)
	for _, key := range keys {
		value, err := m.Get(ctx, key)
		if err == nil {
			results[key] = value
		}
	}

	if len(results) < 1 {
		return nil, nil
	}

	return results, nil
}

// SetMultiple sets multiple values in the cache with an optional TTL.
func (m *InMemoryStore) SetMultiple(ctx context.Context, values map[string]string, ttl time.Duration) error {
	for key, value := range values {
		err := m.Set(ctx, key, value, ttl)
		if err != nil {
			return err
		}
	}
	return nil
}

// Delete removes a value from the cache.
func (m *InMemoryStore) Delete(ctx context.Context, key string) error {
	m.store.Remove(key)
	return nil
}
