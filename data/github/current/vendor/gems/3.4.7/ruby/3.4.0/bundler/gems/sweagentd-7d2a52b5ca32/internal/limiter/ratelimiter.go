package limiter

import (
	"context"
	"fmt"
	"maps"
	"sync"
	"time"

	"github.com/hashicorp/golang-lru/v2/expirable"
)

type client interface {
	RateLimitsForRepo(ctx context.Context, ownerID, repoID int64) (map[uint8]Rate, error)
}

type RateLimiter interface {
	WaitToReceive(context.Context) (time.Duration, bool)
	SetSecondaryRateLimitReset(context.Context, time.Time)
	SetRate(context.Context, string, uint8, Rate)
	DelayProcessing(ctx context.Context, ownerID, repoID int64, categories ...uint8) (time.Duration, bool)
	GetRate(context.Context, string, uint8) (*Rate, bool)
}

// Make sure RateLimiterV1 implements RateLimiter
var _ RateLimiter = (*RateLimiterV1)(nil)

type RateLimiterV1 struct {
	client                  client
	resetMu                 sync.Mutex
	secondaryRateLimitReset time.Time
	rateLimitsMu            sync.RWMutex
	rateLimits              *expirable.LRU[string, map[uint8]Rate] // [target]map[category]Rate
}

func NewRateLimiterV1(client client, size int, ttl time.Duration) *RateLimiterV1 {
	// create an expirable LRU cache with the given size (max entries) and ttl
	return &RateLimiterV1{
		client:     client,
		rateLimits: expirable.NewLRU[string, map[uint8]Rate](size, nil, ttl),
	}
}

// WaitToReceive checks if the rate limiter is currently in a secondary (global)
// rate limited state. If it is, it returns the duration to wait until the secondary
// rate limit resets. If not, it returns 0 and false.
//
// This is used to delay processing until the secondary rate limit allows it.
//
// The secondary rate limit is a global limit that spans all installations and
// actors. If the secondary rate limit is exceeded, the the caller should wait
// until the reset time before making additional requests or receiving jobs.
// It may make sense to sleep or block during this time, as it is a global limit
// that affects all installations and actors
func (l *RateLimiterV1) WaitToReceive(ctx context.Context) (time.Duration, bool) {
	l.resetMu.Lock()
	defer l.resetMu.Unlock()

	// If we have a secondary rate limit reset time set and it's in the future, we need to wait.
	if !l.secondaryRateLimitReset.IsZero() {
		if time.Now().Before(l.secondaryRateLimitReset) {
			return time.Until(l.secondaryRateLimitReset), true
		}
		// If the reset time has passed, clear it.
		l.secondaryRateLimitReset = time.Time{}
	}

	return 0, false
}

func (l *RateLimiterV1) SetSecondaryRateLimitReset(ctx context.Context, resetTime time.Time) {
	l.resetMu.Lock()
	defer l.resetMu.Unlock()

	// Set the secondary rate limit reset time.
	l.secondaryRateLimitReset = resetTime
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
// To only check the primary rate limits, use [WaitToReceive] instead.
func (l *RateLimiterV1) DelayProcessing(ctx context.Context, ownerID, repoID int64, categories ...uint8) (time.Duration, bool) {
	buffer := time.Second

	// Check secondary rate limit first
	l.resetMu.Lock()
	if !l.secondaryRateLimitReset.IsZero() {
		if time.Now().Before(l.secondaryRateLimitReset) {
			delay := time.Until(l.secondaryRateLimitReset)
			l.resetMu.Unlock()
			return delay + buffer, true
		}
		// If the reset time has passed, clear it
		l.secondaryRateLimitReset = time.Time{}
	}
	l.resetMu.Unlock()

	// Check primary rate limits
	target := TargetForOwnerID(ownerID)

	l.rateLimitsMu.RLock() // read lock
	if rates, ok := l.rateLimits.Get(target); ok {
		delay := delayForCategories(rates, categories...)
		l.rateLimitsMu.RUnlock() // unlock

		if delay > 0 {
			return delay + buffer, true
		}
		return 0, false
	}
	l.rateLimitsMu.RUnlock() // ensure unlock

	rates, err := l.client.RateLimitsForRepo(ctx, ownerID, repoID)
	if err != nil {
		return 0, false
	}

	l.rateLimitsMu.Lock()         // write lock
	defer l.rateLimitsMu.Unlock() // ensure unlock

	l.rateLimits.Add(target, rates)
	delay := delayForCategories(rates, categories...)
	if delay > 0 {
		return delay + buffer, true
	}
	return 0, false
}

func (l *RateLimiterV1) GetRate(ctx context.Context, target string, category uint8) (*Rate, bool) {
	l.rateLimitsMu.RLock()
	defer l.rateLimitsMu.RUnlock()

	rates, ok := l.rateLimits.Get(target)
	if !ok {
		return nil, false
	}

	rate, ok := rates[category]
	if !ok {
		return nil, false
	}

	return &rate, true
}

func (l *RateLimiterV1) GetRates(ctx context.Context, target string, categories ...uint8) (map[uint8]Rate, bool) {
	l.rateLimitsMu.RLock()
	defer l.rateLimitsMu.RUnlock()

	rates, ok := l.rateLimits.Get(target)
	if !ok {
		return nil, false
	}

	result := make(map[uint8]Rate, len(categories))
	for _, category := range categories {
		if rate, ok := rates[category]; ok {
			result[category] = rate
		}
	}

	return result, len(result) > 0
}

func (l *RateLimiterV1) SetRate(ctx context.Context, target string, category uint8, rate Rate) {
	l.rateLimitsMu.Lock()
	defer l.rateLimitsMu.Unlock()

	rates, ok := l.rateLimits.Get(target)
	if !ok {
		rates = make(map[uint8]Rate)
	}

	rates[category] = rate
	l.rateLimits.Add(target, rates)
}

func (l *RateLimiterV1) SetRates(ctx context.Context, target string, categories map[uint8]Rate) {
	l.rateLimitsMu.Lock()
	defer l.rateLimitsMu.Unlock()

	rates, ok := l.rateLimits.Get(target)
	if !ok {
		rates = make(map[uint8]Rate)
	}

	maps.Copy(rates, categories)

	l.rateLimits.Add(target, rates)
}

func TargetForOwnerID(ownerID int64) string {
	return fmt.Sprintf("owner:id:%d", ownerID)
}

func TargetForOwnerName(ownerName string) string {
	return fmt.Sprintf("owner:name:%s", ownerName)
}

func TargetForUserID(userID int64) string {
	return fmt.Sprintf("user:id:%d", userID)
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
