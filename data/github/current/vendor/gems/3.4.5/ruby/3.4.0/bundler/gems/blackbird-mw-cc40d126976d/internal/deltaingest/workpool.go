package deltaingest

import (
	"context"
	"sync"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/utils"
)

// This operation runs tasks concurrently by fanning them out to a fixed pool of
// workers. Results are reported asynchronously.
//
// WorkPoolOp buffers tasks and is designed to work in sync with the
// AbortableOp. When using them together the AbortableOp's maxConcurrentTasks
// should equal the WorkPoolOp's bufferSize and this value should be >=
// numWorkers.
type WorkPoolOp struct {
	inner Op
	wg    *sync.WaitGroup
	tasks chan *Task
}

// Returns a new WorkPoolOp with numWorkers goroutines and a bufferSize of how
// many tasks can be waiting for a worker before `Run()` blocks.
//
// NOTE: You must call `Close()` on this operation when you're done with it.
// Calling `Run` after you've called `Close` will panic.
func NewWorkPoolOp(ctx context.Context, bufferSize, numWorkers int, inner Op) *WorkPoolOp {
	wg := sync.WaitGroup{}
	tasks := make(chan *Task, bufferSize)
	op := WorkPoolOp{inner, &wg, tasks}

	wg.Add(numWorkers)
	for i := 0; i < numWorkers; i++ {
		go func(id int) {
			defer utils.PanicLogger(ctx)
			defer wg.Done()

			for task := range tasks {
				task.ctx = logging.With(task.ctx, kvp.Int("worker_id", id))
				inner.Run(task)
			}
		}(i)
	}

	return &op
}

func (o *WorkPoolOp) Run(task *Task) {
	task.Begin(o)
	o.tasks <- task
}

func (o *WorkPoolOp) OnDone(task *Task, err error) {
	task.Done(err)
}

// Close the work pool and wait until all workers have exited.
func (o *WorkPoolOp) Close() {
	close(o.tasks) // Do not accept any more tasks
	o.wg.Wait()    // Wait on all workers
}
