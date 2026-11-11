package limiter

import (
	"context"
	"sync"
	"time"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/hashicorp/golang-lru/v2/expirable"
)

const (
	// MaxRunningJobs is the maximum number of jobs that can be running for a
	// single actor. If this limit is reached, the job will be delayed until
	// the number of running jobs falls below this limit.
	//
	// This limit is used to prevent an actor from overwhelming the system with
	// too many concurrent jobs.
	//
	// IMPORTANT: This is a soft limit. It is not guaranteed that the number of
	// running jobs will not exceed this limit, but it is a best effort to keep
	// the number of running jobs below this limit.
	MaxRunningJobs int = 9 // 9 jobs

	// MaxQueuedJobs is the maximum number of jobs that can be queued for a
	// single actor. If this limit is reached, new jobs will be rejected.
	//
	// This limit is used to prevent an actor from overwhelming the system with
	// too many queued jobs.
	//
	// IMPORTANT: This is a soft limit. It is not guaranteed that the number of
	// queued jobs will not exceed this limit, but it is a best effort to keep
	// the number of queued jobs below this limit.
	MaxQueuedJobs int = 100 // 100 jobs

	// JobRequeueDelay is the delay used when requeuing jobs.
	//
	// IMPORTANT: Make sure we always requeue jobs with the same delay. This
	// ensures jobs are processed in the same order they were received/requeued,
	// even if they are requeued multiple times. This is important for maintaining
	// the integrity of the job processing order, and prevents requeued jobs from
	// getting stuck behind other jobs that were received later.
	JobRequeueDelay time.Duration = 2 * time.Minute // 2 minutes

	// RecentJobWindow is the time window used to determine if a job is recent.
	// This is used to prevent counting old jobs that are no longer relevant or
	// stale in the system.
	RecentJobWindow time.Duration = 24 * time.Hour // 24 hours
)

type store interface {
	// GetRunningJobCountForActor(ctx context.Context, actor int64, window time.Duration) (int, error)
	GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration) (sweagentd.JobCounts, error)
}

// JobLimiter is responsible for limiting the number of concurrent jobs that can
// be running and queued for a single actor. It uses an in-memory cache to track
// the number of running and queued jobs for each actor, and refreshes this count
// from the database periodically to ensure it is up-to-date.
//
// We constrain the number of concurrently running jobs per actor, and to delay
// job processing when the limit is reached. This prevents the actor from hitting
// CAPI rate limits causing a cascading failure across their jobs.
//
// Additionally, we constrain the number of queued jobs per actor. This prevents
// an actor from overwhelming the system with too many queued jobs.
//
// IMPORTANT: The in-memory cache is not a source of truth. It is used to reduce
// the number of database queries and to provide a fast response for job processing.
// The source of truth is the database, which is queried when the in-memory cache
// needs to be refreshed.
//
// This implementation is best-effort and does not guarantee that the number of
// running and queued jobs will not exceed the limit. Each instance of JobLimiter
// is local to the pod, so it suffers from not being distributed across pods.
// This means that if multiple pods are running, they will each have their
// own in-memory cache and will not be aware of the other pods' running and queued
// job counts without querying the database.
//
// TODO (colbylwilliams) (ritchxu): We are working towards adding a distributed
// cache via Redis to the service. Once that is in place, we can replace the
// in-memory cache with a distributed cache that will be shared across all pods.
// This will allow us to have a single source of truth for the running job counts
// and will allow us to scale the service more effectively.
// For now, this implementation is sufficient for the current scale of the service.
type JobLimiter struct {
	store  store
	jobsMu sync.RWMutex
	jobs   *expirable.LRU[int64, *jobCount]
}

func NewJobLimiter(store store, size int, ttl time.Duration) *JobLimiter {
	return &JobLimiter{
		store: store,
		jobs:  expirable.NewLRU[int64, *jobCount](size, nil, ttl),
	}
}

