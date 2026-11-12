package deltaingest

import (
	"context"
	"testing"

	hydro_schemas_github_search_v0 "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/routing"
)

func Test_OrderingWaits(t *testing.T) {
	sink := NewTestCollectOp()
	ordering := NewAncestorOrderingOp(sink)
	op := NewBufferOp(ordering)

	// Process two tasks where the second one depends on the first finishing
	op.Run(newTaskWithAncestors(t, 1, nil))
	op.Run(newTaskWithAncestors(t, 2, []uint32{1}))

	require.Equal(t, 1, len(sink.tasks))         // only the first task should be passed on for processing
	require.Equal(t, 2, len(ordering.buffer))    // two different repos are inflight
	require.Equal(t, 1, len(ordering.buffer[1])) // repo_id=1 has repo 2 waiting on it
	require.Equal(t, 0, len(ordering.buffer[2])) // repo_id=2 doesn't have anything waiting on it
	require.Equal(t, 0, len(op.doneTasks))       // no tasks are done
	require.Equal(t, 2, len(op.inTasks))

	// finish a task
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(sink.tasks))         // the waiting task is released for processing
	require.Equal(t, 1, len(ordering.buffer))    // only repo_id=2 is inflight
	require.Equal(t, 0, len(ordering.buffer[2])) // repo_id=2 doesn't have anything waiting on it
	require.Equal(t, 1, len(op.doneTasks))       // one task is done now
	require.Equal(t, 2, len(op.inTasks))

	// finish the last task
	sink.FinishLastOne(nil)

	require.Equal(t, 0, len(sink.tasks))      // no more work to do
	require.Equal(t, 0, len(ordering.buffer)) // buffer is empty
	require.Equal(t, 2, len(op.doneTasks))    // two tasks are done now
	require.Equal(t, 2, len(op.inTasks))
}

func Test_OrderingInverseOrderDoesNotWait(t *testing.T) {
	sink := NewTestCollectOp()
	ordering := NewAncestorOrderingOp(sink)
	op := NewBufferOp(ordering)

	op.Run(newTaskWithAncestors(t, 2, []uint32{1}))
	op.Run(newTaskWithAncestors(t, 1, nil))

	require.Equal(t, 2, len(sink.tasks))         // both tasks get processed
	require.Equal(t, 2, len(ordering.buffer))    // both repos are marked as inflight
	require.Equal(t, 0, len(ordering.buffer[1])) // nothing in the buffer
	require.Equal(t, 0, len(ordering.buffer[2])) // nothing in the buffer
	require.Equal(t, 0, len(op.doneTasks))       // no tasks are done
	require.Equal(t, 2, len(op.inTasks))

	// Finish a task (this will finish repo_id=1)
	sink.FinishLastOne(nil)
	require.Equal(t, 1, len(sink.tasks))         // one task left to process
	require.Equal(t, 1, len(ordering.buffer))    // one inflight
	require.Equal(t, 0, len(ordering.buffer[2])) // nothing in the buffer
	require.Equal(t, 1, len(op.doneTasks))       // no tasks are done
	require.Equal(t, 2, len(op.inTasks))

	// Finish the last task (this will finish repo_id=2)
	sink.FinishLastOne(nil)
	require.Equal(t, 0, len(sink.tasks))      // nothing left to process
	require.Equal(t, 0, len(ordering.buffer)) // nothing inflight
	require.Equal(t, 2, len(op.doneTasks))    // both tasks are done
	require.Equal(t, 2, len(op.inTasks))
}

