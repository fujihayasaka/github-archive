package admin

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/dnaeon/go-vcr/recorder"
	"github.com/github/blackbird/crates/client/pkg/blackbird"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	hydro_bb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	hydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	search_pb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0" //nolint:staticcheck
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/github/client"
	"github.com/github/blackbird-mw/internal/github/githubfakes"
	"github.com/github/blackbird-mw/internal/healthcheck"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
	v1 "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/publish"
	"github.com/github/blackbird-mw/internal/publish/backfill"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_BackfillCreatesEpoch(t *testing.T) {
	ctx := context.Background()
	servingCorpus := routing.Corpora[0]
	backfillCorpus := routing.Corpora[1]
	searchClusters := helpers.SearchClustersWithServingCorpus(t, servingCorpus)
	cacheClusters := helpers.CacheClusters(t)
	indexerClusters := helpers.IndexerClusters(t)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}
	store.CreateEpochStub = func(c1 context.Context, c2 routing.Corpus, s string) (*db.Epoch, error) {
		return &db.Epoch{EpochID: 1, Corpus: c2, Description: s}, nil
	}
	store.GetEpochReturns(&db.Epoch{EpochID: 1, Description: "test"}, nil)

	svc := NewService(
		searchClusters,
		cacheClusters,
		indexerClusters,
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		&githubfakes.FakeInternalAPIClient{},
		&chat.NoopClient{},
		mockClusterAdminProvider(),
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		backfill.NewPublisher(
			store,
			&mocks.FakeSyncProducer{},
			searchClusters,
			cacheClusters,
			&chat.NoopClient{},
			1,
		),
		nil, /* repo publisher */
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil, /* sitesapi */
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	r, err := svc.BackfillCorpus(ctx, &v1.BackfillCorpusRequest{Corpus: backfillCorpus.String(), Bootstrap: true, Reason: "testing"})
	require.NoError(t, err)
	require.Equal(t, uint32(1), r.EpochId)
}

func Test_BackfillSetsCacheClusterIfNotSet(t *testing.T) {
	ctx := context.Background()
	servingCorpus := routing.Corpora[0]
	backfillCorpus := routing.Corpora[1]
	repos := helpers.RepositoriesWithID(t, 3)
	sourceEpoch := types.EpochID(1)

	searchClusters, cacheClusters, _ := helpers.MakeBackfillableCluster(t, repos, servingCorpus, sourceEpoch)
	indexerClusters := helpers.IndexerClusters(t)
	searchClient := searchClusters.ClientForCorpus(backfillCorpus).(*mocks.FakeBlackbirdClient)
	// Don't return cache cluster name first time around, which should trigger setting of cache cluster name
	searchClient.CacheClusterReturnsOnCall(0, "")
	// Second time do return it so that the backfill via mst works
	searchClient.CacheClusterReturnsOnCall(1, routing.CacheClusterNames[0])

	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}
	store.CreateEpochStub = func(c1 context.Context, c2 routing.Corpus, s string) (*db.Epoch, error) {
		return &db.Epoch{EpochID: 2, Corpus: c2, Description: s}, nil
	}
	store.GetEpochReturns(&db.Epoch{EpochID: 1, Description: "test"}, nil)

	client := searchClusters.ClientForCorpus(backfillCorpus).(*mocks.FakeBlackbirdClient)
	client.CacheClusterReturns("")

	svc := NewService(
		searchClusters,
		cacheClusters,
		indexerClusters,
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		&githubfakes.FakeInternalAPIClient{},
		&chat.NoopClient{},
		mockClusterAdminProvider(),
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		backfill.NewPublisher(
			store,
			&mocks.FakeSyncProducer{},
			searchClusters,
			cacheClusters,
			&chat.NoopClient{},
			1,
		),
		nil, /* repo publisher */
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil, /* sitesapi */
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	_, err := svc.BackfillCorpus(ctx, &v1.BackfillCorpusRequest{Corpus: backfillCorpus.String(), Reason: "testing", EpochId: uint32(sourceEpoch)})
	require.NoError(t, err)
	require.Equal(t, 1, client.SetCacheClusterCallCount())
	require.Equal(t, routing.CacheClusterNames[0], client.SetCacheClusterArgsForCall(0))
}

