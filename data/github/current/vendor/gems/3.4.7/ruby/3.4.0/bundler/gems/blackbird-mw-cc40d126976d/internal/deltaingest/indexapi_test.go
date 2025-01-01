package deltaingest

import (
	"context"
	"database/sql"
	_ "embed"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	indexpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/index/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	pb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/blackbird-mw/internal/crawl"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/db/repofilter"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/gitaccess/spokesd"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/github/githubfakes"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_indexapiWithFullCache(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	repo.Experiments = experiments.Experiments{} // NOTE: Documents should use the experiments returned by IndexResponse
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)
	entryExperiments := experiments.Experiments{"foo": "1"}

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			Experiments:    entryExperiments,
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		mockGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
		BlackbirdSuggestedChildId: 999,
		BlackbirdAncestorRepoIds:  []uint32{111, 222, 333},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// One GetPermanentError RPC
	require.Equal(t, 1, fakeIndexAPI.GetPermanentErrorCallCount())

	// Just one Index RPC, and it has the right stuff in it
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())
	_, req := fakeIndexAPI.IndexArgsForCall(0)
	require.Equal(t, uint32(repo.RepoID), req.Repo.RepoId)
	require.Equal(t, repo.OwnerID, req.Repo.OwnerId)
	require.Equal(t, uint32(repo.NetworkID.Int32), req.Repo.NetworkId)
	require.Equal(t, repo.NWO(), req.Repo.Nwo)
	require.Equal(t, uint64(repo.CommitSeqNo.Int64), req.CommitSeqNo)
	require.Equal(t, uint64(repo.RepoSeqNo.Int64), req.Repo.RepoSeqNo)
	require.Equal(t, repo.IsPublic, req.Repo.IsPublic)
	require.Equal(t, repo.IsFork.Bool, req.Repo.IsFork)
	require.Equal(t, repo.IsArchived, req.Repo.IsArchived)
	require.Equal(t, repo.RepoScore(), req.Repo.RepoScore)
	require.Equal(t, repo.LicenseName.String, req.Repo.LicenceName)
	require.Equal(t, uint32(repo.NumWatchers.Int32), req.Repo.NumWatchers)
	require.Equal(t, uint32(repo.NumStars.Int32), req.Repo.NumStars)
	require.Equal(t, repo.HasReadme.Bool, req.Repo.HasReadMe)
	require.Equal(t, uint32(repo.PublicForkCount.Int32), req.Repo.PublicForkCount)
	require.NotZero(t, req.ExpiresAt)
	require.Equal(t, []uint32{111, 222, 333}, req.ParentRepoIds)
	require.NotNil(t, req.SuggestedChildId)
	require.Equal(t, uint32(999), req.SuggestedChildId.Value)
	require.Equal(t, headOID.Bytes(), req.CommitSha)
	require.Equal(t, "refs/heads/main", req.RefName)
	require.Equal(t, experiments.Experiments{}, experiments.Experiments(req.Repo.Experiments), "expected no experiments in IndexRequest")
	require.Equal(t, uint64(repo.RepoSeqNo.Int64), req.Repo.RepoSeqNo)
	require.False(t, req.Reindex, "Reindex should only be true for ADMIN_REPAIR events")

	// N cache RPCs
	require.Equal(t, 2, fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of blobs")
	// Experiments from IndexResponse are used
	_, doc := fakeCache.PublishCacheDocumentArgsForCall(0)
	require.Equal(t, entryExperiments, experiments.Experiments(doc.GitDocument.Experiments), "experiments from IndexResponse should be used for publishing")
}

// https://github.com/orgs/community/discussions/114072
func Test_indexapiPayingCustomerFlagIsHonored(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	githubClient := &githubfakes.FakeInternalAPIClient{}
	githubClient.GetRepositoryStub = func(ctx context.Context, id types.RepoID) (*github.Repository, error) {
		if id == repo.RepoID {
			ghr := helpers.GitHubRepositoryFromRepository(t, repo)
			ghr.PayingCustomer = true
			return ghr, nil
		}

		return nil, twirp.NewError(twirp.NotFound, "no repo")
	}

	const blobPaths = 100_000 // NOTE: Higher than the free limit
	gitClient := mockGitClient(t, headOID)
	gitClient.DiffStub = func(ctx context.Context, locationLimit int, t1, t2 *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
		oid := helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") // NOTE: one of mockGitClient's blob OIDs
		entries := make([]*gitaccess.DiffEntry, 0, blobPaths)
		for i := 0; i < blobPaths; i++ {
			entries = append(entries, &gitaccess.DiffEntry{Path: fmt.Sprintf("p-%d", i), OID: oid, Change: gitaccess.Add})
		}

		return gitaccess.RepoDiff{repo.RepoID: entries}, nil
	}

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		githubClient,
		gitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// Just one Index RPC
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())

	// Only one blob => 1 cache RPC
	require.Equal(t, 1, fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of blobs")
	_, req := fakeCache.PublishCacheDocumentArgsForCall(0)
	require.Equal(t, blobPaths, len(req.GitDocument.Locations), "expected a single document with `blobPaths` locations")

	// Only one GitHub internal API request is required at the beginning of the ingest
	require.Equal(t, 1, githubClient.GetRepositoryCallCount(), "we expect only one call to the internal API")
}

func Test_indexapiGetPermanentErrorWithErrorStopsIngest(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:      &servingpb.ServingStatus{},
			PermanentError:     "oh noes, it's all broken",
			PermanentErrorType: blackbird_entities.PermanentErrorType_RETRIES_EXHAUSTED,
			EntryId:            123,
		},
		nil,
	)

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, helpers.CacheClusters(t), workers, corpus)
	defer crawlPool.Close()

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		mockGitClient(t, helpers.UniqueOID(t)),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Equal(t, db.SkipPermanentError, *skip)

	// One GetPermanentError RPC
	require.Equal(t, 1, fakeIndexAPI.GetPermanentErrorCallCount())

	// No other RPCs
	require.Equal(t, 0, fakeIndexAPI.IndexCallCount())
	require.Equal(t, 0, fakeIndexAPI.FinalizeCallCount())
}

func Test_indexapiReindex(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		mockGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
		Change: pb.RepositoryChanged_ADMIN_REPAIR, // NOTE: Should cause us to tell the indexer to reindex
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// GetPermanentError should not be called
	require.Equal(t, 0, fakeIndexAPI.GetPermanentErrorCallCount(), "expected GetPermanentError to be skipped for ADMIN_REPAIR event")

	// Just one Index RPC, and it sets Reindex
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())
	_, req := fakeIndexAPI.IndexArgsForCall(0)
	require.True(t, req.Reindex, "Expected Reindex to be true for ADMIN_REPAIR event")
}

