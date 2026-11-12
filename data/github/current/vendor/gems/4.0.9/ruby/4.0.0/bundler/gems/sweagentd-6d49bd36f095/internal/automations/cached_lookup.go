package automations

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/github/go-stats"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/hashicorp/golang-lru/v2/expirable"
	"golang.org/x/sync/singleflight"
)

// CachedLookup wraps another Lookup with an in-memory LRU cache for
// HasActiveForEvent results.
type CachedLookup struct {
	inner Lookup
	cache *expirable.LRU[string, bool]
	group singleflight.Group
	stats Stats
}

// Stats reports cache hit/miss telemetry.
type Stats interface {
	Increment(ctx context.Context, key string, tags stats.Tags)
}

// NewCachedLookup returns a Lookup that caches HasActiveForEvent results.
func NewCachedLookup(inner Lookup, size int, ttl time.Duration) *CachedLookup {
	if inner == nil {
		return nil
	}
	return &CachedLookup{
		inner: inner,
		cache: expirable.NewLRU[string, bool](size, nil, ttl),
	}
}

// WithStats attaches a stats reporter.
func (c *CachedLookup) WithStats(s Stats) *CachedLookup {
	if c == nil {
		return nil
	}
	c.stats = s
	return c
}

// HasActiveForEvent returns the cached result if present and unexpired.
func (c *CachedLookup) HasActiveForEvent(ctx context.Context, req EventMatchRequest) (bool, error) {
	key := cacheKey(req)
	tags := stats.Tags{"event": string(req.EventName)}

	if v, ok := c.cache.Get(key); ok {
		c.incr(ctx, "automations.lookup.cache_hit", tags)
		return v, nil
	}

	v, err, shared := c.group.Do(key, func() (any, error) {
		if cached, ok := c.cache.Get(key); ok {
			return cached, nil
		}
		result, lookupErr := c.inner.HasActiveForEvent(ctx, req)
		if lookupErr != nil {
			return false, lookupErr
		}
		c.cache.Add(key, result)
		return result, nil
	})
	if err != nil {
		c.incr(ctx, "automations.lookup.cache_error", tags)
		return false, err
	}
	if shared {
		c.incr(ctx, "automations.lookup.cache_shared", tags)
	} else {
		c.incr(ctx, "automations.lookup.cache_miss", tags)
	}
	result, _ := v.(bool)
	return result, nil
}

// ListForEvent passes through to the wrapped Lookup. Caching the resulting
// RuntimeConfig slice would require careful invalidation; leaving it uncached
// in this first pass.
func (c *CachedLookup) ListForEvent(ctx context.Context, req ListForEventRequest) ([]RuntimeConfig, error) {
	return c.inner.ListForEvent(ctx, req)
}

// AutomationsDisabledFromConfig passes through to the wrapped Lookup.
func (c *CachedLookup) AutomationsDisabledFromConfig(ctx context.Context, cfg *sweagentdtwirp.ConfigurationForRepositoryResponse, repoID int64, triggerType string) bool {
	return c.inner.AutomationsDisabledFromConfig(ctx, cfg, repoID, triggerType)
}

// InvalidateRepo removes all cache entries for the given repository.
func (c *CachedLookup) InvalidateRepo(repoID int64) {
	if c == nil || c.cache == nil {
		return
	}
	prefix := fmt.Sprintf("%d|", repoID)
	for _, k := range c.cache.Keys() {
		if strings.HasPrefix(k, prefix) {
			c.cache.Remove(k)
		}
	}
	c.incr(context.Background(), "automations.lookup.cache_invalidate", nil)
}

// Purge clears the entire cache.
func (c *CachedLookup) Purge() {
	if c == nil || c.cache == nil {
		return
	}
	c.cache.Purge()
}

func (c *CachedLookup) incr(ctx context.Context, key string, tags stats.Tags) {
	if c == nil || c.stats == nil {
		return
	}
	c.stats.Increment(ctx, key, tags)
}

// cacheKey is the canonical key for the LRU.
func cacheKey(req EventMatchRequest) string {
	return fmt.Sprintf("%d|%s|%s|%s", req.RepoID, req.EventName, req.ActivityType, req.WorkflowConclusion)
}
