package deltaingest

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
)

var errTestTask = errors.New("test task error")

func Test_WorkPool(t *testing.T) {
	ctx := context.Background()
	echo := NewTestLogOp()
	op := NewWorkPoolOp(ctx, 1, 1, echo)

	op.Run(newTaskWithRepoID(t, 1))
	op.Close()

	// one task was processed
	require.Equal(t, 1, len(echo.log))
}

func Test_WorkPoolFailedTask(t *testing.T) {
	ctx := context.Background()
	sink := NewTestCollectOp()
	op := NewWorkPoolOp(ctx, 1, 1, sink)
	buf := NewBufferOp(op)

	buf.Run(newTaskWithRepoID(t, 1))

	// finish that task with an error
	sink.FinishLastOne(errTestTask)

	op.Close()
	require.Equal(t, 1, len(buf.doneTasks))
	require.Equal(t, errTestTask, buf.doneTasks[0].err)
}

func Test_WorkPoolSuccessfulTask(t *testing.T) {
	ctx := context.Background()
	sink := NewTestCollectOp()
	op := NewWorkPoolOp(ctx, 1, 1, sink)
	buf := NewBufferOp(op)

	buf.Run(newTaskWithRepoID(t, 1))

	// finish the task
	sink.FinishLastOne(nil)

	op.Close()
	require.Equal(t, 1, len(buf.doneTasks))
	require.Nil(t, buf.doneTasks[0].err)
}

func Test_WorkPoolManyTasks(t *testing.T) {
	ctx := context.Background()
	echo := NewTestLogOp()
	op := NewWorkPoolOp(ctx, 2, 2, echo)

	for i := 0; i < 100; i++ {
		op.Run(newTaskWithRepoID(t, 1))
	}
	op.Close()

	// all tasks were processed
	require.Equal(t, 100, len(echo.log))
}
