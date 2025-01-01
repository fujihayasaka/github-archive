package crawl

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/blackbird/crates/core/pkg/shard"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/messages"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/utils"
)

// WorkPool manages a pool of goroutines that perform document construction and
// publishing using the cache cluster. WorkPool runs tasks that implement the
// Task interface; different task implementations publish to the cache cluster
// with or without content based on if there is a cache hit or not.
//
// The cache clusters always perform language analysis (language detection,
// parsing, and symbol extraction) and publish to the GitDocument topics in
// Kafka directly.
//
// Enqueued tasks are organized into groups (e.g. one per repository being
// ingested) so that a topic barrier for the group can be returned and so that
// errors can be aggregated.
type WorkPool struct {
	wg             sync.WaitGroup
	tasks          chan Task
	indexerCluster *routing.IndexerCluster
	cacheClusters  *routing.CacheClusters
	corpus         routing.Corpus
}

// NewWorkPool creates a new WorkPool. The caller must call Close()
// when they are done to free resources and fully flush any produced kafka
// messages.
func NewWorkPool(
	ctx context.Context,
	indexerCluster *routing.IndexerCluster,
	cacheClusters *routing.CacheClusters,
	numWorkers int,
	corpus routing.Corpus,
) *WorkPool {
	pool := WorkPool{tasks: make(chan Task), indexerCluster: indexerCluster, cacheClusters: cacheClusters, corpus: corpus}

	pool.wg.Add(numWorkers)
	for i := 0; i < numWorkers; i++ {
		go func() {
			defer utils.PanicLogger(ctx)
			defer pool.wg.Done()
			for task := range pool.tasks {
				task.Process()
			}
		}()
	}

	return &pool
}

// Close release all resources related to the pool, it stops accepting new work,
// and waits for all workers to finish. It is an error to use the pool after
// you've called `Close()`.
func (p *WorkPool) Close() {
	close(p.tasks) // Stop accepting new work
	p.wg.Wait()    // Wait for all workers in the pool to finish
}

// Enqueue a task on the pool for processing. Once you've queued all task for
// your group, call `Wait()` on the group to block until they are done.
func (p *WorkPool) Enqueue(task Task) {
	p.tasks <- task
}

// NewTaskGroup creates a new group of crawl tasks that allows checking for
// soon-to-expire leases and calls renew.
func (p *WorkPool) NewTaskGroup(ctx context.Context, cancel context.CancelFunc, renew RenewLease) *TaskGroup {
	return p.NewTaskGroupWithBackOff(ctx, cancel, retry.Forever(ctx), renew)
}

// Primarily for testing, to avoid long retries.
func (p *WorkPool) NewTaskGroupWithBackOff(ctx context.Context, cancel context.CancelFunc, backOff backoff.BackOff, renew RenewLease) *TaskGroup {
	tg := &TaskGroup{
		ctx:     ctx,
		wg:      sync.WaitGroup{},
		results: make(chan TaskResult),
		done:    make(chan error),
		result:  TaskGroupResult{PartitionOffsets: map[int32]int64{}, Missing: map[gitaccess.ObjectID]bool{}},
		pool:    p,
		backOff: backOff,
	}

	go func() {
		defer utils.PanicLogger(ctx)
		var err error
		for res := range tg.results {
			if res.err != nil {
				tg.result.NumErrs++
				if err == nil { // NB: Capture just the first error (if any)
					err = res.err

					if cancel != nil {
						cancel() // Allow the caller to stop enqueuing tasks
					}
				}
				continue // NB: Must drain the results channel
			}

			if res.IsCacheMiss() {
				tg.result.Missing[res.missing] = true
			} else if !res.isSkip {
				tg.result.NumDocs++

				// Capture the very last log append time for this group of tasks
				if res.logAppendTs.After(tg.result.MaxLogAppendTs) {
					tg.result.MaxLogAppendTs = res.logAppendTs
				}
				// Capture the largest offset for each partition
				maxOffset := tg.result.PartitionOffsets[res.partition]
				if res.offset > maxOffset {
					tg.result.PartitionOffsets[res.partition] = res.offset
				}
			}

			// Check if the lease expired. We need to do this before attempting
			// to renew the lease, because if we lost the lease, we have to give
			// up.
			if res.isLeaseExpired() {
				// lease expired!
				if err == nil { // NB: Capture just the first error (if any)
					err = ErrLeaseExpired
				}

				if cancel != nil {
					cancel() // Allow the caller to stop enqueuing tasks
				}
				continue // NB: Must drain the results channel
			}

			// Check if we need to renew the lease. If ingesting a single repo takes
			// more than the original lease duration (e.g. 2hrs) then we'll need to
			// extend the lease. We compare the lease sent on each document published
			// with Kafka's LogAppendTime and once we get within 10 mins of the lease
			// expiring: renew.
			if canRenewLease(tg.result, res) {
				// lease might expire before we finish crawling, renew it
				if leaseErr := renew(); leaseErr != nil {
					if err == nil { // NB: Capture just the first error (if any)
						err = leaseErr
					}

					if cancel != nil {
						cancel() // Allow the caller to stop enqueuing tasks
					}
					continue // NB: Must drain the results channel
				}
			}
		}

		tg.done <- err
	}()

	return tg
}

