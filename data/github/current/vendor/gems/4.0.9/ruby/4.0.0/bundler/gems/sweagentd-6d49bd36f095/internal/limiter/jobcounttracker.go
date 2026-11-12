package limiter

import (
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/github/sweagentd/internal/cache"
	"github.com/hashicorp/golang-lru/v2/expirable"
)

type jobCountTracker interface {
	Get(actor int64, status status) (int, bool)
	Set(actor int64, status status, value int, ttl time.Duration)
	Incr(actor int64, status status, delta int, ttl time.Duration) int
	Decr(actor int64, status status, delta int, ttl time.Duration) int
}

// JobCountMemoryTracker is an in-memory implementation of jobCountTracker.
type JobCountMemoryTracker struct {
	jobsMu sync.RWMutex
	jobs   *expirable.LRU[int64, *jobCount]
}

// NewJobCountMemoryTracker creates a new in-memory job count tracker with the specified size and TTL.
func NewJobCountMemoryTracker(size int, ttl time.Duration) *JobCountMemoryTracker {
	return &JobCountMemoryTracker{
		jobs: expirable.NewLRU[int64, *jobCount](size, nil, ttl),
	}
}

// Get retrieves the job count for the given actor and status.
func (j *JobCountMemoryTracker) Get(actor int64, status status) (int, bool) {
	j.jobsMu.RLock() // read lock
	defer j.jobsMu.RUnlock()

	if jc, ok := j.jobs.Get(actor); ok {
		if !jc.refresh() {
			return jc.get(status), true
		}
	}

	return 0, false
}

// Set sets the job count for the given actor and status.
func (j *JobCountMemoryTracker) Set(actor int64, status status, value int, ttl time.Duration) {
	j.jobsMu.Lock()
	defer j.jobsMu.Unlock()

	jc, ok := j.jobs.Get(actor)
	if !ok {
		jc = &jobCount{}
		j.jobs.Add(actor, jc) // ttl is ignored for memory tracker
	}

	switch status {
	case queued:
		jc.set(value, jc.running)
	case running:
		jc.set(jc.queued, value)
	default:
		// no-op for unknown status
	}
}

// Incr increments the job count for the given actor and status.
func (j *JobCountMemoryTracker) Incr(actor int64, status status, delta int, _ time.Duration) int {
	j.jobsMu.Lock()
	defer j.jobsMu.Unlock()

	jc, ok := j.jobs.Get(actor)
	if !ok {
		return 0 // not tracking count yet
	}

	jc.increment(status, delta)
	return jc.get(status)
}

// Decr decrements the job count for the given actor and status.
func (j *JobCountMemoryTracker) Decr(actor int64, status status, delta int, _ time.Duration) int {
	j.jobsMu.Lock()
	defer j.jobsMu.Unlock()

	jc, ok := j.jobs.Get(actor)
	if !ok {
		return 0 // not tracking count yet
	}

	jc.decrement(status, delta)
	return jc.get(status)
}

// JobCountRedisTracker is a Redis-backed implementation of jobCountTracker.
type JobCountRedisTracker struct {
	store cache.Store
}

// NewJobCountRedisTracker creates a new Redis-backed job count tracker.
func NewJobCountRedisTracker(store cache.Store) *JobCountRedisTracker {
	return &JobCountRedisTracker{
		store: store,
	}
}

func jobCountKey(actor int64, status status) string {
	return fmt.Sprintf("joblimiter:actor:%d:status:%s", actor, status.String())
}

// Get retrieves the job count for the given actor and status from Redis.
func (r *JobCountRedisTracker) Get(actor int64, status status) (int, bool) {
	key := jobCountKey(actor, status)
	valStr, ok := r.store.Get(key)
	if !ok {
		return 0, false
	}
	count, err := strconv.Atoi(valStr)
	if err != nil {
		return 0, false
	}
	return count, true
}

// Set sets the job count for the given actor and status in Redis.
func (r *JobCountRedisTracker) Set(actor int64, status status, value int, ttl time.Duration) {
	key := jobCountKey(actor, status)
	r.store.Set(key, strconv.Itoa(value), ttl)
}

// Incr increments the job count for the given actor and status in Redis.
func (r *JobCountRedisTracker) Incr(actor int64, status status, delta int, ttl time.Duration) int {
	key := jobCountKey(actor, status)
	newVal, ok := r.store.Incr(key, int64(delta), ttl)
	if !ok {
		return 0
	}
	return int(newVal)
}

// Decr decrements the job count for the given actor and status in Redis.
func (r *JobCountRedisTracker) Decr(actor int64, status status, delta int, ttl time.Duration) int {
	key := jobCountKey(actor, status)
	newVal, ok := r.store.Decr(key, int64(delta), ttl)
	if !ok {
		return 0
	}
	return int(newVal)
}
