package sweagentd

import (
	"context"
	"time"
)

// Inspired by https://github.com/github/copilot-api/blob/main/pkg/cache/cache.go

// CacheStore represents a name/value cache store.
type CacheStore interface {
	// Get retrieves a value from the cache.
	Get(ctx context.Context, key string) (string, error)
	// Set sets a value in the cache with an optional TTL.
	Set(ctx context.Context, key, value string, exp time.Duration) error
	// GetMultiple retrieves multiple values from the cache.
	GetMultiple(ctx context.Context, keys []string) (map[string]string, error)
	// SetMultiple sets multiple values in the cache with an optional TTL.
	SetMultiple(ctx context.Context, values map[string]string, ttl time.Duration) error
	// Delete removes a value from the cache.
	Delete(ctx context.Context, key string) error
}
