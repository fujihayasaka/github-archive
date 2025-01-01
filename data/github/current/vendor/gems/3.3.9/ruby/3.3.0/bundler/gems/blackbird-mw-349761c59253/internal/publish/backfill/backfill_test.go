package backfill

import (
	"context"
	"testing"

	"github.com/IBM/sarama"

	"github.com/stretchr/testify/require"
	protojson "google.golang.org/protobuf/encoding/protojson"

	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

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
	publisher := NewPublisher(
		store,
		&mocks.FakeSyncProducer{},
		nil, /* searchClusters */
		nil, /* cacheClusters */
		&chat.NoopClient{},
		1,
		1,
	)

	epoch, err := store.CreateEpoch(ctx, corpus, "test")
	require.NoError(t, err)
	result, err := publisher.Publish(ctx, &pb.BackfillCorpusRequest{Bootstrap: true}, epoch)
	require.NoError(t, err)
	require.Equal(t, 0, int(result.NumReposPublished))
	require.Equal(t, db.EpochOffsets{}, result.MaxPublishedOffsets)
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
	repos := helpers.RepositoriesWithID(t, numRepos)
	store := noop.New()
	searchClusters, cacheClusters, cacheClient := helpers.MakeBackfillableCluster(t, repos, corpus, sourceEpoch)
	snapshotProducer := &mocks.FakeSyncProducer{}

	const (
		partition0 = int32(0)
		partition1 = int32(1)
	)

	ctx := context.Background()
	publisher := NewPublisher(
		store,
		snapshotProducer,
		searchClusters,
		cacheClusters,
		&chat.NoopClient{},
		1,
		1,
	)
	result, err := publisher.Publish(ctx, &pb.BackfillCorpusRequest{Corpus: corpus.String(), EpochId: uint32(sourceEpoch)}, epoch)
	require.NoError(t, err)
	require.Equal(t, 0, int(result.NumReposPublished), "currently number of published repos is not reported")
	require.Equal(t, db.EpochOffsets{partition0: 2, partition1: 3}, result.MaxPublishedOffsets)
	require.Equal(t, 1, cacheClient.MstCallCount(), "shard MST RPC not called")
	require.Equal(t, 2, snapshotProducer.SendMessageCallCount(), "expect two snapshots to be sent: create epoch and source offsets")

	snapshotMsg := snapshotProducer.SendMessageArgsForCall(1)
	require.Equal(t, (&routing.SnapshotTopic{Corpus: corpus, EpochID: epochID}).Name(), snapshotMsg.Topic, "epoch from database should be used for topic name")
	snapshot := helpers.DecodeSnapshot(t, snapshotMsg)
	require.Equal(t, uint32(epochID), snapshot.EpochId, "epoch ID should be the one from the database, not the request")
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
	searchClusters, cacheClusters, cacheClient := helpers.MakeBackfillableCluster(t, shardRepos, corpus, sourceEpoch)

	const (
		partition0 = int32(0)
		partition1 = int32(1)
	)

	ctx := context.Background()
	publisher := NewPublisher(
		store,
		&mocks.FakeSyncProducer{},
		searchClusters,
		cacheClusters,
		&chat.NoopClient{},
		1,
		1,
	)
	result, err := publisher.Publish(ctx, &pb.BackfillCorpusRequest{Corpus: corpus.String(), Limit: limit, EpochId: uint32(sourceEpoch)}, epoch)
	require.NoError(t, err)
	require.Equal(t, 0, int(result.NumReposPublished), "currently the number of published repositories is not returned")
	require.Equal(t, db.EpochOffsets{partition0: 2, partition1: 2}, result.MaxPublishedOffsets)
	require.Equal(t, 1, cacheClient.MstCallCount(), "shard MST RPC not called")
}

// It is the responsibility of the admin service to set the cache cluster if
// there isn't one. This verifies the backfill publishing fails properly (and
// doesn't hang forever) if the state is incorrect.
func Test_MSTBackfillWithNoCacheClusterFails(t *testing.T) {
	corpus := helpers.Corpus(t)
	epoch := &db.Epoch{EpochID: 2, Corpus: corpus}
	sourceEpoch := types.EpochID(1)
	repos := helpers.RepositoriesWithID(t, 1)
	store := noop.New(repos...)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	client.CacheClusterReturns("")

	ctx := context.Background()
	publisher := NewPublisher(
		store,
		&mocks.FakeSyncProducer{},
		searchClusters,
		nil, /* cacheClusters */
		&chat.NoopClient{},
		1,
		1,
	)
	_, err := publisher.Publish(ctx, &pb.BackfillCorpusRequest{Corpus: corpus.String(), EpochId: uint32(sourceEpoch)}, epoch)
	require.Error(t, err)
	require.ErrorContains(t, err, "no cache cluster configured")
}

func Test_JsonEnum(t *testing.T) {
	r := new(pb.BeginBackfillCorpusRequest)
	unmarshaler := protojson.UnmarshalOptions{DiscardUnknown: true}
	err := unmarshaler.Unmarshal([]byte(`{"corpus":"yellow", "epoch_id":"305", "epoch_mode":"EMBEDDINGS"}`), r)
	require.NoError(t, err)
	require.Equal(t, r.GetEpochMode(), entities.EpochMode_EMBEDDINGS)
	require.Equal(t, r.GetCorpus(), "yellow")
	require.Equal(t, r.GetEpochId(), uint32(305))
}