func Test_OrderingMultipleWait(t *testing.T) {
	sink := NewTestCollectOp()
	ordering := NewAncestorOrderingOp(sink)
	op := NewBufferOp(ordering)

	op.Run(newTaskWithAncestors(t, 1, nil))
	op.Run(newTaskWithAncestors(t, 2, []uint32{1}))
	op.Run(newTaskWithAncestors(t, 3, []uint32{1}))

	require.Equal(t, 1, len(sink.tasks))         // only the first task should be passed on for processing
	require.Equal(t, 3, len(ordering.buffer))    // three different repos are inflight
	require.Equal(t, 2, len(ordering.buffer[1])) // repo_id=1 has repo 2 and 3 waiting on it
	require.Equal(t, 0, len(ordering.buffer[2])) // repo_id=2 doesn't have anything waiting on it
	require.Equal(t, 0, len(ordering.buffer[3])) // repo_id=3 doesn't have anything waiting on it
	require.Equal(t, 0, len(op.doneTasks))       // no tasks are done
	require.Equal(t, 3, len(op.inTasks))

	// Finish repo_id=1
	sink.FinishLastOne(nil)

	require.Equal(t, 2, len(sink.tasks))         // repo_id=2 and repo_id3 are now passed for processing
	require.Equal(t, 2, len(ordering.buffer))    // two different repos are inflight
	require.Equal(t, 0, len(ordering.buffer[2])) // repo_id=2 doesn't have anything waiting on it
	require.Equal(t, 0, len(ordering.buffer[3])) // repo_id=3 doesn't have anything waiting on it
	require.Equal(t, 1, len(op.doneTasks))       // one task finished
	require.Equal(t, 3, len(op.inTasks))

	// finish out repo_id=2 and 3
	sink.FinishLastOne(nil)
	sink.FinishLastOne(nil)

	require.Equal(t, 0, len(sink.tasks))      // nothing to do
	require.Equal(t, 0, len(ordering.buffer)) // nothing inflight
	require.Equal(t, 3, len(op.doneTasks))    // three tasks finished
	require.Equal(t, 3, len(op.inTasks))
}

func Test_OrderingTreeWaits(t *testing.T) {
	sink := NewTestCollectOp()
	ordering := NewAncestorOrderingOp(sink)
	op := NewBufferOp(ordering)

	op.Run(newTaskWithAncestors(t, 1, nil))
	op.Run(newTaskWithAncestors(t, 2, []uint32{1}))
	op.Run(newTaskWithAncestors(t, 3, []uint32{2}))

	require.Equal(t, 1, len(sink.tasks))         // only the first task should be passed on for processing
	require.Equal(t, 3, len(ordering.buffer))    // three different repos are inflight
	require.Equal(t, 1, len(ordering.buffer[1])) // repo_id=1 has repo 2 waiting on it
	require.Equal(t, 1, len(ordering.buffer[2])) // repo_id=2 has repo 3 waiting on it
	require.Equal(t, 0, len(ordering.buffer[3])) // repo_id=3 doesn't have anything waiting on it
	require.Equal(t, 0, len(op.doneTasks))       // no tasks are done
	require.Equal(t, 3, len(op.inTasks))

	// finish repo_id=1
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(sink.tasks))         // unblocks repo_id=2 for processing
	require.Equal(t, 2, len(ordering.buffer))    // two different repos are inflight
	require.Equal(t, 1, len(ordering.buffer[2])) // repo_id=2 has repo 3 waiting on it
	require.Equal(t, 0, len(ordering.buffer[3])) // repo_id=3 doesn't have anything waiting on it
	require.Equal(t, 1, len(op.doneTasks))       // one task is done
	require.Equal(t, 3, len(op.inTasks))

	// finish repo_id=2
	sink.FinishLastOne(nil)

	require.Equal(t, 1, len(sink.tasks))         // unblocks repo_id=3 for processing
	require.Equal(t, 1, len(ordering.buffer))    // one repo inflight
	require.Equal(t, 0, len(ordering.buffer[3])) // repo_id=3 doesn't have anything waiting on it
	require.Equal(t, 2, len(op.doneTasks))       // two tasks are done
	require.Equal(t, 3, len(op.inTasks))

	// finish repo_id=3
	sink.FinishLastOne(nil)

	require.Equal(t, 0, len(sink.tasks))      // nothing to do
	require.Equal(t, 0, len(ordering.buffer)) // nothing inflight
	require.Equal(t, 3, len(op.doneTasks))    // all three tasks are done
	require.Equal(t, 3, len(op.inTasks))
}

func Test_OrderingPanicsIfRepoAlreadyInflight(t *testing.T) {
	sink := NewTestCollectOp()
	ordering := NewAncestorOrderingOp(sink)
	op := NewBufferOp(ordering)

	op.Run(newTaskWithAncestors(t, 1, nil))
	require.PanicsWithValue(t, "a task for this repo is already inflight", func() {
		op.Run(newTaskWithAncestors(t, 1, nil))
	})
}