// QueuedJobsExceeded returns true if the number of queued jobs for the actor
// has exceeded the maximum allowed. It checks the in-memory cache first, and
// if the cache is stale or missing, it refreshes the count from the database.
// If there is an error fetching the count from the database, it returns false
// to fail open and allow the job to be processed.
//
// Callers should return an error to the user if this method returns true,
// indicating that the actor has too many queued jobs.
func (l *JobLimiter) QueuedJobsExceeded(ctx context.Context, actor int64) bool {
	l.jobsMu.RLock() // read lock
	if jc, ok := l.jobs.Get(actor); ok {
		if !jc.refresh() {
			l.jobsMu.RUnlock() // unlock before returning
			return jc.get(queued) >= MaxQueuedJobs
		}
	}
	l.jobsMu.RUnlock() // unlock before store fetch

	// Release the locks while we fetch from the store
	counts, err := l.store.GetJobCountByStatusForActor(ctx, actor, RecentJobWindow)
	if err != nil {
		return false // fail open on error
	}

	l.jobsMu.Lock()         // write lock
	defer l.jobsMu.Unlock() // ensure unlock

	jc, ok := l.jobs.Get(actor) // just in case it was added while we fetched
	if !ok {
		jc = &jobCount{}
		l.jobs.Add(actor, jc)
	}
	jc.set(counts.Queued, counts.Running)

	return jc.get(queued) >= MaxQueuedJobs
}

// DelayProcessing checks if the number of running jobs for the actor has
// exceeded the maximum allowed. If it has, it returns a delay duration and
// true indicating that the job should be requeued after the delay.
//
// It checks the in-memory cache first, and if the cache is stale or missing,
// it refreshes the count from the database. If there is an error fetching
// the count from the database, it returns 0 and false to fail open and
// allow the job to be processed.
//
// Callers should requeue the job with the returned delay if this method
// returns true.
func (l *JobLimiter) DelayProcessing(ctx context.Context, actor int64) (time.Duration, bool) {
	l.jobsMu.RLock() // read lock
	if jc, ok := l.jobs.Get(actor); ok {
		if !jc.refresh() {
			l.jobsMu.RUnlock() // unlock before returning
			if jc.get(running) < MaxRunningJobs {
				return 0, false
			}
			return JobRequeueDelay, true
		}
	}
	l.jobsMu.RUnlock() // unlock before store fetch

	// Release the locks while we fetch from the store
	counts, err := l.store.GetJobCountByStatusForActor(ctx, actor, RecentJobWindow)
	if err != nil {
		return 0, false
	}

	l.jobsMu.Lock()         // write lock
	defer l.jobsMu.Unlock() // ensure unlock

	jc, ok := l.jobs.Get(actor) // just in case it was added while we fetched
	if !ok {
		jc = &jobCount{}
		l.jobs.Add(actor, jc)
	}
	jc.set(counts.Queued, counts.Running)

	if jc.get(running) < MaxRunningJobs {
		return 0, false
	}

	return JobRequeueDelay, true
}

// IncrementRunningJobs increments the number of running jobs for the actor
// in the in-memory cache.
func (l *JobLimiter) IncrementRunningJobs(ctx context.Context, actor int64) {
	l.jobsMu.Lock()
	defer l.jobsMu.Unlock()

	jc, ok := l.jobs.Get(actor)
	if !ok {
		return // not tracking count yet
	}

	jc.increment(running)
}

// DecrementRunningJobs decrements the number of running jobs for the actor
// in the in-memory cache.
func (l *JobLimiter) DecrementRunningJobs(ctx context.Context, actor int64) {
	l.jobsMu.Lock()
	defer l.jobsMu.Unlock()

	jc, ok := l.jobs.Get(actor)
	if !ok {
		return // not tracking count yet
	}

	jc.decrement(running)
}

// IncrementQueuedJobs increments the number of queued jobs for the actor
// in the in-memory cache.
func (l *JobLimiter) IncrementQueuedJobs(ctx context.Context, actor int64) {
	l.jobsMu.Lock()
	defer l.jobsMu.Unlock()

	jc, ok := l.jobs.Get(actor)
	if !ok {
		return // not tracking count yet
	}

	jc.increment(queued)
}

// DecrementQueuedJobs decrements the number of queued jobs for the actor
// in the in-memory cache.
func (l *JobLimiter) DecrementQueuedJobs(ctx context.Context, actor int64) {
	l.jobsMu.Lock()
	defer l.jobsMu.Unlock()

	jc, ok := l.jobs.Get(actor)
	if !ok {
		return // not tracking count yet
	}

	jc.decrement(queued)
}