// This tests simulates the index having a higher commit sequence number than
// the ingest process. It does this by making the first Index RPC fail and
// ensuring the repo's commit sequence number doesn't change on the retry.
// Meanwhile, the second Index RPC returns a higher commit sequence number.
func Test_indexapiStopsRetriesAfterIndexerCommitSeqNoExceedsInitialCommitSeqNo(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	headOID := helpers.UniqueOID(t)
	repo := helpers.Repositories(t, 1)[0]
	repo.CommitOID = headOID.Bytes()
	store := noop.New(repo)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)

	var initialCommitSeqNo uint64

	// This stub simulates a failed RPC that nevertheless registered the initial
	// commit sequence number. After the first RPC fails, the second one returns
	// a HIGHER commit sequence number than the ingest.
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		if initialCommitSeqNo == 0 {
			initialCommitSeqNo = req.CommitSeqNo
		}

		if fakeIndexAPI.IndexCallCount() == 1 {
			return nil, context.DeadlineExceeded
		}

		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId,        // Must match req for ingest to finish
			CommitSeqNo:    initialCommitSeqNo + 1, // Must match or exceed initial commit seq no
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		mockGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
		BlackbirdSuggestedChildId: 999,
		BlackbirdAncestorRepoIds:  []uint32{111, 222, 333},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// Database only increments the sequence number once
	dbRepo, err := store.GetRepositoryByID(ctx, repo.RepoID)
	require.NoError(t, err)
	require.Equal(t, headOID, gitaccess.NewObjectIDFromBytes(dbRepo.CommitOID))
	require.Equal(t, initialCommitSeqNo, uint64(dbRepo.CommitSeqNo.Int64), "CommitSeqNo incremented unexpected number of times")

	// The ingest requires two Index RPCs (since the first request fails) but is
	// successfully finalized after the second attempt.
	require.Equal(t, 2, fakeIndexAPI.IndexCallCount())
	_, req := fakeIndexAPI.IndexArgsForCall(0)
	require.Equal(t, initialCommitSeqNo, req.CommitSeqNo)
	_, req = fakeIndexAPI.IndexArgsForCall(1)
	require.Equal(t, initialCommitSeqNo, req.CommitSeqNo)
	require.Equal(t, 1, fakeIndexAPI.FinalizeCallCount())
}

// This tests simulates the index having a lower commit sequence number than the
// ingest process. It does this by making the first Index RPC succeed but the
// first Diff RPC fail. This requires a retry. Meanwhile, the repo's sequence
// number is driven up, simulating a change from another process.
func Test_indexapiStopsRetriesAfterIndexerCommitSeqNoMatchesInitialCommitSeqNo(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	headOID := helpers.UniqueOID(t)
	repo := helpers.Repositories(t, 1)[0]
	repo.CommitOID = headOID.Bytes()
	store := noop.New(repo)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)

	var initialCommitSeqNo uint64

	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		if initialCommitSeqNo == 0 {
			initialCommitSeqNo = req.CommitSeqNo
		}
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId,    // Must match req for ingest to finish
			CommitSeqNo:    initialCommitSeqNo, // Must match or exceed initial commit seq no
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	// Set up a stub that will cause the first ingest to fail. As a sneaky side
	// effect, it also increase the repo's commit sequence number. This will
	// cause the second ingest attempt to have a larger commit sequence number
	// than the indexer.
	fakeGitClient := mockGitClient(t, headOID)
	fakeGitClient.DiffStub = func(ctx context.Context, i int, t1, t2 *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
		// fail the first call and increment the repo seq no
		if fakeGitClient.DiffCallCount() == 1 {
			result, rsErr := store.RepositorySequence(ctx, repo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
				// NOTE: This returns a new head OID, so that the commit sequence number will increment.
				return nil, helpers.GitHubRepositoryFromRepository(t, repo), &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}, nil
			})
			require.NoError(t, rsErr)
			require.Greater(t, uint64(result.Repository.CommitSeqNo.Int64), initialCommitSeqNo, "commit sequence number should have incremented")

			return nil, errors.New("unexpected error, should retry ingest")
		}

		return gitaccess.RepoDiff{
			repo.RepoID: []*gitaccess.DiffEntry{
				{Path: "foo.txt", OID: helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), Change: gitaccess.Add},
				{Path: "bar.txt", OID: helpers.OID(t, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"), Change: gitaccess.Add},
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		fakeGitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
		BlackbirdSuggestedChildId: 999,
		BlackbirdAncestorRepoIds:  []uint32{111, 222, 333},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// Database increments the sequence number three times: one for first ingest attempt, one for my hack, one for second ingest attempt
	dbRepo, err := store.GetRepositoryByID(ctx, repo.RepoID)
	require.NoError(t, err)
	require.Equal(t, headOID, gitaccess.NewObjectIDFromBytes(dbRepo.CommitOID))
	require.Equal(t, initialCommitSeqNo+2, uint64(dbRepo.CommitSeqNo.Int64), "CommitSeqNo incremented unexpected number of times")

	// The ingest requires two Index RPCs (since the first ingest fails) but is
	// successfully finished with a single finalize call.
	require.Equal(t, 2, fakeIndexAPI.IndexCallCount())
	_, req := fakeIndexAPI.IndexArgsForCall(0)
	require.Equal(t, initialCommitSeqNo, req.CommitSeqNo)
	_, req = fakeIndexAPI.IndexArgsForCall(1)
	require.Equal(t, initialCommitSeqNo+2, req.CommitSeqNo, "expected second Index RPC to use larger commit sequence number")
	require.Equal(t, 1, fakeIndexAPI.FinalizeCallCount())
}

// If the index API tells us to use a parent repo and parent commit, we do.
func Test_indexapiUseParentRepoAndCommit(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repos := helpers.Repositories(t, 2)
	repo := repos[0]
	parentRepo := repos[1]
	store := noop.New(repos...)

	const entry = uint64(123)
	barrier := &blackbird_entities.TopicBarrier{
		PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
			{
				Partition: 0,
				Offset:    1,
			},
		},
		TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
	}

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:   &servingpb.ServingStatus{},
			IngestStatus:    indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:         entry,
			CommitSeqNo:     req.CommitSeqNo, // must match req to finish
			RepoSeqNo:       req.Repo.RepoSeqNo,
			RepoId:          uint32(repo.RepoID), // must match req to finish
			CommitSha:       repo.CommitOID,
			ParentRepoId:    uint32(parentRepo.RepoID),
			ParentCommitSha: parentRepo.CommitOID,
			LeaseTimestamp:  uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier:         barrier,
		}, nil
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	fakeGitClient := mockGitClient(t, gitaccess.NewObjectIDFromBytes(repo.CommitOID))

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repos...),
		fakeGitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// N cache RPCs * 1 repo
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount(), "expected 1 index RPC per each repo")
	require.Equal(t, 1, fakeIndexAPI.FinalizeCallCount(), "expected 1 finalize RPC per each repo")
	require.Equal(t, 2, fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of blobs in both repos")

	// Diff Tree RPC should include parent ID and commit
	require.Equal(t, 1, fakeGitClient.DiffCallCount())
	_, _, treeishA, treeishB := fakeGitClient.DiffArgsForCall(0)
	require.Equal(t, parentRepo.RepoID, treeishA.RepoID)
	require.Equal(t, gitaccess.NewObjectIDFromBytes(parentRepo.CommitOID).String(), treeishA.Treeish.GetOid().GetId())
	require.Equal(t, repo.RepoID, treeishB.RepoID)
	require.Equal(t, gitaccess.NewObjectIDFromBytes(repo.CommitOID).String(), treeishB.Treeish.GetOid().GetId())

	_, freq := fakeIndexAPI.FinalizeArgsForCall(0)
	require.EqualValues(t, repo.RepoID, freq.RepoId)
	require.Equal(t, entry, freq.EntryId, "expected repo's entry to finalize")

	// Calls should include barrier
	_, preq := fakeCache.PublishCacheDocumentArgsForCall(0)
	require.Equal(t, barrier, preq.GitDocument.TreeUpdateBarrier)
	_, preq = fakeCache.PublishCacheDocumentArgsForCall(1)
	require.Equal(t, barrier, preq.GitDocument.TreeUpdateBarrier)
}

