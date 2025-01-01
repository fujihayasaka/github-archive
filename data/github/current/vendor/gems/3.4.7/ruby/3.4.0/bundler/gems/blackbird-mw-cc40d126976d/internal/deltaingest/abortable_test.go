package deltaingest

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func Test_CanAbort(t *testing.T) {
	sink := NewTestLogOp()
	ctx, cancel := context.WithCancel(context.Background())
	op := NewAbortableOp(cancel, 1, sink)

	op.Run(newTaskWithRepoID(t, 1))
	require.Equal(t, 1, len(sink.log))

	testErr := errors.New("test")
	op.Abort(testErr)
	err := op.Wait()
	require.Equal(t, err, testErr)
	require.Equal(t, ctx.Err(), context.Canceled)
}

func Test_TasksAfterAbortAreIgnored(t *testing.T) {
	sink := NewTestLogOp()
	ctx, cancel := context.WithCancel(context.Background())
	op := NewAbortableOp(cancel, 1, sink)

	op.Run(newTaskWithRepoID(t, 1))
	require.Equal(t, 1, len(sink.log))

	testErr := errors.New("test")
	op.Abort(testErr)
	err := op.Wait()
	require.Equal(t, err, testErr)
	require.Equal(t, ctx.Err(), context.Canceled)

	// This is a noop now
	op.Run(newTaskWithRepoID(t, 1))
	require.Equal(t, 1, len(sink.log))
}

func Test_AbortWithNoTasks(t *testing.T) {
	sink := NewTestLogOp()
	ctx, cancel := context.WithCancel(context.Background())
	op := NewAbortableOp(cancel, 1, sink)

	testErr := errors.New("test")
	go func() {
		time.Sleep(10 * time.Millisecond)
		op.Abort(testErr)
	}()

	err := op.Wait()
	require.Equal(t, err, testErr)
	require.Equal(t, ctx.Err(), context.Canceled)
}

func Test_TaskCanAbort(t *testing.T) {
	sink := NewTestCollectOp()
	ctx, cancel := context.WithCancel(context.Background())
	op := NewAbortableOp(cancel, 1, sink)

	op.Run(newTaskWithRepoID(t, 1))
	require.Equal(t, 1, len(sink.tasks))

	testErr := errors.New("test")
	sink.FinishLastOne(testErr)

	err := op.Wait()
	require.Equal(t, err, testErr)
	require.Equal(t, ctx.Err(), context.Canceled)
}

func Test_PanicIfAbortedWithNilError(t *testing.T) {
	sink := NewTestCollectOp()
	_, cancel := context.WithCancel(context.Background())
	op := NewAbortableOp(cancel, 2, sink)
	op.Run(newTaskWithRepoID(t, 1))
	require.Equal(t, 1, len(sink.tasks))

	require.PanicsWithValue(t, "must provide an error to abort", func() {
		op.Run(newTaskWithRepoID(t, 2))
		op.Abort(nil)
	})
}

func Test_AbortExternalWithWorkPool(t *testing.T) {
	sink := NewTestLogOp()
	ctx, cancel := context.WithCancel(context.Background())
	wp := NewWorkPoolOp(ctx, 1, 1, sink)
	defer wp.Close()
	op := NewAbortableOp(cancel, 1, wp)

	op.Run(newTaskWithRepoID(t, 1))
	testErr := errors.New("test")
	op.Abort(testErr)
	err := op.Wait()
	require.Equal(t, err, testErr)
	require.Equal(t, ctx.Err(), context.Canceled)
}

func Test_AbortViaTaskWithWorkPool(t *testing.T) {
	sink := NewTestCollectOp()
	ctx, cancel := context.WithCancel(context.Background())
	wp := NewWorkPoolOp(ctx, 1, 1, sink)
	defer wp.Close()
	op := NewAbortableOp(cancel, 1, wp)

	op.Run(newTaskWithRepoID(t, 1))
	testErr := errors.New("test")
	sink.FinishLastOne(testErr)
	err := op.Wait()
	require.Equal(t, err, testErr)
	require.Equal(t, ctx.Err(), context.Canceled)
}