func Test_BackfillManagesTopicsForGivenCorpus(t *testing.T) {
	ctx := context.Background()
	servingCorpus := routing.Corpora[0]
	backfillCorpus := routing.Corpora[1]
	searchClusters := helpers.SearchClustersWithServingCorpus(t, servingCorpus)
	cacheClusters := helpers.CacheClusters(t)
	indexerClusters := helpers.IndexerClusters(t)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}
	store.CreateEpochStub = func(c1 context.Context, c2 routing.Corpus, s string) (*db.Epoch, error) {
		return &db.Epoch{EpochID: 10, Corpus: c2, Description: s}, nil
	}
	store.GetEpochReturns(&db.Epoch{EpochID: 10, Description: "test"}, nil)

	clusterAdmin := &mocks.FakeClusterAdmin{}
	clusterAdmin.ListTopicsReturns(
		map[string]sarama.TopicDetail{
			"blackbird.v1.GitDocument.Green.9":        {}, // should get truncated
			"blackbird.v1.GitDocument.Green.8":        {}, // should get deleted
			"blackbird.v1.GitDocument.Green.7":        {}, // should get deleted
			"blackbird.v1.GitDocument.Blue.6":         {}, // no action
			"blackbird.v1.GitDocument.Blue.5":         {}, // no action
			"blackbird.v1.GitDocumentGreen":           {}, // no action
			"blackbird.v1.GitDocumentBlue":            {}, // no action
			"blackbird.v0.SnapshotTreeUpdateBlue":     {}, // no action
			"blackbird.v0.SnapshotTreeUpdateGreen":    {}, // no action
			"blackbird.v1.SnapshotTreeUpdate.Green.9": {}, // no action (we don't truncate snapshot topics)
			"blackbird.v1.SnapshotTreeUpdate.Green.8": {}, // should get deleted
			"blackbird.v1.SnapshotTreeUpdate.Green.7": {}, // should get deleted
			"blackbird.v1.SnapshotTreeUpdate.Blue.6":  {}, // no action
			"blackbird.v1.SnapshotTreeUpdate.Blue.5":  {}, // no action
			"__consumer_offsets":                      {}, // no action
		},
		nil,
	)
	clusterAdmin.DeleteTopicStub = func(topic string) error {
		t.Logf("deleting topic %q", topic)
		return nil
	}
	clusterAdmin.AlterConfigStub = func(crt sarama.ConfigResourceType, topic string, m map[string]*string, b bool) error {
		t.Logf("modifying topic %q", topic)
		return nil
	}
	clusterAdmin.CreateTopicStub = func(topic string, _ *sarama.TopicDetail, _ bool) error {
		t.Logf("creating topic %q", topic)
		return nil
	}

	provider := func() sarama.ClusterAdmin { return clusterAdmin }

	backfillPublisher := backfill.NewPublisher(store, &mocks.FakeSyncProducer{}, searchClusters, cacheClusters, &chat.NoopClient{}, 1)
	svc := NewService(
		searchClusters,
		cacheClusters,
		indexerClusters,
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		&githubfakes.FakeInternalAPIClient{},
		&chat.NoopClient{},
		provider,
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		backfillPublisher,
		nil,
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil,
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	r, err := svc.BackfillCorpus(ctx, &v1.BackfillCorpusRequest{Corpus: backfillCorpus.String(), Bootstrap: true, Reason: "testing"})
	require.NoError(t, err)
	require.Equal(t, uint32(10), r.EpochId)

	require.Equal(t, 4, clusterAdmin.DeleteTopicCallCount(), "unexpected number of topics deleted")
	require.Equal(t, "blackbird.v1.GitDocument.Green.8", clusterAdmin.DeleteTopicArgsForCall(0))
	require.Equal(t, "blackbird.v1.GitDocument.Green.7", clusterAdmin.DeleteTopicArgsForCall(1))
	require.Equal(t, "blackbird.v1.SnapshotTreeUpdate.Green.8", clusterAdmin.DeleteTopicArgsForCall(2))
	require.Equal(t, "blackbird.v1.SnapshotTreeUpdate.Green.7", clusterAdmin.DeleteTopicArgsForCall(3))

	require.Equal(t, 1, clusterAdmin.AlterConfigCallCount(), "unexpected number of topics altered")
	_, truncatedTopicName, _, _ := clusterAdmin.AlterConfigArgsForCall(0)
	require.Equal(t, "blackbird.v1.GitDocument.Green.9", truncatedTopicName)

	require.Equal(t, 3, clusterAdmin.CreateTopicCallCount(), "unexpected number of topics created")
	outputTopicName, _, _ := clusterAdmin.CreateTopicArgsForCall(0)
	require.Equal(t, "blackbird.v1.GitDocument.Green.10", outputTopicName)
	snapshotTopicName, _, _ := clusterAdmin.CreateTopicArgsForCall(1)
	require.Equal(t, "blackbird.v1.SnapshotTreeUpdate.Green.10", snapshotTopicName)
	backfillTopicName, _, _ := clusterAdmin.CreateTopicArgsForCall(2)
	require.Equal(t, "blackbird.v1.Backfill.Green.10", backfillTopicName)

	// NOTE: It's required to call close on the provided ClusterAdmin, so let's verify that.
	require.Equal(t, 1, clusterAdmin.CloseCallCount())
}

