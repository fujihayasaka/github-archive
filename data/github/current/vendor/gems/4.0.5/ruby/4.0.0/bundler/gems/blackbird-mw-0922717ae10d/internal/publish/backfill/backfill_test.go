package backfill

import (
	"context"
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/blackbird/crates/client/pkg/blackbird"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"
	protojson "google.golang.org/protobuf/encoding/protojson"

	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/noop"
	pb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_BootstrapBackfill(t *testing.T) {
	corpus := helpers.Corpus(t)
	store := noop.New()
	input := make(chan *sarama.ProducerMessage)
	successes := make(chan *sarama.ProducerMessage)
	errs := make(chan *sarama.ProducerError)
	producer := &mocks.FakeAsyncProducer{}
	producer.InputReturns(input)
	producer.SuccessesReturns(successes)
	producer.ErrorsReturns(errs)

	const (
		partition0 = int32(0)
		partition1 = int32(1)
	)

	messages := []*sarama.ProducerMessage{}
	offsets := map[int32]int64{partition0: 0, partition1: 0}
	go func() {
		for msg := range input {
			messages = append(messages, msg)
			offsets[msg.Partition]++
			msg.Offset = offsets[msg.Partition]
			successes <- msg
		}
	}()

	ctx := context.Background()
	_, cacheClusters, cacheClient := helpers.MakeBackfillableCluster(t, nil, corpus, types.EpochID(1))
	kafkaClusterResolver := routing.ClusterResolver{}
	defaultSnapshotProducer := mocks.FakeSyncProducer{}
	snapshotProducers := map[routing.Region]sarama.SyncProducer{
		routing.DefaultRegion: &defaultSnapshotProducer,
	}
	publisher := NewPublisher(
		store,
		kafkaClusterResolver,
		snapshotProducers,
		cacheClusters,
		&chat.NoopClient{},
		routing.TopicConfig{
			Backfill:    routing.BackfillTopicConfig{Partitions: 2},
			Onboard:     routing.OnboardTopicConfig{Partitions: 1},
			Incremental: routing.IncrementalTopicConfig{Partitions: 1},
		},
	)

	epoch, err := store.CreateEpoch(ctx, corpus, "test")
	require.NoError(t, err)
	err = publisher.Publish(ctx, &pb.BackfillCorpusRequest{Bootstrap: true, NumShards: 1, Corpus: corpus.String(), MstCacheCluster: routing.CacheClusterNames[0]}, epoch)

	require.NoError(t, err)
	require.Equal(t, 1, cacheClient.BackfillCallCount(), "shard Backfill RPC not called")
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)
	require.Equal(t, db.IngestModeUnknown, state.IngestMode, "publisher should not change database ingest mode")

	// We should send one message to change the epoch
	require.Equal(t, 1, defaultSnapshotProducer.SendMessageCallCount())
}

func Test_MSTBackfill(t *testing.T) {
	const (
		numRepos   = 5
		partitions = uint32(2)
		epochID    = 2
	)

	corpus := helpers.Corpus(t)
	epoch := &db.Epoch{EpochID: epochID, Corpus: corpus}
	sourceEpoch := types.EpochID(1)
	cacheCluster := routing.CacheClusterNames[0]
	repos := helpers.RepositoriesWithID(t, numRepos)
	store := noop.New()
	_, cacheClusters, cacheClient := helpers.MakeBackfillableCluster(t, repos, corpus, sourceEpoch)
	kafkaClusterResolver := routing.ClusterResolver{}
	defaultSnapshotProducer := mocks.FakeSyncProducer{}
	snapshotProducers := map[routing.Region]sarama.SyncProducer{
		routing.DefaultRegion: &defaultSnapshotProducer,
	}

	ctx := context.Background()
	publisher := NewPublisher(
		store,
		kafkaClusterResolver,
		snapshotProducers,
		cacheClusters,
		&chat.NoopClient{},
		routing.TopicConfig{},
	)
	err := publisher.Publish(ctx, &pb.BackfillCorpusRequest{Corpus: corpus.String(), MstCacheCluster: cacheCluster, NumShards: 1}, epoch)
	require.NoError(t, err)
	require.Equal(t, 1, cacheClient.BackfillCallCount(), "shard Backfill RPC not called")
	require.Equal(t, 1, defaultSnapshotProducer.SendMessageCallCount(), "expect one snapshots to be sent: create epoch")

	snapshotMsg := defaultSnapshotProducer.SendMessageArgsForCall(0)
	require.Equal(t, corpus.ShardAssignmentTopic(), snapshotMsg.Topic)
}

