package deltaingest

import (
	"fmt"
	"time"

	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/google/uuid"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/routing"
)

// An operation that sets up kvps in the context for logging and logs when tasks
// start and finish.
type LoggingContextOp struct {
	inner Op
}

func NewLoggingContextOp(inner Op) *LoggingContextOp {
	return &LoggingContextOp{inner}
}

func (o *LoggingContextOp) Run(task *Task) {
	task.Begin(o)

	rid := newRequestID(task.corpus.Corpus, task.corpus.IngestMode)
	task.ctx = requestid.WithGitHubRequestID(task.ctx, rid)

	task.ctx = logging.With(task.ctx,
		kvp.String("topic", task.msg.Topic),
		kvp.Int64("partition", int64(task.msg.Partition)),
		kvp.Int64("offset", task.msg.Offset),
		kvp.String("hydro_id", task.envelope.GetId()),
		kvp.Int("repo_id", int(task.repoID())),
		kvp.Stringer("change", task.event.GetChange()),
		kvp.Int("epoch_id", int(task.corpus.EpochID)),
		kvp.String("ingest_mode", task.corpus.IngestMode.String()),
		kvp.Time("received_at", task.receivedAt),
		kvp.String("request_id", rid),
	)
	logging.Info(task.ctx, "running task")

	o.inner.Run(task)
}

func (o *LoggingContextOp) OnDone(task *Task, err error) {
	if err != nil {
		logging.Info(task.ctx, "task finished with error", kvp.Any("duration", time.Since(task.receivedAt)), kvp.Duration("duration_ms", time.Since(task.receivedAt)), kvp.Err(err))
	} else {
		logging.Info(task.ctx, "task finished", kvp.Any("duration", time.Since(task.receivedAt)), kvp.Duration("duration_ms", time.Since(task.receivedAt)))
	}

	task.Done(err)
}

// newRequestID returns an opaque ID to use for outgoing requests related to an
// ingest for a repository change.
func newRequestID(corpus routing.Corpus, ingestMode db.IngestMode) string {
	return fmt.Sprintf("%s;corpus=%s;mode=%s", uuid.New().String(), corpus.String(), ingestMode.String())
}
