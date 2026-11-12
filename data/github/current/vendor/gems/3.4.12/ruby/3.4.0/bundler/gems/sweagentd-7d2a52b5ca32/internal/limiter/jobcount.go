package limiter

import (
	"sync"
	"time"
)

type status int

const (
	queued status = iota
	running
)

type jobCount struct {
	mu sync.RWMutex

	// running is the number of running jobs for this actor.
	running int
	// queued is the number of queued jobs for this actor.
	queued int
	// updated is the time when the running count was last updated by a refresh,
	// increment, or decrement.
	updated time.Time
	// refreshed is the time when the running count was last set from the database.
	refreshed time.Time
	// updates is the number of times the running count has been updated by increment
	// or decrement operations since the last refresh.
	updates int
}

func (jc *jobCount) increment(status status) {
	jc.mu.Lock()
	defer jc.mu.Unlock()

	switch status {
	case queued:
		jc.queued++
	case running:
		jc.running++
	default:
		return // shouldn't happen
	}

	jc.updated = time.Now()
	jc.updates++
}

func (jc *jobCount) decrement(status status) {
	jc.mu.Lock()
	defer jc.mu.Unlock()

	switch status {
	case queued:
		if jc.queued <= 0 {
			return // don't decrement below 0
		}
		jc.queued--
	case running:
		if jc.running <= 0 {
			return // don't decrement below 0
		}
		jc.running--
	default:
		return // shouldn't happen
	}

	jc.updated = time.Now()
	jc.updates++
}

func (jc *jobCount) set(queued, running int) {
	jc.mu.Lock()
	defer jc.mu.Unlock()

	jc.queued = queued
	jc.running = running

	jc.updated = time.Now()
	jc.refreshed = jc.updated // Set refreshed to the same time as updated
	jc.updates = 0            // Reset updates since we set the count directly
}

// refresh checks if the jobCount needs to be refreshed based on the current
// running count and the last update times. It returns true if a refresh from
// the database (source of truth) is needed, false otherwise.
func (jc *jobCount) refresh() bool {
	jc.mu.RLock()
	defer jc.mu.RUnlock()

	if jc.refreshed.IsZero() {
		// If we never refreshed (pulled the count from the db), refresh it now.
		//
		// We don't add new jobCount entries to the cache when we increment or
		// decrement, so the only time refreshed will be zero is when we first
		// create the jobCount entry then called [refresh] for the first time.
		return true
	}

	if jc.refreshed.Equal(jc.updated) {
		// If the last update was a refresh, we haven't incremented or decremented
		// the count since the last refresh, so we don't need to refresh again.
		return false
	}

	if jc.updates > 3 {
		// if we've incremented or decremented more than 3 times since the last
		// refresh, we should refresh to ensure the count is accurate.
		return true // refresh if we've incremented/decremented more than 3 times
	}

	if MaxRunningJobs-jc.running <= 3 || MaxQueuedJobs-jc.queued <= 10 {
		return true // refresh if the count is close to the max
	}

	return false
}

// get returns the current count for the given status in a thread-safe manner
func (jc *jobCount) get(status status) int {
	jc.mu.RLock()
	defer jc.mu.RUnlock()

	switch status {
	case queued:
		return jc.queued
	case running:
		return jc.running
	default:
		return 0 // shouldn't happen
	}
}
