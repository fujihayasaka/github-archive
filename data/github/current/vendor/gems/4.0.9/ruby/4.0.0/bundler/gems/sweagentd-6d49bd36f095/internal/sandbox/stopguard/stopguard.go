// Package stopguard provides a small wrapper around the cache store that
// tracks the "current generation" of pending stop-agent-compute jobs per
// compute ID. Each StopAgentCompute Twirp request increments the generation
// for its compute ID; the delayed job records the generation it was created
// with and only executes if it still matches the current generation when it
// fires.
//
// This lets a subsequent StopAgentCompute call for the same compute ID
// supersede an earlier, still-pending stop request without needing Aqueduct
// to support cancelling individual scheduled jobs.
package stopguard

import (
	"fmt"
	"strconv"
	"time"

	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/goerrors"
)

// DefaultTTL is the default TTL for the per-compute generation key. It must
// comfortably exceed the scheduled stop delay so that an in-flight job can
// still find its generation when it fires.
const DefaultTTL = 1 * time.Hour

// Guard tracks the active stop-agent-compute generation per compute ID via
// the cache store.
type Guard struct {
	store cache.Store
	ttl   time.Duration
}

// New returns a Guard backed by the provided cache store. ttl controls the
// expiry of the generation key; pass [DefaultTTL] unless you have a reason
// not to.
func New(store cache.Store, ttl time.Duration) *Guard {
	if ttl <= 0 {
		ttl = DefaultTTL
	}
	return &Guard{store: store, ttl: ttl}
}

func key(computeID string) string {
	return fmt.Sprintf("stop-agent-compute:gen:%s", computeID)
}

// Record atomically increments the generation for the given compute ID and
// returns the new value. The returned generation must be embedded in the
// scheduled stop job so that the handler can verify it is still current.
func (g *Guard) Record(computeID string) (int64, error) {
	if g == nil || g.store == nil {
		return 0, goerrors.New("stopguard: store not configured")
	}
	val, ok := g.store.Incr(key(computeID), 1, g.ttl)
	if !ok {
		return 0, goerrors.Errorf("stopguard: failed to increment generation for compute %q", computeID)
	}
	return val, nil
}

// IsCurrent returns true if generation matches the current generation
// recorded for computeID. A missing/unreadable key is treated as not-current
// to avoid acting on stale jobs after the key has expired.
func (g *Guard) IsCurrent(computeID string, generation int64) bool {
	if g == nil || g.store == nil {
		return false
	}
	raw, found := g.store.Get(key(computeID))
	if !found {
		return false
	}
	current, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return false
	}
	return current == generation
}
