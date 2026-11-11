package deltaingest

import (
	"context"
	"testing"

	"github.com/IBM/sarama"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_DetectEndOfBackfill(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	for _, offset := range []int64{1, 10, 100} {
		store := mockStore(t, db.IngestModeBackfill, db.EpochOffsets{
			0: 1, // NB: Looking for last offset = 1
		})
		blackbirdKafkaAdmin := helpers.FakeAdminClient(t, corpus, types.EpochID(1), offset)
		sharedKafkaAdmin := helpers.FakeAdminClient(t, corpus, types.EpochID(1), offset)

		d := NewIngestModeDetector(store, sharedKafkaAdmin, blackbirdKafkaAdmin, nil, 1, routing.Dotcom)

		err := d.check(ctx)
		require.NoError(t, err)
		require.Equal(t, 1, store.SetCorpusIngestModeCallCount())

		_, c, _, mode := store.SetCorpusIngestModeArgsForCall(0)
		require.Equal(t, corpus, c)
		require.Equal(t, db.IngestModeBackfillCatchup, mode)
	}
}

func Test_DetectNotYetEndOfBackfill(t *testing.T) {
	corpus := helpers.Corpus(t)
	store := mockStore(t, db.IngestModeBackfill, db.EpochOffsets{
		0: 2, // NB: Looking for last offset = 2
	})

	sharedKafkaAdmin := helpers.FakeAdminClient(t, corpus, types.EpochID(1), 0)
	blackbirdKafkaAdmin := helpers.FakeAdminClient(t, corpus, types.EpochID(1), 1) // NB: But Kafka says we've only consumed to offset = 1
	d := NewIngestModeDetector(store, sharedKafkaAdmin, blackbirdKafkaAdmin, nil, 1, routing.Dotcom)

	err := d.check(context.Background())
	require.NoError(t, err)
	require.Equal(t, 0, store.SetCorpusIngestModeCallCount())
}

func Test_DetectLatestOffsetIsNotEndOfBackfill(t *testing.T) {
	corpus := helpers.Corpus(t)
	store := mockStore(t, db.IngestModeBackfill, db.EpochOffsets{
		0: 2, // NB: Looking for last offset = 2
	})

	backfillTopic := corpus.EpochBackfillTopic(types.EpochID(1))
	blackbirdAdminClient := helpers.FakeAdminClientWithOffsets(
		t,
		types.EpochID(1),
		map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			backfillTopic: {0: {Offset: -2}}, // NB: But Kafka says we're at the "latest" initial offset
		})

	d := NewIngestModeDetector(
		store,
		helpers.FakeAdminClient(t, corpus, types.EpochID(1), 0),
		blackbirdAdminClient,
		nil,
		1,
		routing.Dotcom,
	)
	err := d.check(context.Background())
	require.NoError(t, err)
	require.Equal(t, 0, store.SetCorpusIngestModeCallCount())
}

// NOTE: We don't currently use "earliest" but this test ensures it works correctly if we ever enable that.
func Test_DetectEarliestOffsetIsNotEndOfBackfill(t *testing.T) {
	store := mockStore(t, db.IngestModeBackfill, db.EpochOffsets{
		0: 2, // NB: Looking for last offset = 2
	})
	corpus := helpers.Corpus(t)

	backfillTopic := corpus.EpochBackfillTopic(types.EpochID(1))
	sharedKafkaAdmin := helpers.FakeAdminClientWithOffsets(
		t,
		types.EpochID(1),
		map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			backfillTopic: {0: {Offset: -2}}, // NB: But Kafka says we're at the "earliest" initial offset
		},
	)
	blackbirdKafkaAdmin := helpers.FakeAdminClientWithOffsets(
		t,
		types.EpochID(1),
		map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			backfillTopic: {0: {Offset: -2}}, // NB: But Kafka says we're at the "earliest" initial offset
		},
	)

	d := NewIngestModeDetector(store, sharedKafkaAdmin, blackbirdKafkaAdmin, nil, 1, routing.Dotcom)
	err := d.check(context.Background())
	require.NoError(t, err)
	require.Equal(t, 0, store.SetCorpusIngestModeCallCount())
}

func Test_DetectNoopStates(t *testing.T) {
	corpus := helpers.Corpus(t)
	for _, mode := range []db.IngestMode{
		db.IngestModeLegacy,
		db.IngestModeIncremental,
		db.IngestModeIncrementalTransition,
	} {
		store := &dbfakes.FakeStore{}
		store.GetCorpusStateReturns(&db.CorpusState{Corpus: corpus, EpochID: 1, IngestMode: mode}, nil)
		d := NewIngestModeDetector(store, helpers.FakeAdminClient(t, corpus, 1, 0), nil, nil, 1, routing.Dotcom)

		err := d.check(context.Background())
		require.NoError(t, err)
		require.Equal(t, 0, store.SetCorpusIngestModeCallCount())
	}
}

func Test_DetectTransitionToIncremental(t *testing.T) {
	const consumerGroupOffset = 10
	store := mockStore(t, db.IngestModeBackfillCatchup, db.EpochOffsets{})
	producer := &mocks.FakeSyncProducer{}
	blackbirdKafkaAdmin := helpers.FakeAdminClientWithOffsets(
		t,
		1,
		map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			routing.IncrementalSourceTopic: {0: {Offset: consumerGroupOffset - 1}},
			routing.OnboardSourceTopic:     {0: {Offset: consumerGroupOffset - 1}},
		},
	)
	d := NewIngestModeDetector(store, blackbirdKafkaAdmin, nil, producer, 1, routing.Dotcom)

	err := d.check(context.Background())
	require.NoError(t, err)
	// NB: All 6 corpora are going to transition due to how ListConsumerGroupOffsetsReturns is written
	// NOTE: The following two integers need to be incremented every time a new cluster is added.
	// The first integer should be twice the second. The second integer represents the total number of
	// clusters we currently have configured.
	require.Equal(t, 12, store.SetCorpusIngestModeCallCount())
	require.Equal(t, 6, producer.SendMessageCallCount())
}