func Test_BackfillDatabaseState(t *testing.T) {
	ctx := context.Background()
	store := noop.New()
	servingCorpus := routing.Corpora[0]
	backfillCorpus := routing.Corpora[1]
	sourceEpoch := types.EpochID(1)
	repos := helpers.RepositoriesWithID(t, 3)

	searchClusters, cacheClusters, _ := helpers.MakeBackfillableCluster(t, repos, servingCorpus, sourceEpoch)
	indexerClusters := helpers.IndexerClusters(t)

	publisher := backfill.NewPublisher(store, &mocks.FakeSyncProducer{}, searchClusters, cacheClusters, &chat.NoopClient{}, 1)
	svc := NewService(
		searchClusters,
		cacheClusters,
		indexerClusters,
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		&githubfakes.FakeInternalAPIClient{},
		&chat.NoopClient{},
		mockClusterAdminProvider(),
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		publisher,
		nil,
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil,
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	resp, err := svc.BackfillCorpus(ctx, &v1.BackfillCorpusRequest{Corpus: backfillCorpus.String(), Reason: "testing", EpochId: uint32(sourceEpoch)})
	require.NoError(t, err)
	require.Equal(t, uint32(1), resp.EpochId)

	// After running backfill
	state, err := store.GetCorpusState(ctx, backfillCorpus)
	require.NoError(t, err)
	require.Equal(t, types.EpochID(1), state.EpochID)

	// NOTE: A delta corpus gets put in Backfill Mode
	require.Equal(t, db.IngestModeBackfill, state.IngestMode)
}

func Test_BackfillDatabaseRequiresEpoch(t *testing.T) {
	ctx := context.Background()
	svc := &adminService{}
	_, err := svc.BackfillCorpus(ctx, &v1.BackfillCorpusRequest{Corpus: helpers.Corpus(t).String()})
	require.EqualError(t, err, "twirp error invalid_argument: epoch_id is required for mst computation")
}

func Test_BranchEpochChecksTimestamp(t *testing.T) {
	ctx := context.Background()
	svc := &adminService{}

	future := time.Now().Add(100 * time.Hour)
	req := &v1.BranchEpochRequest{
		SourceEpoch:  0, // should fail after ts checks
		SourceCorpus: "blue",
		Corpus:       "green",
		Reason:       "testing",
		BranchTs:     future.UnixMilli(),
		NumShards:    1,
	}
	_, err := svc.BranchEpoch(ctx, req)
	require.EqualError(t, err, "twirp error invalid_argument: branch_ts should not be in the future")

	past := time.Now().Add(-10000 * time.Hour)
	req.BranchTs = past.UnixMilli()
	_, err = svc.BranchEpoch(ctx, req)
	require.EqualError(t, err, "twirp error invalid_argument: branch_ts is too far in the past")

	ok := time.Now().Add(-1 * time.Hour)
	req.BranchTs = ok.UnixMilli()
	_, err = svc.BranchEpoch(ctx, req)
	require.EqualError(t, err, "twirp error invalid_argument: source_epoch is required")
}

func Test_IndexRepoPublishesMessageWithRepoNWO(t *testing.T) {
	ctx := context.Background()
	searchClusters := helpers.SearchClusters(t)
	repoID := types.RepoID(1)
	store := &dbfakes.FakeStore{}
	producer := &mocks.FakeSyncProducer{}
	githubClient := &githubfakes.FakeInternalAPIClient{}
	githubClient.GetRepositoryByNWOReturns(&github.Repository{ID: repoID}, nil)

	repoPublisher := repo.NewPublisher(producer, 1)
	svc := NewService(
		searchClusters,
		nil, /* cacheClusters */
		nil, /* indexerClusters */
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		githubClient,
		&chat.NoopClient{},
		mockClusterAdminProvider(),
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		nil,
		repoPublisher,
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil, /* sitesapi */
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	res, err := svc.IndexRepo(ctx, &v1.IndexRepoRequest{RepoNwo: "github/blackbird"})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.Equal(t, 1, producer.SendMessageCallCount())
	m := producer.SendMessageArgsForCall(0)
	event := publish.DeserializeMessage(t, m)
	require.EqualValues(t, repoID, event.Repository.Id)
	require.Equal(t, search_pb.RepositoryChanged_ADMIN_PUSHED, event.Change)
}

func Test_IndexRepoPublishesMessageWithRepoID(t *testing.T) {
	ctx := context.Background()
	searchClusters := helpers.SearchClusters(t)
	repoID := types.RepoID(1)
	store := &dbfakes.FakeStore{}
	producer := &mocks.FakeSyncProducer{}

	repoPublisher := repo.NewPublisher(producer, 1)
	svc := NewService(
		searchClusters,
		nil, /* cacheClusters */
		nil, /* indexerClusters */
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		nil, /* githubClient */
		&chat.NoopClient{},
		mockClusterAdminProvider(),
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		nil,
		repoPublisher,
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil, /* sitesapi */
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	res, err := svc.IndexRepo(ctx, &v1.IndexRepoRequest{RepoId: uint32(repoID)})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.Equal(t, 1, producer.SendMessageCallCount())
	m := producer.SendMessageArgsForCall(0)
	event := publish.DeserializeMessage(t, m)
	require.EqualValues(t, repoID, event.Repository.Id)
	require.Equal(t, search_pb.RepositoryChanged_ADMIN_PUSHED, event.Change)
}

func Test_IndexRepoPublishesMessageForceReindex(t *testing.T) {
	ctx := context.Background()
	searchClusters := helpers.SearchClusters(t)
	store := &dbfakes.FakeStore{}
	producer := &mocks.FakeSyncProducer{}
	githubClient := &githubfakes.FakeInternalAPIClient{}
	githubClient.GetRepositoryByNWOReturns(&github.Repository{ID: 1}, nil)

	repoPublisher := repo.NewPublisher(producer, 1)
	svc := NewService(
		searchClusters,
		nil, /* cacheClusters */
		nil, /* indexerClusters */
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		githubClient,
		&chat.NoopClient{},
		mockClusterAdminProvider(),
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		nil,
		repoPublisher,
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil, /* sitesapi */
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	res, err := svc.IndexRepo(ctx, &v1.IndexRepoRequest{RepoNwo: "github/blackbird", ForceReindex: true})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.Equal(t, 1, producer.SendMessageCallCount())
	m := producer.SendMessageArgsForCall(0)
	event := publish.DeserializeMessage(t, m)
	require.Equal(t, event.Change, search_pb.RepositoryChanged_ADMIN_REPAIR)
}

func Test_CompactCorpus(t *testing.T) {
	const (
		offset  = int64(123)
		epochID = types.EpochID(100)
	)
	corpus := helpers.Corpus(t)
	ctx := context.Background()
	snapshotProducer := &mocks.FakeSyncProducer{}
	snapshotProducer.SendMessageReturns(0, offset, nil)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(
		&db.CorpusState{
			Corpus:  corpus,
			EpochID: epochID,
		},
		nil,
	)

	svc := &adminService{store: store, snapshotProducer: snapshotProducer}
	resp, err := svc.CompactCorpus(ctx, &v1.CompactCorpusRequest{
		Corpus:         corpus.String(),
		CompactionType: v1.CompactionType_COMPACTION_TYPE_INCREMENTAL,
		IncrementalOptions: &v1.IncrementalCompactionOptions{
			Radix:              10,
			MinSubtreeByteSize: 10_000_000,
		},
	})
	require.NoError(t, err)
	require.Equal(t, uint32(epochID), resp.EpochId)
	require.Equal(t, uint64(offset), resp.ServingOffset)
	require.Equal(t, 1, snapshotProducer.SendMessageCallCount())
}

func Test_PinCorpus(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus, IngestMode: db.IngestModeBackfill}, nil)
	store.SetCorpusIngestModeReturns(true, nil)

	svc := &adminService{searchClusters: searchClusters, store: store, snapshotProducer: &mocks.FakeSyncProducer{}}
	_, err := svc.PinCorpus(ctx, &v1.PinCorpusRequest{
		Corpus:    corpus.String(),
		ServingTs: time.Now().UnixMilli(),
	})
	require.NoError(t, err)

	c := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	require.NotNil(t, c)
	require.Equal(t, 1, c.SetPinCallCount())
	require.Equal(t, 1, c.SetIndexingPausedCallCount())
	require.True(t, c.SetIndexingPausedArgsForCall(0))
}

func Test_PinCorpusServingTsRequired(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus, IngestMode: db.IngestModeBackfill}, nil)
	store.SetCorpusIngestModeReturns(true, nil)

	svc := &adminService{searchClusters: searchClusters, store: store, snapshotProducer: &mocks.FakeSyncProducer{}}
	_, err := svc.PinCorpus(ctx, &v1.PinCorpusRequest{
		Corpus: corpus.String(),
	})
	require.EqualError(t, err, "twirp error invalid_argument: serving_ts is required")

	c := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	require.NotNil(t, c)
	require.Equal(t, 0, c.SetPinCallCount())
}

