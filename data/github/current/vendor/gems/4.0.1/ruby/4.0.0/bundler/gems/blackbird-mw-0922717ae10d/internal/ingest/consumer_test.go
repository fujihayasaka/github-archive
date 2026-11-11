package ingest

import (
	"context"
	"errors"
	"testing"
	"time"

	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	entitiespb "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/db/mysqlerrors"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_SwitchModes(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()
	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)
	backfillTopic := corpus.EpochBackfillTopic(state.EpochID)
	backfillMessages := make(chan hydro.Message, 1)
	backfillMsg := hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, backfillTopic, 1, 1)
	backfillMessages <- backfillMsg
	defer close(backfillMessages)
	backfillSource, err := hydro.NewMemorySource(backfillMessages)
	require.NoError(t, err)

	incrMessages := make(chan hydro.Message, 3)
	incrMsg1 := hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, routing.IncrementalSourceTopic, 2, 2)
	incrMsg2 := hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, routing.IncrementalSourceTopic, 2, 3)
	incrMsg3 := hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, routing.IncrementalSourceTopic, 2, 4)
	incrMessages <- incrMsg1
	incrMessages <- incrMsg2
	incrMessages <- incrMsg3
	defer close(incrMessages)
	incrSource, err := hydro.NewMemorySource(incrMessages)
	require.NoError(t, err)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetRandomHost(ctx)
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	// Not all partitions have marked the end of the backfill => read from backfill topic in IngestModeBackfill
	fakeIndexAPI.StatusReturns(
		&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				EpochId: uint32(state.EpochID),
				Shards: []*servingpb.Shard{{
					SourceKafkaInfo: map[string]*servingpb.KafkaInfo{
						backfillTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: 123},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 123).Raw()},
							},
						},
					},
				}},
			},
		}, nil)

	c := NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		routing.TopicConfig{
			Backfill:    routing.BackfillTopicConfig{Partitions: 2},
			Onboard:     routing.OnboardTopicConfig{Partitions: 2},
			Incremental: routing.IncrementalTopicConfig{Partitions: 2},
		},
		backfillSource,
		incrSource,
		indexerCluster,
		state.EpochID,
		time.Duration(0),
	)
	// In backfill mode, we expect to read one message from the backfill source
	msg, msgState, err := c.ReadMessage(ctx)
	require.NoError(t, err)
	require.Equal(t, backfillMsg, msg)
	require.Equal(t, db.IngestModeBackfill, msgState.IngestMode)

	// All partitions have marked the end of the backfill, but incremental topics are not all marked => read from incremental topic in IngestModeBackfillCatchup
	fakeIndexAPI.StatusReturns(
		&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				EpochId: uint32(state.EpochID),
				Shards: []*servingpb.Shard{{
					SourceKafkaInfo: map[string]*servingpb.KafkaInfo{
						backfillTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 123).Raw()},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 123).Raw()},
							},
						},
						routing.OnboardSourceTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: 999},
								1: {Offset: 345},
							},
						},
						routing.IncrementalSourceTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 1).Raw()},
								1: {Offset: 1},
							},
						},
					},
				}},
			},
		}, nil)
	// In backfill catchup mode, we expect to read one message from the incremental source
	msg, msgState, err = c.ReadMessage(ctx)
	require.NoError(t, err)
	require.Equal(t, incrMsg1, msg)
	require.Equal(t, db.IngestModeBackfillCatchup, msgState.IngestMode)

	// All partitions have marked the end of the backfill and incremental topics are caught up => publish mode transition and read from incremental topic in IngestModeIncremental
	fakeIndexAPI.StatusReturns(
		&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				EpochId: uint32(state.EpochID),
				Shards: []*servingpb.Shard{{
					SourceKafkaInfo: map[string]*servingpb.KafkaInfo{
						backfillTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 123).Raw()},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 123).Raw()},
							},
						},
						routing.OnboardSourceTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 999).Raw()},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 345).Raw()},
							},
						},
						routing.IncrementalSourceTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 1).Raw()},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 1).Raw()},
							},
						},
					},
				}},
			},
		}, nil)

	// In incremental mode, we expect to read one message from the incremental source
	msg, msgState, err = c.ReadMessage(ctx)
	require.NoError(t, err)
	require.Equal(t, incrMsg2, msg)
	require.Equal(t, db.IngestModeIncremental, msgState.IngestMode)

	// Now that we are in incremental mode, the indexer API will not be checked: we stay in incremental mode until an epoch change is detected
	fakeIndexAPI.StatusReturns(nil, errors.New("this error is not going to be returned"))
	c.lastModeFetch = time.Now().Add(-1 * time.Minute)
	msg, msgState, err = c.ReadMessage(ctx)
	require.NoError(t, err)
	require.Equal(t, incrMsg3, msg)
	require.Equal(t, db.IngestModeIncremental, msgState.IngestMode)
}

