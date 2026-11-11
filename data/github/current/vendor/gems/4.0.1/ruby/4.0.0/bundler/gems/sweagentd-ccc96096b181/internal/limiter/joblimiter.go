package limiter

import (
	"context"
	"time"

	"github.com/github/sweagentd/internal/sweagentd"
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
	//
	// TODO (colbylwilliams) (ritchxu): Consider increasing this limit once we
	// start incrementing/decrementing the concurrent job count in the redis
	// cache instead of relying on periodic database fetches which has shown to
	// allow bursts of new jobs to exceed the limit.
	MaxRunningJobs int = 4 // 4 jobs

	// MaxQueuedJobs is the maximum number of jobs that can be queued for a
	// single actor. If this limit is reached, new jobs will be rejected.
	//
	// This limit is used to prevent an actor from overwhelming the system with
	// too many queued jobs.
	//
	// IMPORTANT: This is a soft limit. It is not guaranteed that the number of
	// queued jobs will not exceed this limit, but it is a best effort to keep
	// the number of queued jobs below this limit.
	MaxQueuedJobs int = MaxRunningJobs * 10 // 10:1 ratio to running jobs

	// JobRequeueDelay is the delay used when requeuing jobs.
	//
	// IMPORTANT: Make sure we always requeue jobs with the same delay. This
	// ensures jobs are processed in the same order they were received/requeued,
	// even if they are requeued multiple times. This is important for maintaining
	// the integrity of the job processing order, and prevents requeued jobs from
	// getting stuck behind other jobs that were received later.
	//
	// NOTE: This value should be coordinated with [agent_job.AgentJobMaxRequeueCount]
	// to ensure that the maximum total time a job can spend in the queued state
	// is acceptable.
	JobRequeueDelay time.Duration = 90 * time.Second // (90 seconds) see note above

	// RecentJobWindow is the time window used to determine if a job is recent.
	// This is used to prevent counting old jobs that are no longer relevant or
	// stale in the system.
	//
	// This is used when fetching job counts from the database and compared against
	// the job created_at timestamp. Jobs older than this window are not counted.
	//
	// This value should be significantly larger than the maximum expected job
	// processing time to ensure that all relevant jobs are counted, but not so
	// large that it includes stale jobs that are no longer relevant.
	RecentJobWindow time.Duration = 2 * time.Hour // 2 hours

	// CountCacheTTL is the TTL for the cached job counts.
	CountCacheTTL time.Duration = 30 * time.Minute // 30 minutes
)

type store interface {
	GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration) (sweagentd.JobCounts, error)
}

// JobLimiter is responsible for limiting the number of concurrent jobs that can
// be running and queued for a single actor. It uses a cache store (Redis or in-memory)
// to track the number of running and queued jobs for each actor.
//
// We constrain the number of concurrently running jobs per actor, and to delay
// job processing when the limit is reached. This prevents the actor from hitting
// CAPI rate limits causing a cascading failure across their jobs.
//
// Additionally, we constrain the number of queued jobs per actor. This prevents
// an actor from overwhelming the system with too many queued jobs.
//
// With Redis-based cache, the counts are shared across all pods and use atomic
// increment/decrement operations for accuracy. With in-memory cache using refresh
// heuristics, each pod has its own local cache that periodically refreshes from
// the database based on update count and proximity to limits.
type JobLimiter struct {
	store        store
	countTracker jobCountTracker
}

// NewJobLimiter creates a new JobLimiter with the specified store and count tracker.
func NewJobLimiter(store store, countTracker jobCountTracker) *JobLimiter {
	return &JobLimiter{
		store:        store,
		countTracker: countTracker,
	}
}

// QueuedJobsExceeded returns true if the number of queued jobs for the actor
// has exceeded the maximum allowed. It checks the cache first, and
// if the cache is stale or missing, it refreshes the count from the database.
// If there is an error fetching the count from the database, it returns false
// to fail open and allow the job to be processed.
//
// Callers should return an error to the user if this method returns true,
// indicating that the actor has too many queued jobs.
func (l *JobLimiter) QueuedJobsExceeded(ctx context.Context, actor int64) bool {
	queuedCount, exists := l.countTracker.Get(actor, queued)
	if exists {
		return queuedCount >= MaxQueuedJobs
	}

	// Release the locks while we fetch from the store
	counts, err := l.store.GetJobCountByStatusForActor(ctx, actor, RecentJobWindow)
	if err != nil {
		return false // fail open on error
	}

	l.countTracker.Set(actor, queued, counts.Queued, CountCacheTTL)
	l.countTracker.Set(actor, running, counts.Running, CountCacheTTL)

	return counts.Queued >= MaxQueuedJobs
}

// DelayProcessing checks if the number of running jobs for the actor has
// exceeded the maximum allowed. If it has, it returns a delay duration and
// true indicating that the job should be requeued after the delay.
//
// It checks the cache first, and if the cache is stale or missing,
// it refreshes the count from the database. If there is an error fetching
// the count from the database, it returns 0 and false to fail open and
// allow the job to be processed.
//
// Callers should requeue the job with the returned delay if this method
// returns true.
func (l *JobLimiter) DelayProcessing(ctx context.Context, actor int64) (time.Duration, bool) {
	runningCount, exists := l.countTracker.Get(actor, running)
	if exists {
		if runningCount < MaxRunningJobs {
			return 0, false
		}
		return JobRequeueDelay, true
	}

	// Release the locks while we fetch from the store
	counts, err := l.store.GetJobCountByStatusForActor(ctx, actor, RecentJobWindow)
	if err != nil {
		return 0, false
	}

	l.countTracker.Set(actor, running, counts.Running, CountCacheTTL)
	l.countTracker.Set(actor, queued, counts.Queued, CountCacheTTL)

	if counts.Running < MaxRunningJobs {
		return 0, false
	}

	return JobRequeueDelay, true
}

// IncrementRunningJobs increments the number of running jobs for the actor
// in the cache.
func (l *JobLimiter) IncrementRunningJobs(ctx context.Context, actor int64) {
	l.countTracker.Incr(actor, running, 1, CountCacheTTL)
}

// DecrementRunningJobs decrements the number of running jobs for the actor
// in the cache.
func (l *JobLimiter) DecrementRunningJobs(ctx context.Context, actor int64) {
	l.countTracker.Decr(actor, running, 1, CountCacheTTL)
}

// IncrementQueuedJobs increments the number of queued jobs for the actor
// in the cache.
func (l *JobLimiter) IncrementQueuedJobs(ctx context.Context, actor int64) {
	l.countTracker.Incr(actor, queued, 1, CountCacheTTL)
}

// DecrementQueuedJobs decrements the number of queued jobs for the actor
// in the cache.
func (l *JobLimiter) DecrementQueuedJobs(ctx context.Context, actor int64) {
	l.countTracker.Decr(actor, queued, 1, CountCacheTTL)
}