func Test_UnpinCorpus(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus, IngestMode: db.IngestModeIncremental}, nil)
	store.SetCorpusIngestModeReturns(true, nil)

	svc := &adminService{searchClusters: searchClusters, store: store, snapshotProducer: &mocks.FakeSyncProducer{}}
	_, err := svc.UnpinCorpus(ctx, &v1.UnpinCorpusRequest{Corpus: corpus.String()})
	require.NoError(t, err)

	c := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	require.NotNil(t, c)
	require.Equal(t, 1, c.UnsetPinCallCount())
	require.Equal(t, 1, c.SetIndexingPausedCallCount())
	require.False(t, c.SetIndexingPausedArgsForCall(0))
}

func Test_SetCorpusQueryState(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	store := &dbfakes.FakeStore{}

	svc := &adminService{searchClusters: searchClusters, store: store, snapshotProducer: &mocks.FakeSyncProducer{}}
	_, err := svc.SetCorpusQueryState(ctx, &v1.SetCorpusQueryStateRequest{Corpus: corpus.String(), Serving: true})
	require.NoError(t, err)

	c := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	require.NotNil(t, c)
	require.Equal(t, 1, c.SetServingCallCount())

	// Now try to turn off the only serving cluster
	_, err = svc.SetCorpusQueryState(ctx, &v1.SetCorpusQueryStateRequest{Corpus: corpus.String(), Serving: false})
	require.EqualError(t, err, fmt.Sprintf("twirp error invalid_argument: serving cannot disable serving in %s because it is the only serving cluster", corpus.NameWithCluster()))
	require.Equal(t, 1, c.SetServingCallCount()) // NB: Still only 1 call.
}

