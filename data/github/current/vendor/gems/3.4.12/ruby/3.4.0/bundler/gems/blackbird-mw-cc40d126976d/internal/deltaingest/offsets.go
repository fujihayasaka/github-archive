package deltaingest

import (
	"github.com/github/blackbird-mw/internal/kafka"
)

// An operation that tracks and commits Kafka offsets for each topic/partition
// being consumed.
//
// This operation ensures that messages are only seen by inner operations
// **once** and that all tasks are run (started) in strictly monotonically
// increasing offset order on a topic/partition basis.
//
// Offsets are committed for tasks that complete successfully. Offsets are not
// committed for tasks that error as a task error is considered fatal (pod will
// restart).
//
// Tasks may be completed out of order. Because of this, it is possible for a
// task to finish, but not yet have its offset committed as we need to wait
// until the preceding tasks complete. Every time a task finishes, a safe to
// commit offset is calculated and if found will be committed to Kafka.
//
// Committing offsets **can** fail and this is usually due to Kafka rebalancing:
// if a pod's partition assignment changes, it is no longer possible to commit
// offsets to your old partition.
//
// During Kafka rebalances, reassignment of the same partition may cause the
// consumer may "replay" some portion of messages that have already been
// consumed and are either actively being processed by the rest of the operation
// stack or already finished.
//
//   - Messages that have been consumed, processed, and committed will be skipped
//     entirely.
//   - Messages that have been consumed and are inflight (still processing)
//     won't be re-run: the inflight message will commit offsets when it finishes.
type OffsetTrackingOp struct {
	inner   Op
	tracker kafka.OffsetTracker
}

func NewOffsetTrackingOp(offsetTracker *kafka.OffsetTracker, inner Op) *OffsetTrackingOp {
	return &OffsetTrackingOp{inner, *offsetTracker}
}

func (o *OffsetTrackingOp) Run(task *Task) {
	task.Begin(o)

	if o.tracker.TrackMsg(task.ctx, task.msg.Topic, task.msg.Partition, task.msg.Offset, task.msg.Timestamp) {
		o.inner.Run(task)
	} else {
		task.Done(nil)
	}
}

func (o *OffsetTrackingOp) OnDone(task *Task, err error) {
	// An error will cause the entire pipeline to shutdown. In that case we
	// don't want to mark offsets and certainly don't want to mark offsets for a
	// task with an error.
	if err == nil {
		o.tracker.MarkOffset(task.ctx, task.msg.Topic, task.msg.Partition, task.msg.Offset)
	}

	task.Done(err)
}
