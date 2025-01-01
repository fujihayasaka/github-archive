package rate

import (
	"context"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

type inMemoryRateLimiterOption func(*inMemoryRateLimiter)

func withResetFrequency(d time.Duration) inMemoryRateLimiterOption {
	return func(mrl *inMemoryRateLimiter) {
		mrl.resetFrequency = d
	}
}

type inMemoryRateLimiter struct {
	cache *sync.Map
	lock  *sync.RWMutex

	threshold uint64

	resetFrequency time.Duration
}

func newInMemoryRateLimiter(ctx context.Context, threshold uint64, opts ...inMemoryRateLimiterOption) *inMemoryRateLimiter {
	mrl := &inMemoryRateLimiter{
		cache: &sync.Map{},
		lock:  &sync.RWMutex{},

		threshold: threshold,

		resetFrequency: 15 * time.Minute,
	}

	for _, opt := range opts {
		opt(mrl)
	}

	go mrl.scanAndRemoveExpiredEntries(ctx)

	return mrl
}

func (mrl *inMemoryRateLimiter) scanAndRemoveExpiredEntries(ctx context.Context) {
	delay := time.NewTimer(mrl.resetFrequency)
	defer delay.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-delay.C:
			mrl.Reset()
			delay.Reset(mrl.resetFrequency)
		}
	}
}

func (mrl *inMemoryRateLimiter) Allow(_ context.Context, repoDatabaseID int64) bool {
	mrl.lock.RLock()

	needsUnlock := true
	defer func() {
		if needsUnlock {
			mrl.lock.RUnlock()
		}
	}()

	loaded, has := mrl.cache.Load(repoDatabaseID)
	if !has {
		// Upgrade to a write lock
		mrl.lock.RUnlock()
		needsUnlock = false
		mrl.lock.Lock()
		defer mrl.lock.Unlock()

		loaded = rate.NewLimiter(rate.Limit(mrl.threshold), int(mrl.threshold))
		mrl.cache.Store(repoDatabaseID, loaded)
	}

	e, _ := loaded.(*rate.Limiter)
	return e.Allow()
}

func (mrl *inMemoryRateLimiter) Reset() {
	mrl.lock.Lock()
	defer mrl.lock.Unlock()
	mrl.cache = &sync.Map{}
}