func Test_MSTBackfillWithLimit(t *testing.T) {
	// All the repos are in the database, but only half are returned from
	// the shard RPC. Only the repos in the MST should be published UP TO THE LIMIT
	const (
		numRepos   = 10
		limit      = 4
		partitions = 2
	)

	corpus := helpers.Corpus(t)
	epoch := &db.Epoch{EpochID: 2, Corpus: corpus}
	sourceEpoch := types.EpochID(1)
	repos := helpers.RepositoriesWithID(t, numRepos)
	shardRepos := repos[0:limit] // NOTE: simulating MST returning up to `limit` repos
	store := noop.New(repos...)
	_, cacheClusters, cacheClient := helpers.MakeBackfillableCluster(t, shardRepos, corpus, sourceEpoch)
	cacheCluster := routing.CacheClusterNames[0]
	kafkaClusterResolver := routing.ClusterResolver{}
	defaultSnapshotProducer := mocks.FakeSyncProducer{}
	snapshotProducers := map[routing.Region]sarama.SyncProducer{
		routing.DefaultRegion: &defaultSnapshotProducer,
	}

	ctx := context.Background()
	publisher := NewPublisher(
		store,
		kafkaClusterResolver,
		snapshotProducers,
		cacheClusters,
		&chat.NoopClient{},
		routing.TopicConfig{},
	)
	err := publisher.Publish(ctx, &pb.BackfillCorpusRequest{Corpus: corpus.String(), Limit: limit, MstCacheCluster: cacheCluster, NumShards: 1}, epoch)
	require.NoError(t, err)
	require.Equal(t, 1, cacheClient.BackfillCallCount(), "shard Backfill RPC not called")
}

// It is the responsibility of the admin service to set the cache cluster if
// there isn't one. This verifies the backfill publishing fails properly (and
// doesn't hang forever) if the state is incorrect.
func Test_MSTBackfillWithNoCacheClusterFails(t *testing.T) {
	corpus := helpers.Corpus(t)
	destEpoch := &db.Epoch{EpochID: 2, Corpus: corpus}
	repos := helpers.RepositoriesWithID(t, 1)
	store := noop.New(repos...)

	sourceEpochID := types.EpochID(1)
	epochMode := epoch.EpochModeHybridGraph
	mockCacheClient := &mocks.FakeCacheAPI{}
	clients := map[string]blackbird.Client{}
	cacheHosts := make([][]*blackbird.IndexHost, 1)
	cacheHosts[0] = []*blackbird.IndexHost{{Hostname: "cache-001", CacheClient: mockCacheClient}}
	cacheClient := &mocks.FakeBlackbirdClient{}
	cacheClient.EpochInfoReturns(blackbird.EpochInfo{EpochID: uint32(sourceEpochID), EpochMode: blackbird.EpochMode(epochMode), NumShards: 1})
	cacheClient.RoutesReturns(blackbird.Routes{Hosts: cacheHosts, ServingOffset: 10, ServingTs: time.Now().UTC().UnixMilli(), Epoch: uint32(sourceEpochID), EpochMode: blackbird.EpochMode(epochMode)})
	clients[routing.CacheClusterNames[0]] = cacheClient
	kafkaClusterResolver := routing.ClusterResolver{}
	defaultSnapshotProducer := mocks.FakeSyncProducer{}
	snapshotProducers := map[routing.Region]sarama.SyncProducer{
		routing.DefaultRegion: &defaultSnapshotProducer,
	}

	ctx := context.Background()
	publisher := NewPublisher(
		store,
		kafkaClusterResolver,
		snapshotProducers,
		routing.NewCacheClusters(clients),
		&chat.NoopClient{},
		routing.TopicConfig{},
	)
	err := publisher.Publish(ctx, &pb.BackfillCorpusRequest{Corpus: corpus.String(), NumShards: 1}, destEpoch)
	require.Error(t, err)
	require.ErrorContains(t, err, "couldn't find client for cache cluster")
}

func Test_JsonEnum(t *testing.T) {
	r := new(pb.BeginBackfillCorpusRequest)
	unmarshaler := protojson.UnmarshalOptions{DiscardUnknown: true}
	err := unmarshaler.Unmarshal([]byte(`{"corpus":"yellow", "mst_cache_cluster":"cache-001", "epoch_mode":"EMBEDDINGS_GRAPH"}`), r)
	require.NoError(t, err)
	require.Equal(t, r.GetEpochMode(), entities.EpochMode_EMBEDDINGS_GRAPH)
	require.Equal(t, r.GetCorpus(), "yellow")
	require.Equal(t, r.GetMstCacheCluster(), "cache-001")
}