// Task is a specific blob to crawl and produce a document.
type Task interface {
	// Process runs the task.
	Process()
}

// TaskResult records the result of a single document publish RPC. Failure to
// convert a change into a GitDocument is also reported as a TaskResult, but
// does not result in an RPC.
type TaskResult struct {
	// err will be non-nil an unsuccessful TaskResult.
	err error
	// leaseExpiresAt is the lease expiration time of the document associated with this
	// result. leaseExpiresAt will ALWAYS be set, even for errored TaskResults.
	leaseExpiresAt time.Time
	// logAppendTs is the LogAppendTime of a successful publish. Will be zero for
	// cache miss or a skip.
	logAppendTs time.Time
	// The partition the index message was published to.
	partition int32
	// The offset of the index message in partition.
	offset int64
	// isCache will be true if this is a cache result
	isCache bool
	// missing will be a non-NullObjectID if the document was not cached and
	// needs to be fetched from Git.
	missing gitaccess.ObjectID
	// isSkip will be true if this is was a document that was skipped for
	// indexing.
	isSkip bool
}

func (tr TaskResult) IsCacheMiss() bool {
	return tr.isCache && !tr.missing.IsNull()
}

// isLeaseExpired returns true if the logAppendTs is greater than or equal to
// the lease expiration time.
//
// This check tests whether the lease used to publish the document covered the
// log append time of the resulting Kafka message. Otherwise, we could miss that
// a document was rejected by the indexer because of the lease.
func (tr TaskResult) isLeaseExpired() bool {
	if tr.leaseExpiresAt.IsZero() {
		panic("lease expiration time must be set for all TaskResult instances")
	}

	return tr.logAppendTs.Compare(tr.leaseExpiresAt) >= 0
}

// RenewLease should call the Lease RPC and, if successful, update the lease on
// the ingest message.
type RenewLease func() error

var ErrLeaseExpired = errors.New("lease expired")

// The maximum LogAppendTime and maximum offset per partition of all published
// documents, a collection of missing documents that must be fetched and
// republished, and some statistics about a group of tasks.
type TaskGroupResult struct {
	MaxLogAppendTs   time.Time                   // MaxLogAppendTs is the largest seen LogAppendTs on any partition
	PartitionOffsets map[int32]int64             // PartitionOffsets is the maximum published offset for each partition
	Missing          map[gitaccess.ObjectID]bool // Documents missing from cache (must be fetched, analyzed, and republished)
	NumDocs          int                         // NumDocs is the number of documents published by the task group
	NumErrs          int                         // NumErrs is the number of errors encountered. Must be 0 for a successful TaskGroup.
}

// TaskGroup allows organizing a collection of tasks that are all related to
// the same repo and waiting on them to finish producing to kafka. It aggregates
// results and returns either a max LogAppendTime of all tasks in the group or
// an error.
type TaskGroup struct {
	ctx     context.Context
	wg      sync.WaitGroup
	results chan TaskResult
	done    chan error
	result  TaskGroupResult
	pool    *WorkPool
	backOff backoff.BackOff
}

func (tg *TaskGroup) EnqueueCachePublishTask(msg *messages.Ingest, oid *gitaccess.BlobOIDChange) {
	start := time.Now()
	defer func() {
		statting.DistributionMs(tg.ctx, "crawl.task_group.enqueue.duration", time.Since(start), stats.Tags{"task": "cache_publish"})
	}()

	for _, change := range blobOIDChangesByDocSHA(oid, msg.EpochMode) {
		tg.enqueue(newCachePublishTask(tg, msg, change))
	}
}

