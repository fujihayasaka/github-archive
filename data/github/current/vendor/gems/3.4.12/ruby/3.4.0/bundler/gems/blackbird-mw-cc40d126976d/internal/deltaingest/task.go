package deltaingest

import (
	"context"
	"math"
	"time"

	hydroschemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	"github.com/golang/protobuf/proto" //nolint:staticcheck

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// Marker for initial commit sequence number being unknown.
const unknownCommitSeqNo uint64 = math.MaxUint64

func NewTask(ctx context.Context, msg hydro.Message, state *db.CorpusState, stamp routing.Stamp) (*Task, error) {
	envelope := hydroschemas.Envelope{}
	if err := proto.Unmarshal(msg.Value, &envelope); err != nil {
		return nil, err
	}

	event := searchpb.RepositoryChanged{}
	if err := proto.Unmarshal(envelope.Message, &event); err != nil {
		return nil, err
	}

	return &Task{
		msg:                msg,
		envelope:           &envelope,
		event:              &event,
		receivedAt:         time.Now(),
		corpus:             state,
		stamp:              stamp,
		initialCommitSeqNo: unknownCommitSeqNo,
		ctx:                ctx,
		ops:                []Op{},
	}, nil

}

// Task represents the work of ingesting a repo to a corpus.
type Task struct {
	msg                hydro.Message
	envelope           *hydroschemas.Envelope
	event              *searchpb.RepositoryChanged
	receivedAt         time.Time
	corpus             *db.CorpusState
	stamp              routing.Stamp
	initialCommitSeqNo uint64 // The first successfully generated commit sequence number. Should be set to unknownCommitSeqNo on initialization.
	ctx                context.Context
	ops                []Op
}

func (t *Task) repoID() types.RepoID {
	return types.RepoID(t.event.GetRepository().GetId())
}

func (t *Task) messageID() kafka.MessageID {
	return kafka.MessageID{Topic: t.msg.Topic, Partition: t.msg.Partition, Offset: t.msg.Offset, Timestamp: t.msg.Timestamp}
}

// Mark that an operation has started by pushing that op onto the task's stack
// of operations.
func (t *Task) Begin(op Op) {
	t.ops = append(t.ops, op)
}

// Mark that an operation is finished by popping the operation stack. Also
// notifies the next operation in the stack by calling its OnDone callback. In
// order to prevent deadlocks, it is important that callers NOT hold any locks
// when calling Done.
func (t *Task) Done(err error) {
	if len(t.ops) == 0 {
		panic("empty operation stack")
	}

	// pop this operation
	t.ops = t.ops[:len(t.ops)-1]

	// finish the remaining operations
	if len(t.ops) > 0 {
		op := t.ops[len(t.ops)-1]
		op.OnDone(t, err)
	}
}
