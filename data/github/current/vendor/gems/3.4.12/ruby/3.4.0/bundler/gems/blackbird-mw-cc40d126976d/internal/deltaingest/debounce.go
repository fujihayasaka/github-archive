package deltaingest

import (
	"fmt"
	"sync"

	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/types"
)

// An operation that debounces pushes to the same repository.
type DebounceReposOp struct {
	inner  Op
	buffer map[types.RepoID]*Task
	mutex  sync.Mutex
}

func NewDebounceReposOp(inner Op) *DebounceReposOp {
	return &DebounceReposOp{inner, make(map[types.RepoID]*Task), sync.Mutex{}}
}

func (o *DebounceReposOp) Run(task *Task) {
	task.Begin(o)

	taskToSkip, shouldRun := func() (*Task, bool) {
		o.mutex.Lock()
		defer o.mutex.Unlock()

		if bufferedTask, ok := o.buffer[task.repoID()]; ok {
			// there's either a task already inflight or a task already inflight AND
			// an already buffered task: put the current task in the buffer and return
			// the existing buffered task (if any) to be skipped.
			logging.Info(task.ctx, "debounce: buffering task")
			o.buffer[task.repoID()] = task
			return bufferedTask, false
		} else {
			// nothing inflight: mark as inflight and run this task
			o.buffer[task.repoID()] = nil
			return nil, true
		}
	}()

	if shouldRun {
		o.inner.Run(task)
	} else if taskToSkip != nil {
		logging.Info(taskToSkip.ctx, "debounce: skipping task")
		statting.Counter(taskToSkip.ctx, "ingest.consumer.task_debounced", 1, stats.Tags{"topicpartition": fmt.Sprintf("%s-%d", taskToSkip.msg.Topic, taskToSkip.msg.Partition)})
		taskToSkip.Done(nil)
	}
}

func (o *DebounceReposOp) OnDone(task *Task, err error) {
	taskToRun := func() *Task {
		o.mutex.Lock()
		defer o.mutex.Unlock()

		if bufferedTask := o.buffer[task.repoID()]; bufferedTask != nil {
			// If there's a buffered task, run it now
			o.buffer[task.repoID()] = nil
			return bufferedTask
		} else {
			// otherwise mark that this repo is no longer in flight
			delete(o.buffer, task.repoID())
			return nil
		}
	}()

	// Call Done on the original task before running more tasks to allow a
	// wrapping operation like offset tracking to commit offsets for the finished
	// task.
	task.Done(err)
	if taskToRun != nil {
		logging.Info(taskToRun.ctx, "debounce: running buffered task")
		o.inner.Run(taskToRun)
	}
}
