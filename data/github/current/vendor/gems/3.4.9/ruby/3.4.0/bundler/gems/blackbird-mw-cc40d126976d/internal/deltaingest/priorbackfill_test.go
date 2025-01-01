package deltaingest

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_PriorBackfillFilterOp(t *testing.T) {
	logOp := NewTestLogOp()
	filter := NewPriorBackfillFilterOp(logOp)

	priorBackfillTask := newTaskWithRepoID(t, uint32(helpers.RepoID(t)))
	priorBackfillTask.event.BlackbirdEpochId = 1
	priorBackfillTask.corpus = &db.CorpusState{
		EpochID:    2,
		IngestMode: db.IngestModeBackfill,
	}

	currentBackfillTask := newTaskWithRepoID(t, uint32(helpers.RepoID(t)))
	currentBackfillTask.event.BlackbirdEpochId = 2
	currentBackfillTask.corpus = &db.CorpusState{
		EpochID:    2,
		IngestMode: db.IngestModeBackfill,
	}

	// Not in backfill mode any more? => ignore the epoch ID
	nonBackfillTask := newTaskWithRepoID(t, uint32(helpers.RepoID(t)))
	nonBackfillTask.event.BlackbirdEpochId = -1
	nonBackfillTask.corpus = &db.CorpusState{
		EpochID:    2,
		IngestMode: db.IngestModeBackfillCatchup,
	}

	filter.Run(priorBackfillTask)
	filter.Run(currentBackfillTask)
	filter.Run(nonBackfillTask)

	require.Len(t, logOp.log, 2)
	require.Equal(t, logOp.log[0], currentBackfillTask)
	require.Equal(t, logOp.log[1], nonBackfillTask)
}
