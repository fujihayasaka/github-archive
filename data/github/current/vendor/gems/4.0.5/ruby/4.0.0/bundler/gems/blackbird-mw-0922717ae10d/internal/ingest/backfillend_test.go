package ingest

import (
	"context"
	"testing"
	"time"

	hydropb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_BackfillEndOp(t *testing.T) {
	const endBackfillPartition = 1
	const endBackfillOffset = 1
	corpus := helpers.Corpus(t)
	epochID := types.EpochID(1)
	logOp := NewTestLogOp()

	op := NewBackfillEndOp(logOp)

	// repo ID != 0 => not end of backfill
	notBackfillEndTask := newTaskWithRepoID(t, 123)
	notBackfillEndTask.msg.Topic = corpus.EpochBackfillTopic(epochID)
	notBackfillEndTask.event.Change = searchpb.RepositoryChanged_ADMIN_PUSHED
	notBackfillEndTask.event.BlackbirdEpochId = int64(epochID)
	notBackfillEndTask.corpus = &db.CorpusState{
		Corpus:     corpus,
		EpochID:    epochID,
		IngestMode: db.IngestModeBackfill,
	}

	// repo ID 0 => end of backfill, report max offset
	sentinelEvent := &searchpb.RepositoryChanged{
		Repository:       nil,
		Change:           searchpb.RepositoryChanged_ADMIN_PUSHED,
		BlackbirdEpochId: int64(epochID),
	}
	backfillEndTask := &Task{
		ctx:        context.Background(),
		msg:        hydroMsg(t, sentinelEvent, corpus.EpochBackfillTopic(epochID), endBackfillPartition, endBackfillOffset),
		event:      sentinelEvent,
		envelope:   &hydropb.Envelope{},
		receivedAt: time.Now(),
		corpus: &db.CorpusState{
			Corpus:     corpus,
			EpochID:    epochID,
			IngestMode: db.IngestModeBackfill,
		},
	}

	// Not in backfill mode any more => can't be the end of the backfill
	nonBackfillTask := newTaskWithRepoID(t, 123)
	nonBackfillTask.msg.Topic = routing.OnboardSourceTopic
	nonBackfillTask.event.Change = searchpb.RepositoryChanged_ADMIN_PUSHED
	backfillEndTask.event.BlackbirdEpochId = int64(epochID)
	nonBackfillTask.corpus = &db.CorpusState{
		Corpus:     corpus,
		EpochID:    epochID,
		IngestMode: db.IngestModeBackfillCatchup,
	}

	op.Run(notBackfillEndTask)
	op.Run(backfillEndTask)
	op.Run(nonBackfillTask)

	require.Len(t, logOp.log, 2)
	require.Equal(t, logOp.log[0], notBackfillEndTask)
	require.Equal(t, logOp.log[1], nonBackfillTask)
}