func Test_DetectIncrementalModeOnStartup(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()
	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)
	backfillTopic := corpus.EpochBackfillTopic(state.EpochID)
	backfillMessages := make(chan hydro.Message)
	defer close(backfillMessages)
	backfillSource, err := hydro.NewMemorySource(backfillMessages)
	require.NoError(t, err)

	incrMessages := make(chan hydro.Message, 1)
	incrMsg := hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, routing.IncrementalSourceTopic, 2, 2)
	incrMessages <- incrMsg
	defer close(incrMessages)
	incrSource, err := hydro.NewMemorySource(incrMessages)
	require.NoError(t, err)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetRandomHost(ctx)
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	// All partitions are marked => we are in incremental mode based on indexer status
	fakeIndexAPI.StatusReturns(
		&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				EpochId: uint32(state.EpochID),
				Shards: []*servingpb.Shard{{
					SourceKafkaInfo: map[string]*servingpb.KafkaInfo{
						backfillTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 123).Raw()},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 123).Raw()},
							},
						},
						routing.OnboardSourceTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 999).Raw()},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 345).Raw()},
							},
						},
						routing.IncrementalSourceTopic: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 1).Raw()},
								1: {Offset: helpers.MarkedKafkaOffsetWithMark(t, 1).Raw()},
							},
						},
					},
				}},
			},
		}, nil)

	c := NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		routing.TopicConfig{
			Backfill:    routing.BackfillTopicConfig{Partitions: 2},
			Onboard:     routing.OnboardTopicConfig{Partitions: 2},
			Incremental: routing.IncrementalTopicConfig{Partitions: 2},
		},
		backfillSource,
		incrSource,
		indexerCluster,
		state.EpochID,
		time.Duration(0),
	)
	// In incremental mode, we expect to read one message from the incremental
	// source. We don't use the Kafka client and publish no messages.
	msg, msgState, err := c.ReadMessage(ctx)
	require.NoError(t, err)
	require.Equal(t, incrMsg, msg)
	require.Equal(t, db.IngestModeIncremental, msgState.IngestMode)
}

func Test_EpochChangeReturnsError(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)
	backfillTopic := corpus.EpochBackfillTopic(state.EpochID)
	backfillTopicConsumed := routing.ConsumedTopic(backfillTopic)

	const numMessages = 2
	backfillMessages := make(chan hydro.Message, numMessages)
	defer close(backfillMessages)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetRandomHost(ctx)
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	// Partitions have not recorded reaching the end of the backfill => read from backfill topic in IngestModeBackfill
	fakeIndexAPI.StatusReturns(
		&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				EpochId: uint32(state.EpochID),
				Shards: []*servingpb.Shard{{
					SourceKafkaInfo: map[string]*servingpb.KafkaInfo{
						backfillTopicConsumed: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: 123},
								1: {Offset: 456},
							},
						},
					},
				}},
			},
		}, nil)

	for i := 0; i < numMessages; i++ {
		msg := hydroMsg(t,
			&searchpb.RepositoryChanged{
				Repository: &entitiespb.Repository{
					Id:      uint32(repo.RepoID),
					OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
					Name:    repo.Name,
				},
				OwnerName: repo.OwnerLogin,
			}, backfillTopic, 0, int64(i))
		backfillMessages <- msg
	}
	backfillSource, err := hydro.NewMemorySource(backfillMessages)
	require.NoError(t, err)

	incrMessages := make(chan hydro.Message)
	close(incrMessages)
	incrSource, err := hydro.NewMemorySource(incrMessages)
	require.NoError(t, err)

	c := NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		routing.TopicConfig{},
		backfillSource,
		incrSource,
		indexerCluster,
		state.EpochID,
		time.Duration(0),
	)

	// Read the first message
	_, _, err = c.ReadMessage(ctx)
	require.NoError(t, err)

	// After reading the first message, change the epoch ID. Now we should get an error.
	_, err = store.CreateEpoch(ctx, corpus, "new epoch for testing")
	require.NoError(t, err)

	// Pretend to sleep one second so that ReadMessage will read the latest ingest mode
	c.lastStateFetch = time.Now().Add(-1 * time.Minute)

	_, _, err = c.ReadMessage(ctx)
	require.Error(t, err)
	require.ErrorIs(t, err, ErrEpochChanged)
}

func Test_MySQLServerShutdownContinues(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	state := &db.CorpusState{
		Corpus:  corpus,
		EpochID: 123,
	}
	repo := helpers.Repositories(t, 1)[0]
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturnsOnCall(0, nil, mysqlerrors.ServerShutdownError())
	store.GetCorpusStateReturns(state, nil)
	backfillTopic := corpus.EpochBackfillTopic(state.EpochID)
	backfillTopicConsumed := routing.ConsumedTopic(backfillTopic)

	indexerCluster := helpers.IndexerCluster(t)
	host, err := indexerCluster.GetRandomHost(ctx)
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, host)
	// Partitions have not recorded reaching the end of the backfill => read from backfill topic in IngestModeBackfill
	fakeIndexAPI.StatusReturns(
		&servingpb.StatusResponse{
			Status: &servingpb.ServingStatus{
				EpochId: uint32(state.EpochID),
				Shards: []*servingpb.Shard{{
					SourceKafkaInfo: map[string]*servingpb.KafkaInfo{
						backfillTopicConsumed: {
							Partitions: map[int32]*servingpb.OffsetTimestamp{
								0: {Offset: 123},
								1: {Offset: 456},
							},
						},
					},
				}},
			},
		}, nil)

	backfillMessages := make(chan hydro.Message, 1)
	defer close(backfillMessages)

	msg := hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, backfillTopic, 0, 1)
	backfillMessages <- msg

	backfillSource, err := hydro.NewMemorySource(backfillMessages)
	require.NoError(t, err)

	incrMessages := make(chan hydro.Message)
	close(incrMessages)
	incrSource, err := hydro.NewMemorySource(incrMessages)
	require.NoError(t, err)

	c := NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		routing.TopicConfig{},
		backfillSource,
		incrSource,
		indexerCluster,
		state.EpochID,
		time.Duration(0),
	)
	// Reading the message should succeed
	_, _, err = c.ReadMessage(ctx)
	require.NoError(t, err)

	require.Equal(t, 2, store.GetCorpusStateCallCount(), "expected two calls to GetCorpusState due to MySQL shutdown error")
}