func Test_DetectNoTransitionToIncrementalHighLagOnIncrementalTopic(t *testing.T) {
	const consumerGroupOffset = 1000 // last offset is 1000, so there's too much lag
	store := mockStore(t, db.IngestModeBackfillCatchup, db.EpochOffsets{})
	admin := &mocks.FakeClusterAdmin{}
	admin.ListConsumerGroupOffsetsReturns(&sarama.OffsetFetchResponse{
		Blocks: map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			routing.IncrementalSourceTopic: {0: {Offset: 10 + 1}},                  // cg is at offset = 10
			routing.OnboardSourceTopic:     {0: {Offset: consumerGroupOffset + 1}}, // no lag on this topic
		},
	}, nil)
	admin.ListConsumerGroupsStub = func() (map[string]string, error) {
		res := map[string]string{}
		for _, c := range routing.Corpora {
			res[c.ConsumerGroup(1)] = "blah"
		}
		return res, nil
	}

	client := &mocks.FakeSaramaClient{}
	client.PartitionsReturns([]int32{0}, nil)
	client.GetOffsetReturns(consumerGroupOffset, nil)
	producer := &mocks.FakeSyncProducer{}
	makeAdminClient := func() sarama.ClusterAdmin {
		return admin
	}

	blackbirdKafkaAdmin := kafka.NewAdminClient(makeAdminClient, client)
	d := NewIngestModeDetector(store, blackbirdKafkaAdmin, nil, producer, 1, routing.Dotcom)

	err := d.check(context.Background())

	require.NoError(t, err)
	require.Equal(t, 0, store.SetCorpusIngestModeCallCount())
}

func Test_DetectNoTransitionToIncrementalHighLagOnOnboardingTopic(t *testing.T) {
	const consumerGroupOffset = 1000 // last offset is 1000, so there's too much lag
	store := mockStore(t, db.IngestModeBackfillCatchup, db.EpochOffsets{})
	admin := &mocks.FakeClusterAdmin{}
	admin.ListConsumerGroupOffsetsReturns(&sarama.OffsetFetchResponse{
		Blocks: map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			routing.IncrementalSourceTopic: {0: {Offset: consumerGroupOffset + 1}}, // no lag on this topic
			routing.OnboardSourceTopic:     {0: {Offset: 10 + 1}},                  // cg is at offset = 10
		},
	}, nil)
	admin.ListConsumerGroupsStub = func() (map[string]string, error) {
		res := map[string]string{}
		for _, c := range routing.Corpora {
			res[c.ConsumerGroup(1)] = "blah"
		}
		return res, nil
	}

	client := &mocks.FakeSaramaClient{}
	client.PartitionsReturns([]int32{0}, nil)
	client.GetOffsetReturns(consumerGroupOffset, nil)
	producer := &mocks.FakeSyncProducer{}
	makeAdminClient := func() sarama.ClusterAdmin {
		return admin
	}

	blackbirdKafkaAdmin := kafka.NewAdminClient(makeAdminClient, client)
	d := NewIngestModeDetector(store, blackbirdKafkaAdmin, nil, producer, 1, routing.Dotcom)

	err := d.check(context.Background())

	require.NoError(t, err)
	require.Equal(t, 0, store.SetCorpusIngestModeCallCount())
}

func Test_PartitionMismatchPanic(t *testing.T) {
	const epochID = types.EpochID(42)
	corpus := helpers.Corpus(t)
	store := mockStore(t, db.IngestModeBackfill, db.EpochOffsets{0: 1, 1: 2}) // NOTE: Database has two offsets
	blackbirdKafkaAdmin := helpers.FakeAdminClient(t, corpus, epochID, 1)
	d := NewIngestModeDetector(store, nil, blackbirdKafkaAdmin, nil, 1, routing.Dotcom) // NOTE: Expecting 1 partition

	require.Panics(t, func() { _ = d.check(context.Background()) })
}

func Test_PartitionUnexpectedOffsetFromKafka(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	store := mockStore(t, db.IngestModeBackfill, db.EpochOffsets{0: 1})
	backfillTopic := corpus.EpochBackfillTopic(types.EpochID(1))
	blackbirdKafkaAdmin := helpers.FakeAdminClientWithOffsets(
		t,
		types.EpochID(1),
		// NOTE: This is an invalid Kafka offset and should never happen
		map[string]map[int32]*sarama.OffsetFetchResponseBlock{backfillTopic: {0: {Offset: -3}}},
	)

	d := NewIngestModeDetector(store, nil, blackbirdKafkaAdmin, nil, 1, routing.Dotcom)
	require.Panics(t, func() { _ = d.check(ctx) })
}

func mockStore(t *testing.T, startingIngestMode db.IngestMode, offsets db.EpochOffsets) *dbfakes.FakeStore {
	t.Helper()

	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(ctx context.Context, c routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c, EpochID: 1, IngestMode: startingIngestMode}, nil
	}
	store.SetCorpusIngestModeReturns(true, nil)
	store.GetEpochEndOffsetsReturns(offsets, nil)
	return store
}
