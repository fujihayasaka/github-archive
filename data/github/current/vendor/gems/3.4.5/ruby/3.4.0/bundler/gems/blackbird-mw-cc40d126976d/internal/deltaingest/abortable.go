package deltaingest

import (
	"context"
	"sync"

	"golang.org/x/sync/semaphore"
)

// An operation that aborts an entire stack of operations on the first task
// error or via an explicit call to Abort.
//
// Once aborted, any further tasks you run will be dropped: the inner Op will
// not run and the OnDone callbacks will not fire. Because of this it is
// recommended that AbortableOp be the outermost operation in the stack.
//
// AbortableOp also sets a limit on the number of concurrent tasks and is
// designed to work in sync with the WorkPoolOp. When using them together
// maxConcurrentTasks should equal the WorkPoolOps bufferSize and this value
// should be >= the WorkPoolOps numWorkers.
type AbortableOp struct {
	inner  Op
	wg     sync.WaitGroup
	sem    *semaphore.Weighted
	cancel context.CancelFunc
	mutex  sync.Mutex
	anyErr error
}

// Returns a new AbortableOp.
//
// The cancel func will be called on Abort. The maxConcurrentTasks parameter
// determines how many concurrent tasks can be inflight before `Run` blocks.
func NewAbortableOp(cancel context.CancelFunc, maxConcurrentTasks int, inner Op) *AbortableOp {
	op := &AbortableOp{inner, sync.WaitGroup{}, semaphore.NewWeighted(int64(maxConcurrentTasks)), cancel, sync.Mutex{}, nil}
	op.wg.Add(1) // so that Wait blocks before running any tasks
	return op
}

func (o *AbortableOp) Run(task *Task) {
	// limit the number of concurrent tasks we run through the operation stack.
	err := o.sem.Acquire(task.ctx, 1)
	if err != nil {
		o.Abort(err)
		return
	}

	shouldRun := func() bool {
		o.mutex.Lock()
		defer o.mutex.Unlock()
		if o.anyErr == nil {

			o.wg.Add(1)
			return true
		} else {
			// If there's been an error, we are aborting: do not run any more tasks
			return false
		}
	}()

	if shouldRun {
		task.Begin(o)
		o.inner.Run(task)
	} else {
		o.sem.Release(1)
	}
}

func (o *AbortableOp) OnDone(task *Task, err error) {
	if err != nil {
		o.Abort(err)
	}
	o.sem.Release(1)
	o.wg.Done()
	task.Done(err)
}

// Abort processing of the entire stack of operations by calling the saved
// context.CancelFunc and saving the error that caused abort.
//
// Panics if err is nil.
func (o *AbortableOp) Abort(err error) {
	if err == nil {
		panic("must provide an error to abort")
	}

	o.mutex.Lock()
	defer o.mutex.Unlock()
	if o.anyErr == nil {
		o.anyErr = err // capture the error
		o.cancel()     // cancel the context
		o.wg.Done()    // mark that this abort op is done
	}
}

// Waits on all submitted tasks to be done and returns an error (if any).
func (o *AbortableOp) Wait() error {
	o.wg.Wait() // wait for all tasks (and the operation itself) to be done
	o.mutex.Lock()
	defer o.mutex.Unlock()
	return o.anyErr
}
