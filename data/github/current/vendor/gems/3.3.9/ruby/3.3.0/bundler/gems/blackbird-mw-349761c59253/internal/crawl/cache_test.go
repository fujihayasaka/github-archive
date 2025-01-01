package crawl_test

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/crawl"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/messages"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_CreatePoolAndEnqueueCachePublishTask(t *testing.T) {
	const partition = 0
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	cache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  partition,
				Offset:     int64(cache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:          1,
		OwnerID:         1,
		Head:            &gitaccess.RefTip{RefName: "refs/heads/master", CommitOID: helpers.RandomOID(t)},
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blobs := 0
	blob := func() *gitaccess.BlobOIDChange {
		blobs++
		return &gitaccess.BlobOIDChange{
			ObjectID:      helpers.RandomOID(t),
			BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: fmt.Sprintf("foo-%d.txt", blobs)}},
		}
	}

	tg := pool.NewTaskGroup(ctx, nil, noopRenew)
	tg.EnqueueCachePublishTask(msg, blob())
	tg.EnqueueCachePublishTask(msg, blob())
	tg.EnqueueCachePublishTask(msg, blob())

	res, err := tg.Wait()
	require.NoError(t, err)
	require.Equal(t, 3, cache.PublishCacheDocumentCallCount())
	require.True(t, res.MaxLogAppendTs.After(time.Time{}))
	require.Equal(t, 3, res.NumDocs)
	require.Equal(t, 0, res.NumErrs)
	require.Equal(t, map[int32]int64{partition: int64(blobs)}, res.PartitionOffsets)
}

func Test_ProcessCachePublishTaskRPCError(t *testing.T) {
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	cache.PublishCacheDocumentReturns(nil, errors.New("some horrible problem"))

	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:          1,
		OwnerID:         1,
		Head:            &gitaccess.RefTip{RefName: "refs/heads/master", CommitOID: helpers.RandomOID(t)},
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blob := &gitaccess.BlobOIDChange{
		ObjectID:      helpers.RandomOID(t),
		BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: "foo.txt"}},
	}
	tg := pool.NewTaskGroupWithBackOff(ctx, nil, &backoff.StopBackOff{}, noopRenew)
	tg.EnqueueCachePublishTask(msg, blob)

	_, err = tg.Wait()
	require.EqualError(t, err, "some horrible problem")
}

func Test_CachePublishTaskUnindexableContent(t *testing.T) {
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:  1,
		OwnerID: 1,
		Head: &gitaccess.RefTip{
			RefName:   "refs/heads/master",
			CommitOID: helpers.RandomOID(t),
		},
		DocumentTopic: routing.DocumentTopic{
			Partitions: 1,
		},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blob := &gitaccess.BlobOIDChange{
		ObjectID:      helpers.RandomOID(t),
		BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: "vendor/foo.txt"}}, // NB: This is a vendored path
	}

	tg := pool.NewTaskGroup(ctx, nil, noopRenew)
	tg.EnqueueCachePublishTask(msg, blob)

	res, err := tg.Wait()
	require.NoError(t, err)             // No error expected, just the RPC should have been skipped
	require.Zero(t, res.MaxLogAppendTs) // No valid LogAppendTime b/c no content was published
	require.Zero(t, res.NumDocs)
	require.Zero(t, res.NumErrs)
	require.Equal(t, map[int32]int64{}, res.PartitionOffsets)
	require.Equal(t, 1, cache.PublishCacheDocumentCallCount())
	require.Zero(t, cache.PublishDeleteDocumentCallCount())
	require.Zero(t, cache.PublishDocumentCallCount())
}

func Test_CachePublishTaskUnindexableBlobOID(t *testing.T) {
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:  1,
		OwnerID: 1,
		Head: &gitaccess.RefTip{
			RefName:   "refs/heads/master",
			CommitOID: helpers.RandomOID(t),
		},
		DocumentTopic: routing.DocumentTopic{
			Partitions: 1,
		},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blob := &gitaccess.BlobOIDChange{
		ObjectID:      gitaccess.EmptyBlobOID,
		BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: "vendor/foo.txt"}}, // NB: This is a vendored path
	}

	tg := pool.NewTaskGroup(ctx, nil, noopRenew)
	tg.EnqueueCachePublishTask(msg, blob)

	res, err := tg.Wait()
	require.NoError(t, err)             // No error expected, just the RPC should have been skipped
	require.Zero(t, res.MaxLogAppendTs) // No valid LogAppendTime b/c no content was published
	require.Zero(t, res.NumDocs)
	require.Zero(t, res.NumErrs)
	require.Equal(t, map[int32]int64{}, res.PartitionOffsets)
	require.Zero(t, cache.PublishCacheDocumentCallCount()) // empty blob isn't even sent to cache server
	require.Zero(t, cache.PublishDeleteDocumentCallCount())
	require.Zero(t, cache.PublishDocumentCallCount())
}

