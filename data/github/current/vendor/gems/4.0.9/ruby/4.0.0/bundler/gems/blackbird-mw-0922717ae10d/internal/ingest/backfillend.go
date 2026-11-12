package ingest

import (
	"github.com/github/go-telemetry/logging"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"

	"github.com/github/blackbird-mw/internal/db"
)

type BackfillEndOp struct {
	inner Op
}

func NewBackfillEndOp(inner Op) *BackfillEndOp {
	return &BackfillEndOp{inner}
}

func (o *BackfillEndOp) Run(task *Task) {
	task.Begin(o)

	if isEndOfBackfillSentinel(task) {
		logging.Info(task.ctx, "reached end of backfill partition")
		task.Done(nil)
	} else {
		o.inner.Run(task)
	}
}

func (o *BackfillEndOp) OnDone(task *Task, err error) {
	task.Done(err)
}

// When the cache server is done publishing backfill messages, it publishes one
// more message with these attributes as an end of backfill sentinel.
func isEndOfBackfillSentinel(task *Task) bool {
	event := task.event
	corpus := task.corpus.Corpus
	epochID := task.corpus.EpochID

	return task.corpus.IngestMode == db.IngestModeBackfill &&
		task.msg.Topic == corpus.EpochBackfillTopic(epochID) &&
		event.Change == searchpb.RepositoryChanged_ADMIN_PUSHED &&
		event.Repository == nil &&
		event.BlackbirdEpochId == int64(epochID)
}
