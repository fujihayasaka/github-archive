package deltaingest

import (
	"sync"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/types"
)

// An operation that orders tasks so that ancestors are processed before their
// children.
type AncestorOrderingOp struct {
	inner  Op
	buffer map[types.RepoID][]*Task
	mutex  sync.Mutex
}

func NewAncestorOrderingOp(inner Op) *AncestorOrderingOp {
	return &AncestorOrderingOp{inner, make(map[types.RepoID][]*Task), sync.Mutex{}}
}

func (o *AncestorOrderingOp) Run(task *Task) {
	task.Begin(o)

	// Check if this task can run. Tasks with inflight ancestors will wait for
	// their parent to finish before running themselves.
	shouldRun := func() bool {
		o.mutex.Lock()
		defer o.mutex.Unlock()

		if _, ok := o.buffer[task.repoID()]; ok {
			panic("a task for this repo is already inflight")
		}

		o.buffer[task.repoID()] = nil // mark this repo as inflight

		if len(task.event.BlackbirdAncestorRepoIds) > 0 {
			parentID := types.RepoID(task.event.BlackbirdAncestorRepoIds[0])
			if _, ok := o.buffer[parentID]; ok {
				// this task's parent repo is inflight: buffer the task
				logging.Info(task.ctx, "ancestor ordering: buffering task because parent is inflight")
				o.buffer[parentID] = append(o.buffer[parentID], task)
				return false
			}
			// has parent, but isn't inflight (assume finished): run the task
			return true
		} else {
			// no parents: run the task
			return true
		}
	}()

	if shouldRun {
		o.inner.Run(task)
	}
}

func (o *AncestorOrderingOp) OnDone(task *Task, err error) {
	// Fetch any tasks that are waiting on this task to finish. Do this in a block
	// so that we don't hold the lock while calling Run or Done.
	waitingTasks := func() []*Task {
		o.mutex.Lock()
		defer o.mutex.Unlock()

		statting.Gauge(task.ctx, "ingest.consumer.ancestor_waiting_buffer_size", int64(len(o.buffer)))

		waitingTasks := o.buffer[task.repoID()]
		delete(o.buffer, task.repoID())
		return waitingTasks
	}()

	// Call Done on the original task before running more tasks to allow a
	// wrapping operation like offset tracking to commit offsets for the finished
	// task.
	task.Done(err)
	if len(waitingTasks) > 0 {
		logging.Info(task.ctx, "ancestor ordering: parent task finished, releasing child tasks", kvp.Int("num_child_tasks", len(waitingTasks)))
	}
	for _, waitingTask := range waitingTasks {
		o.inner.Run(waitingTask)
	}
}
