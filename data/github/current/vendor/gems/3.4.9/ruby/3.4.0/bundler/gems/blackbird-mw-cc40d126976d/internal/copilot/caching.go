package copilot

import (
	"context"
	"time"

	"github.com/github/blackbird-mw/internal/cache"
)

// Wraps a copilot.Client and caches results up to the given TTL.
// The result is thread-safe if the wrapped client is thread-safe.
func NewCachingClient(client Client, ttl time.Duration) Client {
	if client == nil {
		return nil
	}
	return &cachingClient{
		client,
		cache.NewTTLCache[cacheKey, []float32](ttl),
	}
}

type cachingClient struct {
	Client
	cache cache.TTLCache[cacheKey, []float32]
}

type cacheKey struct {
	prompt     string
	userID     uint32
	model      string
	dimensions int
}

func (c *cachingClient) GetEmbedding(ctx context.Context, prompt string, userID uint32, model string, dimensions int) ([]float32, error) {
	key := cacheKey{prompt, userID, model, dimensions}
	if value, ok := c.cache.Get(key); ok {
		return value, nil
	}
	value, err := c.Client.GetEmbedding(ctx, prompt, userID, model, dimensions)
	if err != nil {
		return nil, err
	}
	c.cache.Insert(key, value)
	return value, nil
}