func Test_SetCacheCluster(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus, IngestMode: db.IngestModeIncremental}, nil)
	store.SetCorpusIngestModeReturns(true, nil)

	svc := &adminService{searchClusters: searchClusters, store: store, snapshotProducer: &mocks.FakeSyncProducer{}}
	_, err := svc.SetCorpusCacheCluster(ctx, &v1.SetCorpusCacheClusterRequest{Corpus: corpus.String(), CacheCluster: "cache-001"})
	require.NoError(t, err)

	c := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	require.NotNil(t, c)
	require.Equal(t, 1, c.SetCacheClusterCallCount())
}

func Test_GetDeployAheadBehind(t *testing.T) {
	ctx := context.Background()

	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus, IngestMode: db.IngestModeIncremental}, nil)
	store.SetCorpusIngestModeReturns(true, nil)

	r, err := recorder.New("../github/client/fixtures/get-pulls-for-commit")
	r.SetReplayableInteractions(true) // we send the same sha twice to get two requests
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}
	githubClient := client.NewInternalAPIClient(httpClient, "http://api.github.localhost", "octocat", "octocat")

	gitClient := &gitaccessfakes.FakeClient{}
	gitClient.GetDefaultRefReturns(&gitaccess.RefTip{RefName: "main", CommitOID: gitaccess.NullObjectID}, nil)

	svc := &adminService{searchClusters: searchClusters, store: store, snapshotProducer: &mocks.FakeSyncProducer{}, githubClient: githubClient, gitClient: gitClient}
	resp, err := svc.GetDeployAheadBehind(ctx, &v1.GetDeployAheadBehindRequest{CommitShas: []string{"13240fd24fb480312e66adac4b8375c1a0727edb", "13240fd24fb480312e66adac4b8375c1a0727edb"}})
	require.NoError(t, err)
	require.NotNil(t, resp)
}

