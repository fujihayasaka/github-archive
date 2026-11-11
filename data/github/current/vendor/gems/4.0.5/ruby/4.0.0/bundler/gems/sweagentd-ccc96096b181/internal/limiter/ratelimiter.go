package limiter

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	secondaryRateLimitResetKey = "rate_limit:secondary_rate_limit_reset"
	primaryRateLimitsKey       = "rate_limit:primary_rate_limits"
)

// Client provides methods for retrieving rate limit information from external sources.
type Client interface {
	RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]Rate, error)
}

// RateLimiter provides methods for managing and checking rate limits.
type RateLimiter interface {
	WaitToReceive(ctx context.Context, appID int64) (time.Duration, bool)
	SetSecondaryRateLimitReset(ctx context.Context, appID int64, resetTime time.Time)
	SetRate(ctx context.Context, target sweagentd.ClientTarget, category uint8, rate Rate)
	DelayProcessing(ctx context.Context, appID, ownerID, repoID int64, categories ...uint8) (time.Duration, bool)
	GetRate(ctx context.Context, target sweagentd.ClientTarget, category uint8) (*Rate, bool)
}

// CacheRateLimiter is a cache-backed implementation of the RateLimiter interface.
// It uses an external cacheStore (e.g., Redis or in-memory) for storing rate limit data,
// making it suitable for distributed systems where rate limit state needs to be shared.
type CacheRateLimiter struct {
	client      Client
	obsv        observability.Exporters
	cacheStore  cache.Store
	appProvider *agenticapp.Provider
}

// Ensure CacheRateLimiter implements RateLimiter interface
var _ RateLimiter = (*CacheRateLimiter)(nil)

// NewCacheRateLimiter creates a new cache-backed rate limiter.
func NewCacheRateLimiter(client Client, obsv observability.Exporters, cacheStore cache.Store, appProvider *agenticapp.Provider) *CacheRateLimiter {
	return &CacheRateLimiter{
		client:      client,
		obsv:        obsv,
		cacheStore:  cacheStore,
		appProvider: appProvider,
	}
}

// WaitToReceive checks if the rate limiter is currently in a secondary (global)
// rate limited state. If it is, it returns the duration to wait until the secondary
// rate limit resets. If not, it returns 0 and false.
//
// This is used to delay processing until the secondary rate limit allows it.
//
// The secondary rate limit is a global limit that spans all installations and
// actors. If the secondary rate limit is exceeded, the caller should wait
// until the reset time before making additional requests or receiving jobs.
// It may make sense to sleep or block during this time, as it is a global limit
// that affects all installations and actors.
func (l *CacheRateLimiter) WaitToReceive(ctx context.Context, appID int64) (time.Duration, bool) {
	key := makeSecondaryKey(appID)
	value, ok := l.cacheStore.Get(key)
	if !ok || value == "" {
		return 0, false
	}

	secondaryRateLimitReset, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return 0, false
	}
	if !secondaryRateLimitReset.IsZero() {
		if time.Now().Before(secondaryRateLimitReset) {
			return time.Until(secondaryRateLimitReset), true
		}
	}

	return 0, false
}

// SetSecondaryRateLimitReset sets the reset time for the secondary (global) rate limit.
// The reset time is stored in the cache with a TTL that extends slightly beyond the reset time.
func (l *CacheRateLimiter) SetSecondaryRateLimitReset(ctx context.Context, appID int64, resetTime time.Time) {
	// Store the reset time in cache with a small buffer so readers see it.
	ttl := max(time.Until(resetTime.Add(5*time.Minute)), 0)

	key := makeSecondaryKey(appID)
	l.cacheStore.Set(key, resetTime.Format(time.RFC3339Nano), ttl)
}

// DelayProcessing checks the secondary (global) rate limit first, then the
// primary rate limits for the given target and categories. If either rate limit
// indicates that processing should be delayed, it returns the duration to wait
// and true. If not, it returns 0 and false.
//
// The secondary rate limit is a global limit that spans all installations and
// actors. The primary rate limits are specific to an installation or user.
//
// If either rate limit is exceeded, the caller should defer processing until
// the reset time before making additional requests.
//
// IMPORTANT: Callers should NOT block or sleep while waiting during this time,
// because this duration may be the result of a primary rate limit that affects
// only a single installation or actor. Blocking would prevent other installations
// or actors from being processed during this time. Instead, callers should
// re-queue the work to be processed later, allowing other work to continue
// processing in the meantime.
//
// To only check the secondary rate limits, use WaitToReceive instead.
func (l *CacheRateLimiter) DelayProcessing(ctx context.Context, appID, ownerID, repoID int64, categories ...uint8) (time.Duration, bool) {
	buffer := time.Second

	// Check secondary rate limit in cache first
	key := makeSecondaryKey(appID)
	if raw, ok := l.cacheStore.Get(key); ok && raw != "" {
		t, err := time.Parse(time.RFC3339Nano, raw)
		if err == nil {
			if time.Now().Before(t) {
				return time.Until(t) + buffer, true
			}
			// expired: clear
			l.cacheStore.Set(key, "", 0)
		}
	}

	app, err := l.appProvider.FindByID(appID)
	if err != nil {
		l.obsv.Logger.WithFields(
			kvp.Int64("app_id", appID),
			kvp.Int64("owner_id", ownerID),
			kvp.Int64("repo_id", repoID),
		).WithError(err).Error("DelayProcessing: failed to get app by ID")
		return 0, false
	}

	target := sweagentd.ClientTargetForInstallationByOwnerID(app.AppID(), ownerID)

	// Try to get primary rates from cache-backed GetRates
	if rates, ok := l.GetRates(ctx, target, categories...); ok {
		delay := delayForCategories(rates, categories...)
		if delay > 0 {
			return delay + buffer, true
		}
		return 0, false
	}

	// Fallback to client call
	rates, err := l.client.RateLimitsForRepo(ctx, app, ownerID, repoID)
	if err != nil {
		l.obsv.Logger.WithFields(
			kvp.Int64("app_id", appID),
			kvp.Int64("owner_id", ownerID),
			kvp.Int64("repo_id", repoID),
		).WithError(err).Error("DelayProcessing: failed to get rate limits")
		return 0, false
	}

	l.SetRates(ctx, target, rates)
	delay := delayForCategories(rates, categories...)
	if delay > 0 {
		return delay + buffer, true
	}
	return 0, false
}