// Sometimes the index API may tell us to crawl a different entry ID. We need to
// crawl it, and then crawl the one we started with.
func Test_indexapiReturnsAnotherEntryToCrawl(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repos := helpers.Repositories(t, 2)
	repoA := repos[0]
	repoB := repos[1]
	store := noop.New(repos...)
	headOID := helpers.UniqueOID(t)

	const entryA = uint64(123)
	const entryB = uint64(456)
	barrierA := &blackbird_entities.TopicBarrier{
		PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
			{
				Partition: 0,
				Offset:    2,
			},
		},
		TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
	}
	barrierB := &blackbird_entities.TopicBarrier{
		PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
			{
				Partition: 0,
				Offset:    1,
			},
		},
		TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
	}

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		// first call for repo A => index repo B
		if fakeIndexAPI.IndexCallCount() == 1 && req.Repo.RepoId == uint32(repoA.RepoID) {
			return &indexpb.IndexResponse{
				ServingStatus:  &servingpb.ServingStatus{},
				IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
				EntryId:        entryB,
				CommitSeqNo:    123,
				RepoSeqNo:      123,
				RepoId:         uint32(repoB.RepoID),
				CommitSha:      headOID.Bytes(),
				LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
				Barrier:        barrierB,
			}, nil
		}

		if fakeIndexAPI.IndexCallCount() == 2 && req.Repo.RepoId == uint32(repoA.RepoID) {
			return &indexpb.IndexResponse{
				ServingStatus:  &servingpb.ServingStatus{},
				IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
				EntryId:        entryA,
				RepoId:         uint32(repoA.RepoID), // Must match req to finish
				CommitSeqNo:    req.CommitSeqNo,      // Must match req to finish
				RepoSeqNo:      req.Repo.RepoSeqNo,
				CommitSha:      headOID.Bytes(),
				LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
				Barrier:        barrierA,
			}, nil

		}

		return nil, fmt.Errorf("unexpected repo %d or call count %d", req.Repo.RepoId, fakeIndexAPI.IndexCallCount())
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repos...),
		mockGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repoA.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// N cache RPCs * N repos
	require.Equal(t, 2, fakeIndexAPI.IndexCallCount(), "expected 1 index RPC per each repo")
	require.Equal(t, 2, fakeIndexAPI.FinalizeCallCount(), "expected 1 finalize RPC per each repo")
	require.Equal(t, 4, fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of blobs in both repos")

	_, freq := fakeIndexAPI.FinalizeArgsForCall(0)
	require.EqualValues(t, repoB.RepoID, freq.RepoId, "expected repoB to be included in first finalize RPC")
	require.Equal(t, entryB, freq.EntryId, "expected repoB's entry to finalize first")

	_, freq = fakeIndexAPI.FinalizeArgsForCall(1)
	require.EqualValues(t, repoA.RepoID, freq.RepoId, "expected repoA to be included in second finalize RPC")
	require.Equal(t, entryA, freq.EntryId, "expected repoA's entry to finalize second")

	// First two calls should be to repoB
	_, preq := fakeCache.PublishCacheDocumentArgsForCall(0)
	require.Equal(t, barrierB, preq.GitDocument.TreeUpdateBarrier)
	_, preq = fakeCache.PublishCacheDocumentArgsForCall(1)
	require.Equal(t, barrierB, preq.GitDocument.TreeUpdateBarrier)

	// Second two calls should be to repoA
	_, preq = fakeCache.PublishCacheDocumentArgsForCall(2)
	require.Equal(t, barrierA, preq.GitDocument.TreeUpdateBarrier)
	_, preq = fakeCache.PublishCacheDocumentArgsForCall(3)
	require.Equal(t, barrierA, preq.GitDocument.TreeUpdateBarrier)
}

// Failure to get the base commit from the parent repo should result in retrying
// the crawl. This test is written as if the indexer gave us a new base, which
// is then used.
func Test_indexapiBaseCommitNotFoundRetries(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repos := helpers.Repositories(t, 2)
	repo := repos[0]
	parentRepo := repos[1]
	store := noop.New(repos...)
	baseOID := helpers.UniqueOID(t)
	headOID := helpers.UniqueOID(t)
	blobOID := helpers.UniqueOID(t)

	const (
		parentEntry = uint64(123) // Will be purged by the indexer
		entryA      = uint64(456) // First entry ID returned by the indexer
		entryB      = uint64(789) // Second entry ID returned by the indexer
	)
	barrierA := &blackbird_entities.TopicBarrier{
		PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
			{
				Partition: 0,
				Offset:    2,
			},
		},
		TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
	}
	barrierB := &blackbird_entities.TopicBarrier{
		PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
			{
				Partition: 0,
				Offset:    1,
			},
		},
		TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
	}

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		// first call for repo => returns a parent entry which will be not found
		if fakeIndexAPI.IndexCallCount() == 1 {
			return &indexpb.IndexResponse{
				ServingStatus:            &servingpb.ServingStatus{},
				IngestStatus:             indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
				EntryId:                  entryA,
				CommitSeqNo:              req.CommitSeqNo,
				RepoSeqNo:                req.Repo.RepoSeqNo,
				RepoId:                   req.Repo.RepoId,
				CommitSha:                req.CommitSha,
				ParentRepoId:             uint32(parentRepo.RepoID),
				ParentCommitSha:          baseOID.Bytes(),
				ParentEntryId:            parentEntry,
				ParentGeometricXorFilter: []byte{},
				LeaseTimestamp:           uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
				Barrier:                  barrierA,
			}, nil
		}

		// Second call for repo => returns no parent entry (the indexer tells us to ingest from scratch)
		if fakeIndexAPI.IndexCallCount() == 2 {
			return &indexpb.IndexResponse{
				ServingStatus:  &servingpb.ServingStatus{},
				IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
				EntryId:        entryB,
				CommitSeqNo:    req.CommitSeqNo,
				RepoSeqNo:      req.Repo.RepoSeqNo,
				RepoId:         req.Repo.RepoId,
				CommitSha:      req.CommitSha,
				LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
				Barrier:        barrierB,
			}, nil
		}

		return nil, fmt.Errorf("unexpected call count %d", fakeIndexAPI.IndexCallCount())
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	fakeGitClient := &gitaccessfakes.FakeClient{}
	fakeGitClient.GetDefaultRefReturns(&gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: headOID}, nil)
	fakeGitClient.DiffStub = func(ctx context.Context, locationLimit int, base, head *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
		// first call: base repo fails
		if fakeGitClient.DiffCallCount() == 1 {
			return nil, spokesd.WrapInvalidDiffBaseError(
				twirp.NotFoundError(fmt.Sprintf("object %s not found", base.Treeish.GetOid().Id)), "base object not found",
			)
		}

		// second call: success
		if fakeGitClient.DiffCallCount() == 2 {
			return gitaccess.RepoDiff{head.RepoID: []*gitaccess.DiffEntry{{Path: "file", OID: blobOID, Change: gitaccess.Add}}}, nil
		}

		return nil, fmt.Errorf("unexpected call count %d", fakeGitClient.DiffCallCount())
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repos...),
		fakeGitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	require.Equal(t, 2, fakeIndexAPI.IndexCallCount(), "expected 1 index RPC per each attempt")
	require.Equal(t, 2, fakeIndexAPI.FinalizeCallCount(), "expected 1 finalize call for invalidating entry and 1 for successful attempt crawl")
	require.Equal(t, 1, fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of blobs in the diff")

	_, freq := fakeIndexAPI.FinalizeArgsForCall(0)
	require.EqualValues(t, repo.RepoID, freq.RepoId)
	require.Equal(t, entryA, freq.EntryId, "expected entryA to finalize first")
	require.Equal(t, indexpb.IngestStatus_INGEST_STATUS_COMMIT_NOT_FOUND, freq.IngestStatus, "expected entryA to be marked commit not found")

	_, freq = fakeIndexAPI.FinalizeArgsForCall(1)
	require.EqualValues(t, repo.RepoID, freq.RepoId)
	require.Equal(t, entryB, freq.EntryId, "expected entryB to finalize second")
	require.Equal(t, indexpb.IngestStatus_INGEST_STATUS_SUCCESS, freq.IngestStatus, "expected entryB to be successful")

	// We publish one cache document for the successful repo
	_, preq := fakeCache.PublishCacheDocumentArgsForCall(0)
	require.Equal(t, barrierB, preq.GitDocument.TreeUpdateBarrier)
}