func Test_GetRepoStatusReturnsSnapshotsFromAllBackends(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)

	repos := helpers.Repositories(t, 1)
	repo := repos[0]
	store := noop.New(repos...)
	githubClient := &githubfakes.FakeInternalAPIClient{}
	githubClient.GetRepositoryReturns(nil, errors.New("failed to get repo"))

	// Setup snapshots from the indexer
	const indexingSnapshotOffset = int64(123)
	indexerClusters := helpers.IndexerClusters(t)
	indexerCluster := indexerClusters.GetCluster(corpus)
	host, err := indexerCluster.GetHost()
	require.NoError(t, err)

	indexerClient := helpers.FakeIndexAPI(t, host)
	indexerClient.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
		Snapshots: []*snapshotpb.Snapshot{
			{
				Entries: []*snapshotpb.SnapshotEntry{
					{
						EntryId:        123,
						RepoId:         uint32(repo.RepoID),
						OwnerId:        repo.OwnerID,
						NetworkId:      uint32(repo.NetworkID.Int32),
						Nwo:            repo.NWO(),
						IsRepoPublic:   repo.IsPublic,
						IsRepoArchived: repo.IsArchived,
						RepoScore:      repo.RepoScore(),
						RefName:        "refs/heads/main",
						CommitSha:      repo.CommitOID,
						Experiments:    repo.Experiments,
						Versions: []*snapshotpb.SnapshotEntryVersion{
							{
								OffsetId: indexingSnapshotOffset,
								State:    snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE,
							},
						},
					},
				},
			},
		},
		ServingStatus: &servingpb.ServingStatus{
			Shards: []*servingpb.Shard{
				{
					Id:            host.ShardID,
					ServingOffset: indexingSnapshotOffset,
					ServingTs:     time.Now().UnixMilli(),
				},
			},
		},
	}, nil)

	// Setup snapshots from the search cluster
	const servingSnapshotOffset = int64(101)
	searchClusters := helpers.SearchClustersN(t, 1)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	searchClient := helpers.FakeShardClient(t, routes.ServingHosts[0][0])
	searchClient.SearchSnapshotsReturns(
		&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{
				{
					Entries: []*snapshotpb.SnapshotEntry{
						{
							EntryId:        100,
							RepoId:         uint32(repo.RepoID),
							OwnerId:        repo.OwnerID,
							NetworkId:      uint32(repo.NetworkID.Int32),
							Nwo:            repo.NWO(),
							IsRepoPublic:   repo.IsPublic,
							IsRepoArchived: repo.IsArchived,
							RepoScore:      repo.RepoScore(),
							RefName:        "refs/heads/main",
							CommitSha:      helpers.UniqueOID(t).Bytes(),
							Experiments:    repo.Experiments,
							Versions: []*snapshotpb.SnapshotEntryVersion{
								{
									OffsetId: servingSnapshotOffset,
									State:    snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE,
								},
							},
						},
					},
				},
			},
			ServingStatus: &servingpb.ServingStatus{
				Shards: []*servingpb.Shard{
					{
						Id:            host.ShardID,
						ServingOffset: servingSnapshotOffset,
						ServingTs:     time.Now().Add(-10 * time.Minute).UnixMilli(),
					},
				},
			},
		},
		nil,
	)

	svc := &adminService{
		store:            store,
		indexerClusters:  indexerClusters,
		searchClusters:   searchClusters,
		githubClient:     githubClient,
		snapshotProducer: &mocks.FakeSyncProducer{},
	}
	r, err := svc.GetRepoStatus(ctx, &v1.GetRepoStatusRequest{RepoNwo: repo.NWO(), Corpus: corpus.String()})
	require.NoError(t, err)
	require.Len(t, r.IndexerIngests, 1, "response is not the right size: %+v", r)
	require.Len(t, r.IndexerIngests[0].SnapshotEntries, 1)
	require.Equal(t, indexingSnapshotOffset, r.IndexerIngests[0].SnapshotEntries[0].ServingOffset)
	require.Len(t, r.ServingIngests, 1, "response is not the right size: %+v", r)
	require.Len(t, r.ServingIngests[0].SnapshotEntries, 1)
	require.Equal(t, servingSnapshotOffset, r.ServingIngests[0].SnapshotEntries[0].ServingOffset)
}

