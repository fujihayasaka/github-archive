package rate

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
)

type fallbackRateLimiter struct {
	obs               *observability.Observability
	remoteRateLimiter *redisRateLimiter
	localRateLimiter  *inMemoryRateLimiter
	lock              *sync.RWMutex
	useFallback       bool
	useDarkMode       bool

	redisClient                    redis.UniversalClient
	breaker                        *circuit.Breaker
	configChangeDetectionFrequency time.Duration
	keyPrefix                      string
}

var (
	defaultConfigSyncFrequency = 1 * time.Minute
)

const (
	sourceInMemory = "in_memory"
	sourceRedis    = "github_redis"

	tagSource        = "data_source"
	tagDarkMode      = "dark_mode"
	tagResult        = "is_allowed"
	tagRateLimitType = "rate_limit_type"
)

func newFallbackRateLimiter(
	ctx context.Context,
	obs *observability.Observability,
	redisClient redis.UniversalClient,
	breaker *circuit.Breaker,
	keyPrefix string,
	threshold uint64,
	windowSize int, //nolint:unparam // both queue build and webhook rate limiters use the same window size
	getOverride func(repoDatabaseID int64) (uint64, bool),
	opts ...RedisRateLimiterOption) *fallbackRateLimiter {

	rrl := newRedisRateLimiter(obs, redisClient, breaker, keyPrefix, threshold, windowSize, getOverride, opts...)

	eventSubscription := rrl.breaker.Subscribe()

	useDarkMode := rrl.useDarkMode

	// rate.Limiter used by in-memory is per-second, and our Redis rate limiter is per-10-seconds (window), so we'll adjust
	inMemoryThreshold := threshold / uint64(windowSize)

	frl := &fallbackRateLimiter{
		obs:               obs,
		remoteRateLimiter: rrl,
		localRateLimiter:  newInMemoryRateLimiter(ctx, inMemoryThreshold),
		lock:              &sync.RWMutex{},
		useFallback:       false,
		useDarkMode:       useDarkMode,

		redisClient:                    redisClient,
		breaker:                        breaker,
		configChangeDetectionFrequency: defaultConfigSyncFrequency,
		keyPrefix:                      keyPrefix,
	}

	go frl.listenForBreakerEvents(ctx, eventSubscription)
	go frl.detectConfigChanges(ctx)

	return frl
}

func (frl *fallbackRateLimiter) Allow(ctx context.Context, repoDatabaseID int64) bool {
	frl.lock.RLock()
	defer frl.lock.RUnlock()

	kvps := []kvp.Field{
		kvp.Int64("gh.repo.id", repoDatabaseID),
		kvp.Bool("gh.launch.rate_limit.dark_mode", frl.useDarkMode),
		kvp.String("gh.launch.rate_limit_type", frl.keyPrefix),
	}
	tags := statter.Tags{
		tagRateLimitType: frl.keyPrefix,
		tagSource:        sourceRedis,
		tagDarkMode:      strconv.FormatBool(frl.useDarkMode),
	}

	isAllowed := false
	defer func(allowed *bool, statterTags statter.Tags, kvpFields []kvp.Field) {
		statterTags[tagResult] = strconv.FormatBool(*allowed)
		frl.obs.Counter(ctx, "rate_limit.breaker.result", statterTags, 1)
		if !*allowed {
			frl.obs.Error(ctx, "exceeded rate limit thresholds", kvpFields...)
		}
	}(&isAllowed, tags, kvps)

	if frl.useFallback {
		tags[tagSource] = sourceInMemory
		isAllowed = frl.localRateLimiter.Allow(ctx, repoDatabaseID)
		if frl.useDarkMode {
			kvps = append(kvps, kvp.Bool("gh.launch.rate_limit.dark_mode.is_allowed", isAllowed))
			frl.obs.Debug(ctx, "launch redis rate limiter operating in dark mode", kvps...)
			if !isAllowed {
				frl.obs.Counter(ctx, "rate_limit.breaker.dark_mode_capture", tags, 1)
			}
			return true
		}
		return isAllowed
	}

	isAllowed = frl.remoteRateLimiter.Allow(ctx, repoDatabaseID)
	if frl.useDarkMode {
		kvps = append(kvps, kvp.Bool("gh.launch.rate_limit.dark_mode.is_allowed", isAllowed))
		frl.obs.Debug(ctx, "launch redis rate limiter operating in dark mode", kvps...)
		if !isAllowed {
			frl.obs.Counter(ctx, "rate_limit.breaker.dark_mode_capture", tags, 1)
		}
		return true
	}
	return isAllowed
}