func (tg *TaskGroup) EnqueueCacheContentTask(msg *messages.Ingest, blob *gitaccess.BlobContentChange) {
	start := time.Now()
	defer func() {
		statting.DistributionMs(tg.ctx, "crawl.task_group.enqueue.duration", time.Since(start), stats.Tags{"task": "cache_content"})
	}()

	for _, change := range blobContentChangesByDocSHA(blob, msg.EpochMode) {
		tg.enqueue(newCacheContentTask(tg, msg, change))
	}
}

func (tg *TaskGroup) enqueue(t Task) {
	tg.wg.Add(1)
	tg.pool.Enqueue(t)
}

// Done signals that a task in the group is done and writes its result to the
// group's results channel.
func (tg *TaskGroup) Done(result TaskResult) {
	tg.results <- result
	tg.wg.Done()
}

// DoneWithoutResult signals that a task in the group is done but did not
// produce a result.
func (tg *TaskGroup) DoneWithoutResult() {
	tg.wg.Done()
}

// Wait blocks until all tasks in the group have finished processing and
// producing (received by the kafka broker). It returns the max LogAppendTime of
// all tasks in the group or an error if any task failed.
func (tg *TaskGroup) Wait() (*TaskGroupResult, error) {
	// Wait for all tasks in this crawl group to be processed before closing the
	// group's results channel.
	tg.wg.Wait()
	close(tg.results)

	// wait for results to be collected and an error (if any) to be returned
	err := <-tg.done

	return &tg.result, err
}

// canRenewLease returns true if the largest seen LogAppend time plus a
// threshold is after the TaskResult's lease expiration timestamp.
func canRenewLease(tgr TaskGroupResult, tr TaskResult) bool {
	const leaseThreshold = 10 * time.Minute

	// NOTE: Cache misses do not produce a document to Kafka, so have no
	// ServingTs. In this case, we'll extend the lease if the current time is
	// getting close to the expiration.
	if tgr.MaxLogAppendTs.IsZero() && tr.isCache {
		return time.Now().UTC().Add(leaseThreshold).After(tr.leaseExpiresAt)
	}

	return tgr.MaxLogAppendTs.Add(leaseThreshold).After(tr.leaseExpiresAt)
}

// Group by the doc SHA computed for this epoch mode. When sharding by (content
// sha, path), we must enqueue one cache publish per location.
func blobOIDChangesByDocSHA(oid *gitaccess.BlobOIDChange, epochMode epoch.EpochMode) map[gitaccess.ObjectID]*gitaccess.BlobOIDChange {
	grouped := map[gitaccess.ObjectID]*gitaccess.BlobOIDChange{}
	for _, loc := range oid.BlobLocations {
		docSHABytes := shard.DocSHAForEpochMode(oid.ObjectID.Bytes(), loc.Path, epochMode)
		docSHA := gitaccess.NewObjectIDFromBytes(docSHABytes) // convert doc SHA to an ObjectID so it can be used as a map key

		if change := grouped[docSHA]; change != nil {
			change.BlobLocations = append(change.BlobLocations, loc)
		} else {
			grouped[docSHA] = &gitaccess.BlobOIDChange{
				ObjectID:      oid.ObjectID,
				BlobLocations: []*gitaccess.BlobLocationEntry{loc},
			}
		}
	}

	return grouped
}

// Group by the doc SHA computed for this epoch mode. When sharding by (content
// sha, path), we must enqueue one cache publish per location.
func blobContentChangesByDocSHA(blob *gitaccess.BlobContentChange, epochMode epoch.EpochMode) map[gitaccess.ObjectID]*gitaccess.BlobContentChange {
	grouped := map[gitaccess.ObjectID]*gitaccess.BlobContentChange{}
	for _, loc := range blob.BlobLocations {
		docSHABytes := shard.DocSHAForEpochMode(blob.ObjectID.Bytes(), loc.Path, epochMode)
		docSHA := gitaccess.NewObjectIDFromBytes(docSHABytes) // convert doc SHA to an ObjectID so it can be used as a map key

		if change := grouped[docSHA]; change != nil {
			change.BlobLocations = append(change.BlobLocations, loc)
		} else {
			grouped[docSHA] = &gitaccess.BlobContentChange{
				ObjectID:      blob.ObjectID,
				Content:       blob.Content,
				BlobLocations: []*gitaccess.BlobLocationEntry{loc},
			}
		}
	}

	return grouped
}