// When an Index RPC returns deadline_exceeded, we retry from the top.
func Test_indexapiIndexerDeadlineExceededRetries(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		if fakeIndexAPI.IndexCallCount() == 1 {
			return nil, twirp.NewError(twirp.DeadlineExceeded, "index RPC expired")
		}

		if fakeIndexAPI.IndexCallCount() == 2 {
			return &indexpb.IndexResponse{
				ServingStatus:  &servingpb.ServingStatus{},
				IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
				EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
				RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
				CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
				RepoSeqNo:      req.Repo.RepoSeqNo,
				CommitSha:      headOID.Bytes(),
				LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
				Barrier: &blackbird_entities.TopicBarrier{
					PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
						{
							Partition: 0,
							Offset:    int64(fakeIndexAPI.IndexCallCount()),
						},
					},
					TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
				},
			}, nil
		}

		return nil, fmt.Errorf("unexpected call count %d", fakeIndexAPI.IndexCallCount())
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()
	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		mockGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// There should be two calls, and the ExpiresAt of the second call should be after the first one.
	require.Equal(t, 2, fakeIndexAPI.IndexCallCount())
	_, req0 := fakeIndexAPI.IndexArgsForCall(0)
	_, req1 := fakeIndexAPI.IndexArgsForCall(1)
	require.Greater(t, req1.ExpiresAt, req0.ExpiresAt)

	// N cache RPCs
	require.Equal(t, 2, fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of blobs")
}

// When a Git RPC errors with too-many-processes, we retry from the top.
func Test_indexapiGitmonTooManyProcessesRetries(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match req for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()
	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	fakeGitClient := mockGitClient(t, headOID)
	fakeGitClient.GetDefaultRefStub = func(ctx context.Context, repoID types.RepoID) (*gitaccess.RefTip, error) {
		// first attempt fails with gitmon error
		if fakeGitClient.GetDefaultRefCallCount() == 1 {
			return nil, spokesd.WrapGitmonTooManyProcessesError(fmt.Errorf("gitmon: too-many-processes"), "gitmon has a sad")
		}
		// subsequent attempts succeed
		return &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: headOID}, nil
	}

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		fakeGitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}

	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// We expect GetDefaultRef to be called twice
	require.Equal(t, 2, fakeGitClient.GetDefaultRefCallCount())

	// We only call Index once, because we don't call it until the RepositorySequence succeeds
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())

	// N cache RPCs
	require.Equal(t, 2, fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of blobs")
}

func Test_indexapiCrawlFailsDueToGitBlobsError(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}
	fakeIndexAPI.PermanentErrorStub = func(ctx context.Context, req *indexpb.PermanentErrorRequest) (*indexpb.PermanentErrorResponse, error) {
		return &indexpb.PermanentErrorResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       &blackbird_entities.TopicBarrier{},
		}, nil
	}

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		mockCrawlPoolWithEmptyCache(t),
		mockGitHubClient(t, repo),
		mockFailingGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}

	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, 0), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.Nil(t, skip)
	require.NoError(t, err, "operation should not fail")

	// We expect one index RPC calls (because this error is classified as fatal)
	// and a one PermanentError RPC
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())
	require.Equal(t, 1, fakeIndexAPI.PermanentErrorCallCount())
	require.Equal(t, 0, fakeIndexAPI.FinalizeCallCount())
	_, ireq := fakeIndexAPI.IndexArgsForCall(0)
	indexRPCSeqNo := ireq.CommitSeqNo
	_, preq := fakeIndexAPI.PermanentErrorArgsForCall(0)
	require.EqualValues(t, repo.RepoID, preq.RepoId)
	require.Equal(t, indexRPCSeqNo, preq.CommitSeqNo, "expected the sequence number to be re-used")
	require.Equal(t, "bad-commit: test failure", preq.PermanentError)
	require.Equal(t, "", preq.Nwo, "expected NWO to be empty because the IndexResponse does not contain one")
}

func Test_indexapiDiffLocationLimitExceededIsPermanentError(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	gitClient := mockGitClient(t, headOID)
	gitClient.DiffStub = func(ctx context.Context, locationLimit int, head, base *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
		return nil, spokesd.LocationLimitExceededError
	}

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}
	fakeIndexAPI.PermanentErrorStub = func(ctx context.Context, req *indexpb.PermanentErrorRequest) (*indexpb.PermanentErrorResponse, error) {
		return &indexpb.PermanentErrorResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       &blackbird_entities.TopicBarrier{},
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		gitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// One Index RPC
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())
	_, ireq := fakeIndexAPI.IndexArgsForCall(0)
	indexRPCSeqNo := ireq.CommitSeqNo

	// One PermanentError RPC with a "system limit" permanent failure
	require.Equal(t, 1, fakeIndexAPI.PermanentErrorCallCount())
	_, req := fakeIndexAPI.PermanentErrorArgsForCall(0)
	require.EqualValues(t, repo.RepoID, req.RepoId)
	require.Equal(t, indexRPCSeqNo, req.CommitSeqNo, "sequence number should be reused from Index RPC")
	require.Equal(t, blackbird_entities.PermanentErrorType_SYSTEM_LIMIT, req.PermanentErrorType)
	require.Equal(t, "system-limit: location limit exceeded", req.PermanentError)
	require.Equal(t, "", req.Nwo, "permanent errors after starting crawl should not send NWO")

	// No cache RPCs
	require.Equal(t, 0, fakeCache.PublishCacheDocumentCallCount())
}

