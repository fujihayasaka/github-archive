package deltaingest_test

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	hydro_schemas_github_search_v0 "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	entitiespb "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/db/mysqlerrors"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/deltaingest"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_SwitchModes(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)

	backfillMessages := make(chan hydro.Message, 1)
	backfillMsg := hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, corpus.EpochBackfillTopic(state.EpochID), 1, 1)
	backfillMessages <- backfillMsg
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

	ok, err := store.SetCorpusIngestMode(ctx, corpus, db.IngestModeBackfill, db.IngestModeBackfill)
	require.NoError(t, err)
	require.True(t, ok)

	c := deltaingest.NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		backfillSource,
		incrSource,
		helpers.IndexerCluster(t),
		state.EpochID,
	)
	// In backfill mode, we expect to read one message from the backfill source
	msg, _, err := c.ReadMessage(ctx)
	require.NoError(t, err)
	require.Equal(t, backfillMsg, msg)

	// In incremental mode, we expect to read one message from the incremental source
	ok, err = store.SetCorpusIngestMode(ctx, corpus, db.IngestModeBackfillCatchup, db.IngestModeBackfillCatchup)
	require.NoError(t, err)
	require.True(t, ok)
	msg, _, err = c.ReadMessage(ctx)
	require.NoError(t, err)
	require.Equal(t, incrMsg, msg)
}

func Test_EpochChangeReturnsError(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)

	const numMessages = 2
	backfillMessages := make(chan hydro.Message, numMessages)
	defer close(backfillMessages)

	for i := 0; i < numMessages; i++ {
		msg := hydroMsg(t,
			&searchpb.RepositoryChanged{
				Repository: &entitiespb.Repository{
					Id:      uint32(repo.RepoID),
					OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
					Name:    repo.Name,
				},
				OwnerName: repo.OwnerLogin,
			}, corpus.EpochBackfillTopic(state.EpochID), 0, int64(i))
		backfillMessages <- msg
	}
	backfillSource, err := hydro.NewMemorySource(backfillMessages)
	require.NoError(t, err)

	incrMessages := make(chan hydro.Message)
	close(incrMessages)
	incrSource, err := hydro.NewMemorySource(incrMessages)
	require.NoError(t, err)

	ok, err := store.SetCorpusIngestMode(ctx, corpus, db.IngestModeBackfill, db.IngestModeBackfill)
	require.NoError(t, err)
	require.True(t, ok)

	c := deltaingest.NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		backfillSource,
		incrSource,
		helpers.IndexerCluster(t),
		state.EpochID,
	)
	require.NoError(t, err)

	// Sleep one second so that ReadMessage will read the latest ingest mode
	time.Sleep(time.Second)
	// Read the first message
	_, _, err = c.ReadMessage(ctx)
	require.NoError(t, err)

	// After reading the first message, change the epoch ID. Now we should get an error.
	_, err = store.CreateEpoch(ctx, corpus, "new epoch for testing")
	require.NoError(t, err)

	// Sleep one second so that ReadMessage will read the latest ingest mode
	time.Sleep(time.Second)
	_, _, err = c.ReadMessage(ctx)
	require.Error(t, err)
	require.ErrorIs(t, err, deltaingest.ErrEpochChanged)
}

func Test_MySQLServerShutdownContinues(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	state := &db.CorpusState{
		Corpus:     corpus,
		EpochID:    123,
		IngestMode: db.IngestModeBackfill,
	}
	repo := helpers.Repositories(t, 1)[0]
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateReturnsOnCall(0, nil, mysqlerrors.ServerShutdownError())
	store.GetCorpusStateReturns(state, nil)

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
		}, corpus.EpochBackfillTopic(state.EpochID), 0, 1)
	backfillMessages <- msg

	backfillSource, err := hydro.NewMemorySource(backfillMessages)
	require.NoError(t, err)

	incrMessages := make(chan hydro.Message)
	close(incrMessages)
	incrSource, err := hydro.NewMemorySource(incrMessages)
	require.NoError(t, err)

	c := deltaingest.NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		backfillSource,
		incrSource,
		helpers.IndexerCluster(t),
		state.EpochID,
	)
	require.NoError(t, err)

	// Reading the message should succeed
	_, _, err = c.ReadMessage(ctx)
	require.NoError(t, err)

	require.Equal(t, 2, store.GetCorpusStateCallCount(), "expected two calls to GetCorpusState due to MySQL shutdown error")
}

func hydroMsg(t *testing.T, event *hydro_schemas_github_search_v0.RepositoryChanged, topic string, partition int32, offset int64) hydro.Message {
	encoder := hydro.NewDefaultEncoder()
	data, err := encoder.Encode(event, time.Now())
	require.NoError(t, err)

	key := strconv.Itoa(int(event.GetRepository().GetId()))

	return hydro.Message{
		Topic:     topic,
		Partition: partition,
		Offset:    offset,
		Key:       []byte(key),
		Value:     data,
	}
}
