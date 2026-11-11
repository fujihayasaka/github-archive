package deltaingest

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_DebounceMultipleEventsToSameRepo(t *testing.T) {
	sink := NewTestCollectOp()
	debounce := NewDebounceReposOp(sink)
	op := NewBufferOp(debounce)

	// send 3 tasks for the same repo.
	op.Run(newTaskWithRepoID(t, 1)) // will get processed
	op.Run(newTaskWithRepoID(t, 1)) // buffered and then dropped without running
	op.Run(newTaskWithRepoID(t, 1)) // will get processed when the first one finishes

	require.Equal(t, 1, len(sink.tasks))         // only one task should have been released for processing
	require.Equal(t, 0, len(sink.finishedTasks)) // nothing's finished yet
	require.Equal(t, 1, len(debounce.buffer))    // task in flight
	require.NotNil(t, debounce.buffer[1])        // one task waiting in the buffer
	require.Equal(t, 1, len(op.doneTasks))       // skipped task
	require.Equal(t, 3, len(op.inTasks))

	// finish one task
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(sink.tasks))         // buffered task was released for processing
	require.Equal(t, 1, len(sink.finishedTasks)) // the task we finished
	require.Equal(t, 1, len(debounce.buffer))    // task in flight
	require.Nil(t, debounce.buffer[1])           // waiting task buffer is empty
	require.Equal(t, 2, len(op.doneTasks))       // skipped task + one we just finished
	require.Equal(t, 3, len(op.inTasks))

	// finish one more task (last one)
	sink.FinishLastOne(nil)

	require.Equal(t, 0, len(sink.tasks))         // nothing more to do
	require.Equal(t, 2, len(sink.finishedTasks)) // now we've completed a total of two tasks
	require.Equal(t, 0, len(debounce.buffer))    // debounce buffer is now empty
	require.Equal(t, 3, len(op.doneTasks))       // skipped task + two we finished
	require.Equal(t, 3, len(op.inTasks))
}

func Test_BufferButNoDebounceIfFinishedInTime(t *testing.T) {
	sink := NewTestCollectOp()
	debounce := NewDebounceReposOp(sink)
	op := NewBufferOp(debounce)

	op.Run(newTaskWithRepoID(t, 1))
	op.Run(newTaskWithRepoID(t, 1))

	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 0, len(sink.finishedTasks))
	require.Equal(t, 1, len(debounce.buffer))
	require.NotNil(t, debounce.buffer[1])
	require.Equal(t, 0, len(op.doneTasks))
	require.Equal(t, 2, len(op.inTasks))

	// finishing a task should start processing the buffered task
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, len(debounce.buffer))
	require.Nil(t, debounce.buffer[1])
	require.Equal(t, 1, len(op.doneTasks))
	require.Equal(t, 2, len(op.inTasks))

	// sending another task will fill the buffer again
	op.Run(newTaskWithRepoID(t, 1))

	require.Equal(t, 1, len(sink.tasks))
	require.Equal(t, 1, len(sink.finishedTasks))
	require.Equal(t, 1, len(debounce.buffer))
	require.NotNil(t, debounce.buffer[1])
	require.Equal(t, 1, len(op.doneTasks))
	require.Equal(t, 3, len(op.inTasks))

	// Finish a task and the one in the buffer
	sink.FinishLastOne(nil)
	sink.FinishLastOne(nil)

	require.Equal(t, 0, len(sink.tasks))
	require.Equal(t, 3, len(sink.finishedTasks))
	require.Equal(t, 0, len(debounce.buffer))
	require.Equal(t, 3, len(op.doneTasks))
	require.Equal(t, 3, len(op.inTasks))
}

func Test_NoDebounceOfEventsForDifferentRepos(t *testing.T) {
	sink := NewTestCollectOp()
	debounce := NewDebounceReposOp(sink)
	op := NewBufferOp(debounce)
	op.Run(newTaskWithRepoID(t, 1))
	op.Run(newTaskWithRepoID(t, 2))

	// Two tasks were sent to the sink (and are marked inflight)
	require.Equal(t, 2, len(sink.tasks))
	require.Equal(t, 2, len(debounce.buffer))
	require.Nil(t, debounce.buffer[1])     // inflight, nothing buffered
	require.Nil(t, debounce.buffer[2])     // inflight, nothing buffered
	require.Equal(t, 0, len(op.doneTasks)) // nothing is done
	require.Equal(t, 2, len(op.inTasks))

	// finish both tasks
	sink.FinishLastOne(nil)
	sink.FinishLastOne(nil)

	// two tasks are done
	require.Equal(t, 2, len(sink.finishedTasks))
	require.Equal(t, 2, len(op.doneTasks))
	require.Equal(t, 0, len(debounce.buffer))
}

func Test_DebounceWithWorkPool(t *testing.T) {
	sink := NewTestCollectOp()
	wp := NewWorkPoolOp(context.Background(), 1, 1, sink)
	defer wp.Close()
	debounce := NewDebounceReposOp(wp)
	op := NewBufferOp(debounce)

	op.Run(newTaskWithRepoID(t, 1)) // will get processed
	op.Run(newTaskWithRepoID(t, 1)) // buffered and then dropped without running
	op.Run(newTaskWithRepoID(t, 1)) // will get processed when the first one finishes

	// with the work pool, we must finish one to assert state
	sink.FinishLastOne(nil)
	sink.WaitOne() // we expect that finishing a task will cause the buffered task to get run

	require.Equal(t, 1, len(sink.tasks))         // buffered task was passed on
	require.Equal(t, 1, len(sink.finishedTasks)) // we only finished a single task
	require.Equal(t, 1, len(debounce.buffer))    // there's a single task for this repo inflight
	require.Nil(t, debounce.buffer[1])           // but nothing buffered now
	require.Equal(t, 2, len(op.doneTasks))       // there are two "done" tasks (one was a skip)
	require.Equal(t, 3, len(op.inTasks))         // we've submitted a total of 3 tasks

	// finish the last task
	sink.FinishLastOne(nil)
	require.Equal(t, 0, len(sink.tasks))         // nothing more todo
	require.Equal(t, 2, len(sink.finishedTasks)) // two tasks were processed
	require.Equal(t, 0, len(debounce.buffer))    // debounce buffer is empty
	require.Equal(t, 3, len(op.doneTasks))       // three tasks are now done (one was a skip)
	require.Equal(t, 3, len(op.inTasks))         // we've submitted a total of 3 tasks
}