func Test_indexapiInvalidDocumentIsPermanentError(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	gitClient := mockGitClient(t, headOID)
	gitClient.DiffStub = func(ctx context.Context, locationLimit int, head, base *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
		return gitaccess.RepoDiff{
			base.RepoID: []*gitaccess.DiffEntry{
				{
					Path:   "really_small.txt", // if this is less than 3 bytes it'll trigger an error
					OID:    helpers.UniqueOID(t),
					Change: gitaccess.Add,
				},
			},
		}, nil
	}
	gitClient.GetBlobsForDiffStub = func(ctx context.Context, cancel context.CancelFunc, rd gitaccess.RepoDiff, f func(*gitaccess.BlobContentChange)) error {
		changes := rd.BlobOIDChanges()
		for _, change := range changes {
			blob := &gitaccess.BlobContentChange{
				ObjectID:      change.ObjectID,
				Content:       []byte("a"), // Content is too small to index
				BlobLocations: change.BlobLocations,
			}
			f(blob)
		}

		return nil
	}

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}
	fakeIndexAPI.PermanentErrorStub = func(ctx context.Context, req *indexpb.PermanentErrorRequest) (*indexpb.PermanentErrorResponse, error) {
		return &indexpb.PermanentErrorResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       &blackbird_entities.TopicBarrier{},
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		return &cachepb.PublishCacheDocumentResponse{
			Published: nil, // cache miss
		}, nil
	}

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		gitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// One Index RPC
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())
	_, ireq := fakeIndexAPI.IndexArgsForCall(0)
	indexRPCSeqNo := ireq.CommitSeqNo

	// One PermanentError RPC with a "system limit" permanent failure
	require.Equal(t, 1, fakeIndexAPI.PermanentErrorCallCount())
	_, req := fakeIndexAPI.PermanentErrorArgsForCall(0)
	require.EqualValues(t, repo.RepoID, req.RepoId)
	require.Equal(t, indexRPCSeqNo, req.CommitSeqNo, "sequence number should be reused from Index RPC")
	require.Equal(t, blackbird_entities.PermanentErrorType_RETRIES_EXHAUSTED, req.PermanentErrorType)
	require.Equal(t, "retries-exhausted: cannot create document less than 3 bytes (got 1)", req.PermanentError)
	require.Equal(t, "", req.Nwo, "permanent errors after starting crawl should not send NWO")

	// One cache miss RPCs, no cache publish RPCs
	require.Equal(t, 1, fakeCache.PublishCacheDocumentCallCount())
	require.Equal(t, 0, fakeCache.PublishDocumentCallCount())
}

func Test_indexapiMarkRepositoryDeleted(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New()
	headOID := helpers.UniqueOID(t)

	cacheClusters := helpers.CacheClusters(t)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:    req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	fakeIndexAPI.DeleteRepositoryReturns(&indexpb.DeleteRepositoryResponse{ServingStatus: &servingpb.ServingStatus{}}, nil)
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	githubClient := &githubfakes.FakeInternalAPIClient{}
	githubClient.GetRepositoryReturns(nil, github.ErrRepoBlocked)

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		githubClient,
		nil, // git client
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	require.Equal(t, 0, fakeIndexAPI.IndexCallCount(), "expected no Index RPCs")
	require.Equal(t, 0, fakeIndexAPI.FinalizeCallCount(), "expected no finalize RPCs")
	require.Equal(t, 1, fakeIndexAPI.DeleteRepositoryCallCount())

	_, deleteRepoReq := fakeIndexAPI.DeleteRepositoryArgsForCall(0)
	require.Equal(t, uint64(1), deleteRepoReq.CommitSeqNo)
	require.Equal(t, uint64(0), deleteRepoReq.RepoSeqNo)

	repo, err = store.GetFirstRepository(ctx, repofilter.ID(repo.RepoID))
	require.NoError(t, err)
	require.NotNil(t, repo, "not found: %+v", store.Repos)
	require.True(t, repo.IsDeleted(), "repo should have been marked deleted in store")
}

func Test_indexapiCommitAlreadyIngested(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	headOID := helpers.UniqueOID(t)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_SUCCESS,
			EntryId:        uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:         req.Repo.RepoId,
			CommitSeqNo:    req.CommitSeqNo,
			RepoSeqNo:      req.Repo.RepoSeqNo,
			CommitSha:      headOID.Bytes(),
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	cacheClient, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, cacheClient, 0)

	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repo),
		mockGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// Just one Index RPC, nothing else.
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())
	require.Equal(t, 0, fakeIndexAPI.FinalizeCallCount())
	require.Equal(t, 0, fakeCache.PublishCacheDocumentCallCount())
}

func Test_indexapiCancel(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(nil, context.Canceled)

	headOID := helpers.UniqueOID(t)
	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		mockCrawlPoolWithEmptyCache(t),
		mockGitHubClient(t, repo),
		mockGitClient(t, headOID),
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)

	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	cancel() // cancel the context to simulate a deploy

	buf := NewBufferOp(op)
	buf.Run(task)
	require.Equal(t, len(buf.doneTasks), 1)
	require.Error(t, buf.doneTasks[0].err, "we expect context cancellation to error the task")
	require.ErrorIs(t, buf.doneTasks[0].err, context.Canceled)
}

// This test simulates an error that happens repeatedly before the Index RPC can be sent.]
// The PermanentError will include an NWO because we were able to resolve the repo.
func Test_indexapiRetriesExhaustedPermanentError(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	repo.CommitSeqNo = sql.NullInt64{Int64: 2, Valid: true}
	repo.RepoSeqNo = sql.NullInt64{Int64: 2, Valid: true}
	store := noop.New(repo)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.PermanentErrorReturns(
		&indexpb.PermanentErrorResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       &blackbird_entities.TopicBarrier{},
		},
		nil,
	)

	headOID := helpers.UniqueOID(t)
	mockGitClient := mockGitClient(t, headOID)
	mockGitClient.GetDefaultRefReturns(nil, errors.New("unexpected error"))

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		mockCrawlPoolWithEmptyCache(t),
		mockGitHubClient(t, repo),
		mockGitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		1, // == 2 attempts
	)

	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repo.RepoID),
		},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	buf := NewBufferOp(op)
	buf.Run(task)
	require.Equal(t, len(buf.doneTasks), 1)
	require.NoError(t, buf.doneTasks[0].err, "exhausting retries should be a successful task outcome")

	// We expect exhausting retries to send one error which should have an NWO,
	// along with the commit and repo sequence numbers.
	require.Equal(t, 1, fakeIndexAPI.PermanentErrorCallCount())
	_, req := fakeIndexAPI.PermanentErrorArgsForCall(0)
	require.Equal(t, repo.NWO(), req.Nwo, "permanent error should contain NWO because it was resolved")
	require.Equal(t, uint64(3), req.CommitSeqNo, "commit sequence number should be 3") // CommitSeqNo is incremented on permanent error.
	require.Equal(t, uint64(2), req.RepoSeqNo, "repo sequence number should be 2")     // RepoSeqNo is not incremented on permanent error.
}

//go:embed repo_475454893_a4394bba_diff_repo_481331442_4300d8ee.txt
var diffTree string