func (frl *fallbackRateLimiter) listenForBreakerEvents(ctx context.Context, events <-chan circuit.BreakerEvent) {
	for {
		select {
		case <-ctx.Done():
			return
		case event := <-events:
			eventTag := "fail"
			if event == circuit.BreakerTripped {
				eventTag = "tripped"
			}
			if event == circuit.BreakerReset {
				eventTag = "reset"
			}
			if event == circuit.BreakerReady {
				eventTag = "ready"
			}

			frl.obs.Debug(ctx, "launch redis rate limiter received circuit breaker event", kvp.String("gh.launch.rate_limit.redis_event", eventTag))
			frl.obs.Counter(ctx, "rate_limit.breaker.event", statter.Tags{"event": eventTag}, 1)

			if event == circuit.BreakerFail {
				// We don't want to fallthrough after individual failures
				continue
			}

			if event == circuit.BreakerTripped {
				frl.lock.Lock()
				frl.useFallback = true
				frl.lock.Unlock()
			}

			if event == circuit.BreakerReady || event == circuit.BreakerReset {
				frl.lock.Lock()
				frl.useFallback = false
				frl.lock.Unlock()
			}
		}
	}
}

const (
	darkModeConfigKeyFormatter      = "%s:use_dark_mode"
	forceFallbackConfigKeyFormatter = "%s:use_in_memory"
)

func (frl *fallbackRateLimiter) detectConfigChanges(ctx context.Context) {
	delay := time.NewTimer(frl.configChangeDetectionFrequency)
	defer delay.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-delay.C:
			frl.checkForAndApplyConfigChanges(ctx)

			delay.Reset(frl.configChangeDetectionFrequency)
		}
	}
}

func (frl *fallbackRateLimiter) checkForAndApplyConfigChanges(ctx context.Context) {
	frl.lock.RLock()
	currentlyUsingDarkMode := frl.useDarkMode
	currentlyUsingInMemory := frl.useFallback
	frl.lock.RUnlock()

	shouldUseDarkMode := frl.setupFuncToGetConfigValue(ctx, darkModeConfigKeyFormatter, currentlyUsingDarkMode)

	shouldUseInMemory := frl.setupFuncToGetConfigValue(ctx, forceFallbackConfigKeyFormatter, currentlyUsingInMemory)

	// Do not grab a write lock if there is nothing to change
	if currentlyUsingDarkMode == shouldUseDarkMode && currentlyUsingInMemory == shouldUseInMemory {
		return
	}

	frl.lock.Lock()
	frl.useDarkMode = shouldUseDarkMode
	frl.remoteRateLimiter.useDarkMode = shouldUseDarkMode
	frl.useFallback = shouldUseInMemory
	frl.lock.Unlock()
}

func (frl *fallbackRateLimiter) setupFuncToGetConfigValue(ctx context.Context, formatter string, defaultValue bool) bool {
	resp := frl.redisClient.Get(ctx, fmt.Sprintf(formatter, frl.keyPrefix))
	if resp.Err() == redis.Nil {
		return defaultValue
	}
	if resp.Err() != nil {
		if resp.Err() != context.Canceled {
			frl.breaker.Fail()
		}
		return defaultValue
	}
	val, err := resp.Bool()
	if err != nil {
		return defaultValue
	}
	frl.breaker.Success()
	return val
}