func Test_ShardAssignments(t *testing.T) {
	ctx := context.Background()
	assignmentConsumer := &kafkafakes.FakeAssignmentsReader{}
	assignmentConsumer.ReadAtOffsetReturns(newHostAssignmentSnapshot(), nil)
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2, EpochID: 1}, nil
	}
	svc := &adminService{searchClusters: helpers.SearchClusters(t), assignmentsReader: assignmentConsumer, store: store}

	resp, err := svc.ShardAssignments(ctx, &v1.ShardAssignmentsRequest{Corpus: "yellow"})

	require.NoError(t, err)
	require.Equal(t, uint32(1), resp.AlgorithmVersion)
	require.Equal(t, 2, len(resp.HostAssignments))
	for _, hostAssignment := range resp.HostAssignments {
		require.Equal(t, 2, len(hostAssignment.AssignedShards))
	}
}

func Test_GetQuotas(t *testing.T) {
	ctx := context.Background()
	svc := &adminService{
		searchClusters:     helpers.SearchClusters(t),
		quotaRateEstimator: quota.NewMemoryRateEstimator(),
		githubClient:       &githubfakes.FakeInternalAPIClient{},
	}

	_, err := svc.GetRateLimitQuota(ctx, &v1.GetRateLimitQuotaRequest{Login: "foo"})
	require.NoError(t, err)

	_, err = svc.GetRateLimitQuota(ctx, &v1.GetRateLimitQuotaRequest{Login: "foo[bot]"})
	require.NoError(t, err)
}

func Test_ResetQuotas(t *testing.T) {
	ctx := context.Background()
	svc := &adminService{
		searchClusters:     helpers.SearchClusters(t),
		quotaRateEstimator: quota.NewMemoryRateEstimator(),
		githubClient:       &githubfakes.FakeInternalAPIClient{},
	}

	// Resetting works when the user is not present.
	_, err := svc.ResetRateLimitQuota(ctx, &v1.ResetRateLimitQuotaRequest{Login: "foo"})
	require.NoError(t, err)

	// Resetting works when the user is present.
	_, err = svc.GetRateLimitQuota(ctx, &v1.GetRateLimitQuotaRequest{Login: "foo"})
	require.NoError(t, err)
	_, err = svc.ResetRateLimitQuota(ctx, &v1.ResetRateLimitQuotaRequest{Login: "foo"})
	require.NoError(t, err)
}

func Test_ShardAssignmentsInvalidCluster(t *testing.T) {
	ctx := context.Background()
	svc := &adminService{searchClusters: helpers.SearchClusters(t), assignmentsReader: &kafkafakes.FakeAssignmentsReader{}}
	resp, err := svc.ShardAssignments(ctx, &v1.ShardAssignmentsRequest{Corpus: "blah"})
	require.Error(t, err)
	require.Nil(t, resp)
}