// Test with real example that resulted in missing documents.
// See https://github.com/github/blackbird-mw/issues/1963
func Test_indexapiExcessDocumentsTest(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repos := helpers.Repositories(t, 2)
	baseRepo := repos[0]
	headRepo := repos[1]
	store := noop.New(baseRepo, headRepo)
	baseOID := helpers.OID(t, "a4394bba26bf76fd929568862b142de27b70d0f0")
	headOID := helpers.OID(t, "4300d8ee8dc7e554930ce0430585d681b92e0941")
	head := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: headOID}
	gitClient := &gitaccessfakes.FakeClient{}
	gitClient.GetBlobsForDiffStub = func(ctx context.Context, cancel context.CancelFunc, rd gitaccess.RepoDiff, f func(*gitaccess.BlobContentChange)) error {
		changes := rd.BlobOIDChanges()
		for i, change := range changes {
			blob := &gitaccess.BlobContentChange{
				ObjectID:      change.ObjectID,
				Content:       []byte(fmt.Sprintf("blob %d", i)),
				BlobLocations: change.BlobLocations,
			}
			f(blob)
		}

		return nil
	}
	gitClient.GetDefaultRefReturns(head, nil)
	gitClient.DiffStub = func(ctx context.Context, locationLimit int, t1, t2 *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
		return repoDiffFromDiffTree(t, diffTree, baseRepo.RepoID, headRepo.RepoID), nil
	}

	targetDeletes := map[gitaccess.ObjectID]string{
		helpers.OID(t, "f3069fd6f87183c1e9c9d566ad56c9df13f85fa6"): "argo-cd-apps/overlays/staging/kustomization.yaml",
		helpers.OID(t, "a93cc2dd9b00997bdc967aa2723e9e8fc5abe5b3"): "components/spi-vault/kustomization.yaml",
		helpers.OID(t, "9e835d18bf8553500698fa2be70adf419797f178"): "argo-cd-apps/overlays/development/kustomization.yaml",
		helpers.OID(t, "91deff051ac55202d7fbb56966292f3f115fab37"): "components/spi/overlays/staging/base/kustomization.yaml",
		helpers.OID(t, "74ed4e20500b51c2ec5c57dd154bd70398a6bbcc"): "components/monitoring/grafana/base/spi/kustomization.yaml",
		helpers.OID(t, "25bdbea061fdc1adb7537205bd95b26a612f1ace"): "components/spi/overlays/development/kustomization.yaml",
	}

	foundDeletes := map[gitaccess.ObjectID]int{
		helpers.OID(t, "f3069fd6f87183c1e9c9d566ad56c9df13f85fa6"): 0,
		helpers.OID(t, "a93cc2dd9b00997bdc967aa2723e9e8fc5abe5b3"): 0,
		helpers.OID(t, "9e835d18bf8553500698fa2be70adf419797f178"): 0,
		helpers.OID(t, "91deff051ac55202d7fbb56966292f3f115fab37"): 0,
		helpers.OID(t, "74ed4e20500b51c2ec5c57dd154bd70398a6bbcc"): 0,
		helpers.OID(t, "25bdbea061fdc1adb7537205bd95b26a612f1ace"): 0,
	}

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	fakeIndexAPI.GetPermanentErrorReturns(
		&indexpb.GetPermanentErrorResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			PermanentError: "",
		},
		nil,
	)
	fakeIndexAPI.IndexStub = func(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
		return &indexpb.IndexResponse{
			ServingStatus:   &servingpb.ServingStatus{},
			IngestStatus:    indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
			EntryId:         uint64(fakeIndexAPI.IndexCallCount()),
			RepoId:          req.Repo.RepoId, // Must match req for ingest to finish
			CommitSeqNo:     req.CommitSeqNo, // Must match or exceed initial CommitSeqNo for ingest to finish
			RepoSeqNo:       req.Repo.RepoSeqNo,
			CommitSha:       headOID.Bytes(),
			ParentRepoId:    uint32(baseRepo.RepoID),
			ParentCommitSha: baseOID.Bytes(),
			LeaseTimestamp:  uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			Barrier: &blackbird_entities.TopicBarrier{
				PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{
					{
						Partition: 0,
						Offset:    int64(fakeIndexAPI.IndexCallCount()),
					},
				},
				TopicId: blackbird_entities.TopicBarrier_SNAPSHOT,
			},
		}, nil
	}
	fakeIndexAPI.FinalizeStub = func(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
		return &indexpb.FinalizeResponse{
			ServingStatus: &servingpb.ServingStatus{},
			Barrier:       req.Barrier,
		}, nil
	}
	fakeIndexAPI.LeaseStub = func(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
		return &indexpb.LeaseResponse{
			ServingStatus:  &servingpb.ServingStatus{},
			LeaseTimestamp: uint64(time.Now().UTC().Add(10 * time.Minute).UnixMilli()),
			IngestStatus:   indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS,
		}, nil
	}

	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, client, 0)
	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		oid := gitaccess.NewObjectIDFromBytes(req.GitDocument.ContentSha)
		if path, ok := targetDeletes[oid]; ok {
			for _, loc := range req.GitDocument.Locations {
				if loc.Path == path {
					foundDeletes[oid] = foundDeletes[oid] + 1
				}
			}
		}

		return &cachepb.PublishCacheDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount() + fakeCache.PublishDeleteDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}
	fakeCache.PublishDeleteDocumentStub = func(ctx context.Context, req *cachepb.PublishDeleteDocumentRequest) (*cachepb.PublishDeleteDocumentResponse, error) {
		oid := gitaccess.NewObjectIDFromBytes(req.GitDocument.ContentSha)
		if path, ok := targetDeletes[oid]; ok {
			for _, loc := range req.GitDocument.Locations {
				if loc.Path == path {
					foundDeletes[oid] = foundDeletes[oid] + 1
				}
			}
		}

		return &cachepb.PublishDeleteDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishCacheDocumentCallCount() + fakeCache.PublishDeleteDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}
	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	defer crawlPool.Close()

	topic := corpus.EpochBackfillTopic(123)
	partition := helpers.KafkaPartition(t, headRepo.RepoID)

	op := NewIndexAPIIngestOp(
		helpers.MockOffsetTracker(t, topic, partition),
		crawlPool,
		mockGitHubClient(t, repos...),
		gitClient,
		store,
		indexerCluster,
		routing.TopicConfig{},
		defaultMaxIngestAttempts,
	)

	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id:      uint32(headRepo.RepoID),
			OwnerId: &wrapperspb.UInt32Value{Value: headRepo.OwnerID},
		},
		BlackbirdAncestorRepoIds: []uint32{uint32(baseRepo.RepoID)},
	}
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestWithRetry(ctx, task)
	require.NoError(t, err)
	require.Nil(t, skip)

	// One Index RPC, with the head repo
	require.Equal(t, 1, fakeIndexAPI.IndexCallCount())
	_, req := fakeIndexAPI.IndexArgsForCall(0)
	require.Equal(t, uint32(headRepo.RepoID), req.Repo.RepoId)
	require.Equal(t, headOID.Bytes(), req.CommitSha)
	require.Equal(t, "refs/heads/main", req.RefName)

	// One finalize RPC
	require.Equal(t, 1, fakeIndexAPI.FinalizeCallCount())

	// There are 637 unique blobs in the diff, but one is excluded
	const validBlobs = 636
	require.Equal(t, validBlobs, fakeCache.PublishDeleteDocumentCallCount()+fakeCache.PublishCacheDocumentCallCount(), "with a full cache, RPCs should equal number of non-excluded blobs")

	for oid, count := range foundDeletes {
		require.Equal(t, 1, count, "invalid RPC count for blob %s", oid.String())
	}
}