func Test_CreatePoolAndEnqueueCacheContentTask(t *testing.T) {
	const partition = 0
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	cache.PublishDocumentStub = func(ctx context.Context, req *cachepb.PublishDocumentRequest) (*cachepb.PublishDocumentResponse, error) {
		return &cachepb.PublishDocumentResponse{
			Published: &cachepb.Published{
				Partition:  partition,
				Offset:     int64(cache.PublishDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:          1,
		OwnerID:         1,
		Head:            &gitaccess.RefTip{RefName: "refs/heads/master", CommitOID: helpers.RandomOID(t)},
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blobs := 0
	blob := func() *gitaccess.BlobContentChange {
		blobs++
		return &gitaccess.BlobContentChange{
			ObjectID:      helpers.RandomOID(t),
			BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: fmt.Sprintf("foo-%d.txt", blobs)}},
			Content:       []byte(fmt.Sprintf("content %d", blobs)),
		}
	}

	tg := pool.NewTaskGroup(ctx, nil, noopRenew)
	tg.EnqueueCacheContentTask(msg, blob())
	tg.EnqueueCacheContentTask(msg, blob())
	tg.EnqueueCacheContentTask(msg, blob())

	res, err := tg.Wait()
	require.NoError(t, err)
	require.Equal(t, 3, cache.PublishDocumentCallCount())
	require.Equal(t, 0, cache.PublishCacheDocumentCallCount())
	require.Equal(t, 0, cache.PublishDeleteDocumentCallCount())
	require.True(t, res.MaxLogAppendTs.After(time.Time{}))
	require.Equal(t, 3, res.NumDocs)
	require.Equal(t, 0, res.NumErrs)
	require.Equal(t, map[int32]int64{partition: int64(blobs)}, res.PartitionOffsets)
}

func Test_ProcessCacheContentTaskRPCError(t *testing.T) {
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	cache.PublishDocumentReturns(nil, errors.New("some horrible problem"))

	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:          1,
		OwnerID:         1,
		Head:            &gitaccess.RefTip{RefName: "refs/heads/master", CommitOID: helpers.RandomOID(t)},
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blob := &gitaccess.BlobContentChange{
		ObjectID:      helpers.RandomOID(t),
		BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: "foo.txt"}},
		Content:       []byte("test"),
	}
	tg := pool.NewTaskGroupWithBackOff(ctx, nil, &backoff.StopBackOff{}, noopRenew)
	tg.EnqueueCacheContentTask(msg, blob)

	_, err = tg.Wait()
	require.EqualError(t, err, "some horrible problem")
}

func Test_CacheContentTaskUnindexableContent(t *testing.T) {
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:  1,
		OwnerID: 1,
		Head: &gitaccess.RefTip{
			RefName:   "refs/heads/master",
			CommitOID: helpers.RandomOID(t),
		},
		DocumentTopic: routing.DocumentTopic{
			Partitions: 1,
		},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blob := &gitaccess.BlobContentChange{
		ObjectID:      helpers.RandomOID(t),
		Content:       []byte("hello world"),
		BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: "vendor/foo.txt"}}, // NB: This is a vendored path
	}

	tg := pool.NewTaskGroup(ctx, nil, noopRenew)
	tg.EnqueueCacheContentTask(msg, blob)

	res, err := tg.Wait()
	require.NoError(t, err)             // No error expected, just the RPC should have been skipped
	require.Zero(t, res.MaxLogAppendTs) // No valid LogAppendTime b/c no content was published
	require.Zero(t, res.NumDocs)
	require.Zero(t, res.NumErrs)
	require.Equal(t, map[int32]int64{}, res.PartitionOffsets)
	require.Zero(t, cache.PublishCacheDocumentCallCount())
	require.Zero(t, cache.PublishDeleteDocumentCallCount())
	require.Equal(t, 1, cache.PublishDocumentCallCount())
}

func Test_ProcessCacheContentTaskAnalysisError(t *testing.T) {
	const partition = 0
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	cache := helpers.FakeCacheAPI(t, client, 0)
	cache.PublishDocumentStub = func(ctx context.Context, req *cachepb.PublishDocumentRequest) (*cachepb.PublishDocumentResponse, error) {
		return &cachepb.PublishDocumentResponse{
			Published: &cachepb.Published{
				Partition:  partition,
				Offset:     int64(cache.PublishDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	pool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer pool.Close()

	msg := &messages.Ingest{
		RepoID:          1,
		OwnerID:         1,
		Head:            &gitaccess.RefTip{RefName: "refs/heads/master", CommitOID: helpers.RandomOID(t)},
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		IngestStartedAt: time.Now(),
		Lease:           messages.NewLease(),
	}
	blobs := 0
	blob := func() *gitaccess.BlobContentChange {
		blobs++
		return &gitaccess.BlobContentChange{
			ObjectID:      helpers.RandomOID(t),
			BlobLocations: []*gitaccess.BlobLocationEntry{{Change: gitaccess.Add, Path: fmt.Sprintf("foo-%d.txt", blobs)}},
			Content:       []byte(fmt.Sprintf("content %d", blobs)),
		}
	}

	tg := pool.NewTaskGroup(ctx, nil, noopRenew)
	tg.EnqueueCacheContentTask(msg, blob())
	tg.EnqueueCacheContentTask(msg, blob())
	tg.EnqueueCacheContentTask(msg, blob())

	res, err := tg.Wait()
	require.NoError(t, err, "no error is expected because the analysis call is supressed")
	require.Equal(t, 3, cache.PublishDocumentCallCount())

	for i := 0; i < cache.PublishDocumentCallCount(); i++ {
		_, req := cache.PublishDocumentArgsForCall(i)
		require.Equal(t, constants.UnknownLanguageId, req.GitDocument.LanguageId)
		require.Empty(t, req.GitDocument.Symbols)
	}

	require.True(t, res.MaxLogAppendTs.After(time.Time{}))
	require.Equal(t, 3, res.NumDocs)
	require.Equal(t, 0, res.NumErrs)
	require.Equal(t, map[int32]int64{partition: int64(blobs)}, res.PartitionOffsets)
}

func noopRenew() error {
	return nil
}
