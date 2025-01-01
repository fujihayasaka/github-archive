package deltaingest

// An operation performs some work on a task and signals when it is finished.
// Operations are intended to be nested, sort of like http handlers.
//
// As an example, a simple logging operation might be implemented like this:
//
//	type SimpleLoggingOp struct {
//	  inner Op
//	}
//
//	func (o *SimpleLoggingOp) Run(task *Task) {
//	  task.Begin(o)
//	  fmt.Printf("running %d", task.repoID())
//	  o.inner.Run(task)
//	}
//
//	func (o *SimpleLoggingOp) OnDone(task *Task, err error) {
//	  fmt.Printf("done with %d", task.repoID())
//	  task.Done(err)
//	}
//
// Operations can then be composed together to handle tasks. Look in the
// deltaingest package for other operations, but a simple setup might look like
// this:
//
//	app := NewLoggingContextOp(NewWorkPoolOp(ctx, 10, &EchoOp{}))
//	app.Run(task)
//
// Operations don't have to have an inner Op (but most do). Generally the
// operation on the bottom of the stack processes the task and reports success
// or failure via task.Done. It's OnDone callback will never be called because
// there is no further inner operation to trigger it.
//
// All structs implementing this interface should assume they're in a concurrent
// environment and appropriately protect internal state for access from multiple
// threads (e.g., use a mutex or other synchronization construct).
type Op interface {
	// Runs the operation for the task. An operation's `Run` implementation should
	// immediately call `task.Begin(o)`, passing itself as the operation. This
	// registers the operation in the Task's operation stack and allows `OnDone`
	// to fire when a subsequent (inner) task is finished.
	//
	// Each call to `task.Begin` must have a matching call to `task.Done` when the
	// operation has finished processing the task. It is invalid to call `Begin`
	// or `Done` multiple times for the same task.
	//
	// Run should be called on the top operation in the stack to begin processing
	// a task and each operation that has an inner Op is responsible for calling
	// `Run` on that operation.
	Run(task *Task)

	// The OnDone callback is called when the inner operation is done with the
	// task (when it calls `task.Done`). You should never call `OnDone` directly.
	// Instead, call `task.Done` when your operation is completely finished with a
	// task.
	OnDone(task *Task, err error)
}