func Test_skipNotTargetCorpus(t *testing.T) {
	ctx := context.Background()
	repoID := helpers.RepoID(t)
	corpus := helpers.Corpus(t)
	otherCorpus := helpers.OtherCorpus(t, corpus)
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repoID),
		},
		BlackbirdTargetCorpus: otherCorpus.String(),
	}
	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repoID)
	op := NewIndexAPIIngestOp(helpers.MockOffsetTracker(t, topic, partition), nil, nil, nil, nil, nil, routing.TopicConfig{}, 0)
	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: corpus, IngestMode: db.IngestModeBackfill}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestInner(ctx, task)
	require.NoError(t, err)
	require.NotNil(t, skip)
	require.Equal(t, db.SkipNotTargetCorpus, *skip)
	require.Equal(t, unknownCommitSeqNo, task.initialCommitSeqNo)
}

func Test_skipBannedRepository(t *testing.T) {
	ctx := context.Background()
	var repoID types.RepoID
	for id := range repoDenyList[routing.Dotcom] {
		repoID = id
		break
	}
	require.NotZero(t, repoID, "failed to pick a banned repo")
	event := &pb.RepositoryChanged{
		Repository: &entities.Repository{
			Id: uint32(repoID),
		},
	}
	topic := routing.OnboardSourceTopic
	partition := helpers.KafkaPartition(t, repoID)
	op := NewIndexAPIIngestOp(helpers.MockOffsetTracker(t, topic, partition), nil, nil, nil, nil, nil, routing.TopicConfig{}, 0)

	task, err := NewTask(ctx, hydroMsg(t, event, topic, partition, helpers.KafkaOffset(t)), &db.CorpusState{Corpus: helpers.Corpus(t), IngestMode: db.IngestModeBackfill}, routing.Dotcom)
	require.NoError(t, err)

	skip, err := op.ingestInner(ctx, task)
	require.NoError(t, err)
	require.NotNil(t, skip)
	require.Equal(t, db.SkipRepoDenyList, *skip)
	require.Equal(t, unknownCommitSeqNo, task.initialCommitSeqNo)
}

func Test_skipRepository(t *testing.T) {
	repo := helpers.Repositories(t, 1)[0]
	corpus := helpers.Corpus(t)

	var tests = []struct {
		name      string
		repo      *github.Repository
		state     db.RepoInfoState
		topic     string
		stamp     routing.Stamp
		epochMode epoch.EpochMode
		expected  *db.SkipReason
	}{
		{
			name: "disk size too large (dotcom)",
			repo: &github.Repository{
				ID:        repo.RepoID,
				DiskUsage: 101 * 1024 * 1024 * 1024,
			},
			topic:    routing.OnboardSourceTopic,
			stamp:    routing.Dotcom,
			expected: &db.SkipMaxDiskSize,
		},
		{
			name: "disk size too large (proxima)",
			repo: &github.Repository{
				ID:        repo.RepoID,
				DiskUsage: 101 * 1024 * 1024 * 1024,
			},
			topic:    routing.OnboardSourceTopic,
			stamp:    routing.StaffWUS201,
			expected: &db.SkipMaxDiskSize,
		},
		{
			name: "network is denied (dotcom)",
			repo: &github.Repository{
				ID:        repo.RepoID,
				NetworkID: types.NetworkID(1409811), // on network ban list
			},
			topic:    routing.OnboardSourceTopic,
			stamp:    routing.Dotcom,
			expected: &db.SkipNetworkDenyList,
		},
		{
			name: "network is denied (proxima)",
			repo: &github.Repository{
				ID:        repo.RepoID,
				NetworkID: types.NetworkID(1409811), // on network ban list
			},
			topic:    routing.OnboardSourceTopic,
			stamp:    routing.StaffWUS201,
			expected: nil,
		},
		{
			name: "owner is denied (dotcom)",
			repo: &github.Repository{
				ID:      repo.RepoID,
				OwnerID: 4600091, // on owner ban list
			},
			topic:    routing.OnboardSourceTopic,
			stamp:    routing.Dotcom,
			expected: &db.SkipOwnerDenyList,
		},
		{
			name: "owner is denied (proxima)",
			repo: &github.Repository{
				ID:      repo.RepoID,
				OwnerID: 4600091, // on owner ban list
			},
			topic:    routing.OnboardSourceTopic,
			stamp:    routing.StaffWUS201,
			expected: nil,
		},
		{
			name: "new repo for non-paying customer in incremental topic is skipped",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: false,
			},
			state:    db.RepoInfoStateNew,
			topic:    routing.IncrementalSourceTopic,
			stamp:    routing.Dotcom,
			expected: &db.SkipUnknownRepo,
		},
		{
			name: "existing repo for non-paying customer in incremental topic is not skipped",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: false,
			},
			state:    db.RepoInfoStateExisting,
			topic:    routing.IncrementalSourceTopic,
			stamp:    routing.Dotcom,
			expected: nil,
		},
		{
			name: "new repo for non-paying customer in onboarding topic is not skipped",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: false,
			},
			state:    db.RepoInfoStateNew,
			topic:    routing.OnboardSourceTopic,
			stamp:    routing.Dotcom,
			expected: nil,
		},
		{
			name: "new repo for non-paying customer in backfill topic is not skipped",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: false,
			},
			state:    db.RepoInfoStateNew,
			topic:    corpus.EpochBackfillTopic(123),
			stamp:    routing.Dotcom,
			expected: nil,
		},
		{
			name: "new repo for paying customer in incremental topic is not skipped",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: true,
			},
			state:    db.RepoInfoStateNew,
			topic:    routing.IncrementalSourceTopic,
			stamp:    routing.Dotcom,
			expected: nil,
		},
		{
			name: "repo does not have embeddings enabled",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: true,
				Experiments:    experiments.Experiments{},
			},
			state:     db.RepoInfoStateNew,
			topic:     routing.IncrementalSourceTopic,
			stamp:     routing.Dotcom,
			epochMode: epoch.EpochModeEmbeddings,
			expected:  &db.SkipEmbeddingsDisabled,
		},
		{
			name: "repo has code embeddings enabled",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: true,
				Experiments:    experiments.Experiments{experiments.EnableCodeEmbedding: "1"},
			},
			state:     db.RepoInfoStateNew,
			topic:     routing.IncrementalSourceTopic,
			stamp:     routing.Dotcom,
			epochMode: epoch.EpochModeEmbeddings,
			expected:  nil,
		},
		{
			name: "repo has markdown embeddings enabled",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: true,
				Experiments:    experiments.Experiments{experiments.EnableDocsEmbedding: "1"},
			},
			state:     db.RepoInfoStateNew,
			topic:     routing.IncrementalSourceTopic,
			stamp:     routing.Dotcom,
			epochMode: epoch.EpochModeEmbeddings,
			expected:  nil,
		},
		{
			name: "repo snapshots are always allowed",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: true,
				Experiments:    experiments.Experiments{experiments.EnableCodeEmbedding: "1"},
			},
			state:     db.RepoInfoStateNew,
			topic:     routing.IncrementalSourceTopic,
			stamp:     routing.Dotcom,
			epochMode: epoch.EpochModeLegacyHybrid,
			expected:  nil,
		},
		{
			name: "repo is to be indexed in lexical mode",
			repo: &github.Repository{
				ID:             repo.RepoID,
				PayingCustomer: true,
			},
			state:     db.RepoInfoStateNew,
			topic:     routing.IncrementalSourceTopic,
			stamp:     routing.Dotcom,
			epochMode: epoch.EpochModeLexical,
			expected:  nil,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			skipReason := shouldSkipRepository(test.repo, test.state, test.topic, test.stamp, test.epochMode)
			require.Equal(t, test.expected, skipReason)
		})
	}
}

