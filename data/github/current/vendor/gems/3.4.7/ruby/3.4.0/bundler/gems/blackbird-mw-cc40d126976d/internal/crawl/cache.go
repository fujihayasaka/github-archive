package crawl

import (
	"errors"
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/document"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/messages"
)

// newCachePublishTask creates a Task for sending OIDs to the cache server to be published.
func newCachePublishTask(tg *TaskGroup, msg *messages.Ingest, oid *gitaccess.BlobOIDChange) Task {
	if msg == nil {
		panic("msg nil")
	}

	if tg == nil {
		panic("tg nil")
	}

	return &cachePublishTask{
		msg: msg,
		oid: oid,
		tg:  tg,
	}
}

// newCacheContentTask creates a Task for sending blobs with content and symbols
// to the cache server to be published.
func newCacheContentTask(tg *TaskGroup, msg *messages.Ingest, blob *gitaccess.BlobContentChange) Task {
	if msg == nil {
		panic("msg nil")
	}

	if tg == nil {
		panic("tg nil")
	}

	return &cacheContentTask{
		msg:  msg,
		blob: blob,
		tg:   tg,
	}
}

type cachePublishTask struct {
	msg *messages.Ingest
	oid *gitaccess.BlobOIDChange
	tg  *TaskGroup
}

func (c *cachePublishTask) Process() {
	result := c.process()
	if result.isSkip || document.IsUnindexable(result.err) {
		statting.Counter(c.tg.ctx, "worker.publish.change.unindexable", 1, stats.Tags{"task": "cache_publish"})
		// NB: MUST manually signal we're done early (without publishing) so the task is recorded as finished.
		c.tg.DoneWithoutResult()
	} else {
		c.tg.Done(result)
	}
}

func (c *cachePublishTask) process() TaskResult {
	doc, err := document.NewGitDocumentFromOID(c.tg.ctx, c.msg, c.oid)
	if err != nil {
		if document.IsInvalidDocument(err) {
			logging.Error(c.tg.ctx, "invalid document from oid", kvp.String("blob_oid_change", fmt.Sprintf("%+v", c.oid)), kvp.Err(err))
		}
		return TaskResult{err: err, isCache: true, leaseExpiresAt: c.msg.Lease.ExpiresAtTime()}
	}

	// NOTE: We use the lease time on the document because that is what is sent
	// to the indexer. The lease on the message can change at any time when it
	// is renewed.
	leaseExpiresAt := time.UnixMilli(doc.LeaseExpiresAt)

	indexerCluster := c.tg.pool.indexerCluster
	cacheClusters := c.tg.pool.cacheClusters

	res, err := publishGitDocumentWithRetries(c.tg.ctx, indexerCluster, cacheClusters, newCacheRequest(doc, c.msg), c.msg.DocumentTopic, c.tg.backOff)
	if err != nil {
		return TaskResult{err: err, isCache: true, leaseExpiresAt: leaseExpiresAt}
	}

	result := TaskResult{
		logAppendTs:    time.Time{}, // NOTE: zero time is a special case for cache misses
		leaseExpiresAt: leaseExpiresAt,
		isCache:        true,
	}

	published := res.GetPublished()
	switch {
	case published == nil:
		result.missing = c.oid.ObjectID
	case published.Partition < 0:
		// A negative partition means this document was skipped for indexing
		result.isSkip = true
	default:
		result.partition = published.Partition
		result.offset = published.Offset
		result.logAppendTs = time.UnixMilli(published.AppendTime)
	}

	return result
}

// Basically the same as CrawlTask, but sends RPCs to cache server WITH content.
type cacheContentTask struct {
	msg  *messages.Ingest
	blob *gitaccess.BlobContentChange
	tg   *TaskGroup
}

func (c *cacheContentTask) Process() {
	result := c.process()
	if result.isSkip || document.IsUnindexable(result.err) {
		statting.Counter(c.tg.ctx, "worker.publish.change.unindexable", 1, stats.Tags{"task": "cache_content"})
		// NB: MUST manually signal we're done early (without publishing) so the task is recorded as finished.
		c.tg.DoneWithoutResult()
	} else {
		c.tg.Done(result)
	}
}

func (c *cacheContentTask) process() TaskResult {
	doc, err := document.NewGitDocumentFromContent(c.tg.ctx, c.msg, c.blob)
	if err != nil {
		if document.IsInvalidDocument(err) {
			logging.Error(c.tg.ctx, "invalid document from blob", kvp.String("blob_content_change", fmt.Sprintf("BlobContentChange{oid: %s, locations: %+v}", c.blob.ObjectID.String(), c.blob.BlobLocations)), kvp.Err(err))
		}

		return TaskResult{err: err, isCache: true, leaseExpiresAt: c.msg.Lease.ExpiresAtTime()}
	}

	// NOTE: We use the lease time on the document because that is what is sent
	// to the indexer. The lease on the message can change at any time when it
	// is renewed.
	leaseExpiresAt := time.UnixMilli(doc.LeaseExpiresAt)

	indexerCluster := c.tg.pool.indexerCluster
	cacheClusters := c.tg.pool.cacheClusters

	res, err := publishGitDocumentWithRetries(c.tg.ctx, indexerCluster, cacheClusters, newCacheRequest(doc, c.msg), c.msg.DocumentTopic, c.tg.backOff)
	if err != nil {
		return TaskResult{err: err, isCache: true, leaseExpiresAt: leaseExpiresAt}
	}

	published := res.GetPublished()
	switch {
	case published == nil:
		// This should never happen in the case of a cache publish with content that was not an error.
		logging.Error(c.tg.ctx, "empty published response for cache content", kvp.String("blob_oid", c.blob.ObjectID.String()), kvp.Int("num_locations", len(doc.Locations)), kvp.Int("num_content_bytes", len(doc.Content)), kvp.Bool("all_locations_deleted", doc.AllLocationsDeleted))
		return TaskResult{err: errors.New("non-error response from cache service with no PartitionOffset"), isCache: true, leaseExpiresAt: leaseExpiresAt}
	case published.Partition < 0:
		// A negative partition means this document was skipped for indexing
		return TaskResult{
			leaseExpiresAt: leaseExpiresAt,
			isCache:        true,
			isSkip:         true,
		}
	default:
		return TaskResult{
			logAppendTs:    time.UnixMilli(published.AppendTime),
			leaseExpiresAt: leaseExpiresAt,
			partition:      published.Partition,
			offset:         published.Offset,
			isCache:        true,
		}
	}
}

var _ Task = (*cachePublishTask)(nil)
var _ Task = (*cacheContentTask)(nil)