// GetRate retrieves the rate limit for a specific target and category from the cache.
// Returns the rate and true if found, nil and false otherwise.
func (l *CacheRateLimiter) GetRate(ctx context.Context, target sweagentd.ClientTarget, category uint8) (*Rate, bool) {
	key := makeKey(target, category)
	raw, ok := l.cacheStore.Get(key)
	if !ok || raw == "" {
		return nil, false
	}

	var rate Rate
	err := json.Unmarshal([]byte(raw), &rate)
	if err != nil {
		// Log the error for debugging - invalid cached data should not be silently ignored
		l.obsv.Logger.WithFields(
			kvp.String("key", key),
		).WithError(err).Error("GetRate: failed to unmarshal rate from cache")
		return nil, false
	}

	return &rate, true
}

// SetRate stores a rate limit for a specific target and category in the cache.
// The rate is stored with a 4-hour TTL.
func (l *CacheRateLimiter) SetRate(ctx context.Context, target sweagentd.ClientTarget, category uint8, rate Rate) {
	key := makeKey(target, category)
	data, err := json.Marshal(rate)
	if err != nil {
		// Log marshal error - this indicates a programming error with the Rate struct
		l.obsv.Logger.WithFields(
			kvp.String("key", key),
		).WithError(err).Error("SetRate: failed to marshal rate")
		return
	}

	l.cacheStore.Set(key, string(data), time.Until(rate.Reset))
}

// GetRates retrieves multiple rate limits for a target across multiple categories.
// Returns a map of category to Rate and true if any rates were found, nil and false otherwise.
func (l *CacheRateLimiter) GetRates(ctx context.Context, target sweagentd.ClientTarget, categories ...uint8) (map[uint8]Rate, bool) {
	keys := make([]string, 0, len(categories))
	for _, category := range categories {
		key := makeKey(target, category)
		keys = append(keys, key)
	}
	kv, ok := l.cacheStore.GetMultiple(keys)
	if !ok {
		return nil, false
	}

	result := make(map[uint8]Rate, len(categories))
	for _, category := range categories {
		key := makeKey(target, category)
		if rate, ok := kv[key]; ok {
			var r Rate
			err := json.Unmarshal([]byte(rate), &r)
			if err != nil {
				// Log the error for debugging - skip this category if unmarshal fails
				l.obsv.Logger.WithFields(
					kvp.String("key", key),
				).WithError(err).Error("GetRates: failed to unmarshal rate from cache")
				continue
			}
			result[category] = r
		}
	}

	return result, len(result) > 0
}

// SetRates stores multiple rate limits for a target across multiple categories.
// All rates are stored with a 4-hour TTL.
func (l *CacheRateLimiter) SetRates(ctx context.Context, target sweagentd.ClientTarget, categories map[uint8]Rate) {
	kv := make(map[string]string)
	for category, rate := range categories {
		key := makeKey(target, category)
		data, err := json.Marshal(rate)
		if err != nil {
			l.obsv.Logger.WithFields(
				kvp.Uint8("category", category),
			).WithError(err).Error("SetRates: failed to marshal rate")
			continue
		}
		kv[key] = string(data)
	}

	l.cacheStore.SetMultiple(kv, 4*time.Hour)
}

func makeKey(target sweagentd.ClientTarget, category uint8) string {
	return fmt.Sprintf("%s:%s:%d", primaryRateLimitsKey, target.Key(), category)
}

func makeSecondaryKey(appID int64) string {
	return fmt.Sprintf("%s:app:%d", secondaryRateLimitResetKey, appID)
}

// delayForCategories checks the rate limits for the given categories and returns
// the maximum delay required for any of the categories.
func delayForCategories(rates map[uint8]Rate, categories ...uint8) time.Duration {
	if len(categories) == 0 {
		return 0
	}

	delay := time.Duration(0)
	for _, category := range categories {
		if rate, ok := rates[category]; ok {
			if until, limited := rate.IsLimited(); limited {
				delay = max(delay, until)
			}
		}
	}

	return delay
}