// Returns a mocked GitHub internal API client that returns repository details
// for the provided repositories if the ID matches. Otherwise it 404s.
func mockGitHubClient(t *testing.T, repos ...*db.Repository) github.InternalAPIClient {
	t.Helper()
	client := &githubfakes.FakeInternalAPIClient{}
	client.GetRepositoryStub = func(ctx context.Context, id types.RepoID) (*github.Repository, error) {
		for _, repo := range repos {
			if id == repo.RepoID {
				return helpers.GitHubRepositoryFromRepository(t, repo), nil
			}
		}

		return nil, twirp.NewError(twirp.NotFound, "no repo")
	}

	return client
}

func mockCrawlPoolWithEmptyCache(t *testing.T) *crawl.WorkPool {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	indexerCluster := helpers.IndexerCluster(t)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fake := helpers.FakeCacheAPI(t, client, 0)

	fake.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		// This is an empty cache, so alway return a miss
		return &cachepb.PublishCacheDocumentResponse{}, nil
	}
	fake.PublishDeleteDocumentStub = func(ctx context.Context, req *cachepb.PublishDeleteDocumentRequest) (*cachepb.PublishDeleteDocumentResponse, error) {
		return &cachepb.PublishDeleteDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fake.PublishDeleteDocumentCallCount() + fake.PublishDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}
	fake.PublishDocumentStub = func(ctx context.Context, req *cachepb.PublishDocumentRequest) (*cachepb.PublishDocumentResponse, error) {
		return &cachepb.PublishDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fake.PublishDeleteDocumentCallCount() + fake.PublishDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}
	const workers = 2
	crawlPool := crawl.NewWorkPool(ctx, indexerCluster, cacheClusters, workers, corpus)
	return crawlPool
}

func repoDiffFromDiffTree(t *testing.T, diffTree string, baseRepo, headRepo types.RepoID) gitaccess.RepoDiff {
	repoDiff := gitaccess.RepoDiff{
		baseRepo: []*gitaccess.DiffEntry{},
		headRepo: []*gitaccess.DiffEntry{},
	}

	lines := strings.Split(diffTree, "\n")
	for _, line := range lines {
		if line == "" {
			continue
		}

		var baseMode uint32
		var headMode uint32
		var baseSHA string
		var headSHA string
		var change string
		var path string

		n, err := fmt.Sscanf(line, ":%d %d %s %s %s	%s", &baseMode, &headMode, &baseSHA, &headSHA, &change, &path)
		require.NoError(t, err)
		require.Equal(t, 6, n, "unsuccessful parse")

		if !(baseMode == 0 || baseMode == 100644 || baseMode == 100755) {
			require.Fail(t, "unexpected base mode: %d", baseMode)
		}

		if !(headMode == 0 || headMode == 100644 || headMode == 100755) {
			require.Fail(t, "unexpected head mode: %d", headMode)
		}

		baseOID := helpers.OID(t, baseSHA)
		headOID := helpers.OID(t, headSHA)

		switch change {
		case "D":
			entry := &gitaccess.DiffEntry{
				Path:   path,
				OID:    baseOID,
				Change: gitaccess.Delete,
			}
			repoDiff[baseRepo] = append(repoDiff[baseRepo], entry)
		case "A":
			entry := &gitaccess.DiffEntry{
				Path:   path,
				OID:    headOID,
				Change: gitaccess.Add,
			}
			repoDiff[headRepo] = append(repoDiff[headRepo], entry)
		case "M":
			entry := &gitaccess.DiffEntry{
				Path:   path,
				OID:    baseOID,
				Change: gitaccess.Delete,
			}
			repoDiff[baseRepo] = append(repoDiff[baseRepo], entry)

			entry = &gitaccess.DiffEntry{
				Path:   path,
				OID:    headOID,
				Change: gitaccess.Add,
			}
			repoDiff[headRepo] = append(repoDiff[headRepo], entry)
		default:
			require.Fail(t, "unexpected modification type: %s", change)
		}
	}

	return repoDiff
}

func mockGitClient(t *testing.T, headOID gitaccess.ObjectID) *gitaccessfakes.FakeClient {
	blobs := []*gitaccess.BlobContentChange{
		{
			ObjectID: helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
			Content:  []byte("hello"),
			BlobLocations: []*gitaccess.BlobLocationEntry{
				{
					Path:   "foo.txt",
					Change: gitaccess.Add,
				},
			},
		},
		{
			ObjectID: helpers.OID(t, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
			Content:  []byte("hello"),
			BlobLocations: []*gitaccess.BlobLocationEntry{
				{
					Path:   "bar.txt",
					Change: gitaccess.Add,
				},
			},
		},
	}

	head := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: headOID}
	gitclient := &gitaccessfakes.FakeClient{}
	gitclient.GetBlobsForDiffStub = func(ctx context.Context, cancel context.CancelFunc, rd gitaccess.RepoDiff, f func(*gitaccess.BlobContentChange)) error {
		// So that `Test_deltaingestCancel` can cancel the context and get production-like behavior.
		if ctx.Err() != nil {
			return ctx.Err()
		}

		for _, blob := range blobs {
			f(blob)
		}
		return nil
	}
	gitclient.GetDefaultRefReturns(head, nil)
	gitclient.GetTreeOIDForCommitReturns(headOID, nil)
	gitclient.DiffReturns(gitaccess.RepoDiff{types.RepoID(1): []*gitaccess.DiffEntry{
		{Path: "foo.txt", OID: helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), Change: gitaccess.Add},
		{Path: "bar.txt", OID: helpers.OID(t, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"), Change: gitaccess.Add},
	}}, nil)
	return gitclient
}

func mockFailingGitClient(t *testing.T, headOID gitaccess.ObjectID) *gitaccessfakes.FakeClient {
	head := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: headOID}
	gitclient := &gitaccessfakes.FakeClient{}
	gitclient.GetBlobsForDiffReturns(spokesd.InvalidCommit("test failure"))
	gitclient.GetDefaultRefReturns(head, nil)
	gitclient.GetTreeOIDForCommitReturns(headOID, nil)
	gitclient.DiffReturns(gitaccess.RepoDiff{types.RepoID(1): []*gitaccess.DiffEntry{
		{Path: "foo.txt", OID: helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), Change: gitaccess.Add},
		{Path: "bar.txt", OID: helpers.OID(t, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"), Change: gitaccess.Add},
	}}, nil)
	return gitclient
}
