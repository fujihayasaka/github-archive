package ingest

import (
	"testing"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_TaskOperationInterface(t *testing.T) {
	require.PanicsWithValue(t, "empty operation stack", func() {
		op := &DoubleDoneOp{}
		op.Run(newTaskWithRepoID(t, 1))
	})
}

// An operation that calls done twice (which is an error)
type DoubleDoneOp struct{}

func (o *DoubleDoneOp) Run(task *Task) {
	task.Begin(o)

	task.Done(nil)
	task.Done(nil)
}
func (o *DoubleDoneOp) OnDone(task *Task, err error) {}

func Test_markedKafkaOffset(t *testing.T) {
	corpus := helpers.Corpus(t)
	epochID := types.EpochID(123)
	topic := corpus.EpochBackfillTopic(epochID)
	var tests = []struct {
		mode         db.IngestMode
		markedOffset kafka.MarkedKafkaOffset
	}{
		{
			mode:         db.IngestModeBackfill,
			markedOffset: helpers.MarkedKafkaOffsetWithMark(t, 0),
		},
		{
			mode:         db.IngestModeBackfillCatchup,
			markedOffset: kafka.NewMarkedKafkaOffset(0),
		},

		{
			mode:         db.IngestModeIncremental,
			markedOffset: kafka.NewMarkedKafkaOffset(0),
		},
	}

	for _, test := range tests {
		t.Run(test.mode.String(), func(t *testing.T) {
			// This is a backfill sentinel message. But it should only mark the offset in backfill mode.
			task := Task{
				corpus: &db.CorpusState{
					Corpus:     corpus,
					EpochID:    epochID,
					IngestMode: test.mode,
				},
				msg: hydro.Message{
					Topic:  topic,
					Offset: test.markedOffset.Get(),
				},
				event: &searchpb.RepositoryChanged{
					Change:           searchpb.RepositoryChanged_ADMIN_PUSHED,
					Repository:       nil,
					BlackbirdEpochId: int64(epochID),
				},
			}
			require.Equal(t, test.markedOffset, task.markedKafkaOffset())
		})
	}
}