func Test_ProbeRepoWithSnapshotSearch(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	client := helpers.FakeShardClient(t, routes.ServingHosts[0][0])
	client.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
		Snapshots: []*snapshotpb.Snapshot{
			{
				SnapshotId:         []byte{},
				GeometricXorFilter: []byte{},
				Entries: []*snapshotpb.SnapshotEntry{
					{
						EntryId:        1,
						RepoId:         uint32(repo.RepoID),
						OwnerId:        repo.OwnerID,
						NetworkId:      uint32(repo.NetworkID.Int32),
						Nwo:            repo.NWO(),
						IsRepoPublic:   repo.IsPublic,
						IsRepoArchived: repo.IsArchived,
						RepoScore:      repo.RepoScore(),
						RefName:        "refs/heads/main",
						CommitSha:      repo.CommitOID,
						Experiments:    repo.Experiments,
					},
				},
			},
		},
		ServingStatus: &servingpb.ServingStatus{
			EpochId: 1,
			Shards: []*servingpb.Shard{
				{
					Id:            0,
					ServingOffset: 123,
					ServingTs:     time.Now().UTC().UnixMilli(),
				},
			},
			SequenceNumber: 123,
		},
	}, nil)
	gitClient := &gitaccessfakes.FakeClient{}
	gitClient.DiffReturns(gitaccess.RepoDiff{}, nil)

	svc := &adminService{
		searchClusters: searchClusters,
		store:          store,
		gitClient:      gitClient,
		prober:         healthcheck.NewProber(store, nil, gitClient, routing.Dotcom, searchClusters, nil, nil, nil, nil, nil, helpers.MockDelayedTimestampReader(t)),
	}

	res, err := svc.ProbeRepo(ctx, &v1.ProbeRepoRequest{Corpus: corpus.String(), RepoNwo: repo.NWO()})
	require.NoError(t, err)
	require.NotNil(t, res)
}

func Test_waitForEpochWithBackOff(t *testing.T) {
	ctx := context.Background()
	const epochID = 123

	client := &mocks.FakeBlackbirdClient{}
	hosts := make([][]*blackbird.IndexHost, 1)
	hosts[0] = []*blackbird.IndexHost{{Hostname: "test-server-1"}}
	client.RoutesStub = func() blackbird.Routes {
		switch client.RoutesCallCount() {
		case 1:
			// unknown epoch: requires a retry
			return blackbird.Routes{Epoch: 0, ServingOffset: 1, Hosts: hosts}
		case 2:
			// wrong epoch ID: requires a retry
			return blackbird.Routes{Epoch: epochID - 1, ServingOffset: 1, Hosts: hosts}
		default:
			return blackbird.Routes{Epoch: epochID, ServingOffset: 1, Hosts: hosts}
		}
	}
	clients := map[string]blackbird.Client{
		"test-cache-123": client,
	}

	cacheClusters := routing.NewCacheClusters(clients)

	// really short backoff for this test. The real code waits much longer.
	// The retry limit protects against bugs.
	_, err := cacheClusters.WaitForEpoch(ctx, "test-cache-123", epochID, 2*time.Second)
	require.NoError(t, err)
	require.Equal(t, 3, client.RoutesCallCount())
}

func mockClusterAdminProvider() func() sarama.ClusterAdmin {
	return func() sarama.ClusterAdmin { return &mocks.FakeClusterAdmin{} }
}

func newHostAssignmentSnapshot() *kafka.AssignmentSnapshot {
	hosts := []*hydro_entities.HostAssignment{
		{
			HostName: "host-1",
			Shards: []*hydro_entities.HostAssignment_AssignedShard{
				{ShardId: 1, Operation: hydro_entities.HostAssignment_COMPACTING, ShardGeneration: 2},
				{ShardId: 2, Operation: hydro_entities.HostAssignment_SERVING, ShardGeneration: 1},
			},
			Heartbeat: time.Now().Unix() - 500,
		},
		{
			HostName: "host-2",
			Shards: []*hydro_entities.HostAssignment_AssignedShard{
				{ShardId: 1, Operation: hydro_entities.HostAssignment_DOWNLOADING, ShardGeneration: 1},
				{ShardId: 2, Operation: hydro_entities.HostAssignment_SERVING, ShardGeneration: 1},
			},
			Heartbeat: time.Now().Unix() - 450,
		},
	}

	shards := []*hydro_entities.ShardStatus{
		{Generation: 1},
		{Generation: 2},
	}

	return &kafka.AssignmentSnapshot{
		Msg: &hydro_bb.AssignmentSnapshot{
			Version:            &hydro_entities.AssignmentVersion{IndexVersion: 42, AlgoVersion: 1, EpochId: 100},
			Hosts:              hosts,
			Shards:             shards,
			LastKafkaTimestamp: time.Now().Unix(),
		},
		KafkaOffset: 1,
	}
}