func Test_OrderingWithWorkPool(t *testing.T) {
	sink := NewTestCollectOp()
	wp := NewWorkPoolOp(context.Background(), 1, 1, sink) // single worker
	defer wp.Close()
	ordering := NewAncestorOrderingOp(wp)
	op := NewBufferOp(ordering)

	op.Run(newTaskWithAncestors(t, 1, nil))
	op.Run(newTaskWithAncestors(t, 2, []uint32{1})) // will wait on repo_id=1
	op.Run(newTaskWithAncestors(t, 3, []uint32{1})) // will wait on repo_id=1
	op.Run(newTaskWithAncestors(t, 4, []uint32{1})) // will wait on repo_id=1

	// finish repo_id=1: unblock the others
	sink.FinishLastOne(nil)
	require.Equal(t, 1, len(op.doneTasks))

	// Finish the rest
	sink.WaitUntilN(3)
	sink.FinishCollected()
	require.Equal(t, 4, len(op.doneTasks))
}

func Test_OrderingTreeWithWorkPool(t *testing.T) {
	sink := NewTestCollectOp()
	wp := NewWorkPoolOp(context.Background(), 1, 1, sink) // single worker
	defer wp.Close()
	ordering := NewAncestorOrderingOp(wp)
	op := NewBufferOp(ordering)

	op.Run(newTaskWithAncestors(t, 1, nil))
	op.Run(newTaskWithAncestors(t, 2, []uint32{1})) // will wait on ^
	op.Run(newTaskWithAncestors(t, 3, []uint32{2})) // will wait on ^
	op.Run(newTaskWithAncestors(t, 4, []uint32{3})) // will wait on ^

	// finish repo_id=1: unblock the next
	sink.FinishLastOne(nil)
	require.Equal(t, 1, len(op.doneTasks))

	// finish repo_id=2: unblock the next
	sink.FinishLastOne(nil)
	require.Equal(t, 2, len(op.doneTasks))

	// finish repo_id=3: unblock the next
	sink.FinishLastOne(nil)
	require.Equal(t, 3, len(op.doneTasks))

	// finish repo_id=4
	sink.FinishLastOne(nil)
	require.Equal(t, 4, len(op.doneTasks))
}

func Test_OrderingIsThereAreNoDeadlocksWithWorkpool(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	sink := NewTestIngestOp()
	const maxConcurrentTasks = 2 // allow a small amount of buffering to allow ancestor ordering
	const numWorkers = 1         // single worker
	wp := NewWorkPoolOp(ctx, maxConcurrentTasks, numWorkers, sink)
	defer wp.Close()
	ordering := NewAncestorOrderingOp(wp)
	buf := NewBufferOp(ordering)
	op := NewAbortableOp(cancel, maxConcurrentTasks, buf)

	op.Run(newTaskWithAncestors(t, 1, nil))
	op.Run(newTaskWithAncestors(t, 2, []uint32{1}))

	// cannot call op.Run anymore at it would block since we've reached the max of
	// 2 concurrent tasks.
	sink.FinishFirst() // wait for and finish a single task: this should unblock repo=2 to run
	sink.WaitUntilN(1) // wait for the repo=2 task to get picked up: it'll get finished immediately

	require.Equal(t, 0, len(ordering.buffer))
	require.Equal(t, 2, len(buf.doneTasks))
	require.Equal(t, 2, len(buf.inTasks))

	// now it's ok to run another task
	op.Run(newTaskWithAncestors(t, 3, []uint32{1}))
	sink.WaitUntilN(2)

	require.Equal(t, 0, len(ordering.buffer))
	require.Equal(t, 3, len(buf.doneTasks))
	require.Equal(t, 3, len(buf.inTasks))
}

func newTaskWithAncestors(t *testing.T, repo uint32, ancestors []uint32) *Task {
	return newTaskWithRepo(t, repo, ancestors, hydro_schemas_github_search_v0.RepositoryChanged_ADMIN_PUSHED, routing.IncrementalSourceTopic, 1, 1)
}
