package deltaingest

import "github.com/github/blackbird-mw/internal/db"

// PriorBackfillFilterOp is an operation that skips tasks read while the system
// is in backfill mode but are from a prior epoch.
//
// This happens when a backfill is triggered before fully consuming all messages
// for the prior epoch(s). The database state jumps ahead, but the old messages
// remain in Kafka. Ingesting these messages can cause the database state to become undefined.
//
// By examining the epoch ID on the message and comparing it to the state
// retrieved from the database before the message was read, we can skip these
// stale messages.
type PriorBackfillFilterOp struct {
	inner Op
}

func NewPriorBackfillFilterOp(inner Op) *PriorBackfillFilterOp {
	return &PriorBackfillFilterOp{inner}
}

func (o *PriorBackfillFilterOp) Run(task *Task) {
	task.Begin(o)

	if task.corpus.IngestMode == db.IngestModeBackfill &&
		task.event.BlackbirdEpochId != 0 &&
		task.event.BlackbirdEpochId < int64(task.corpus.EpochID) {
		task.Done(nil)
	} else {
		o.inner.Run(task)
	}
}

func (o *PriorBackfillFilterOp) OnDone(task *Task, err error) {
	task.Done(err)
}
