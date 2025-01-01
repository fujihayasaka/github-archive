package deltaingest

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_TaskOperationInterface(t *testing.T) {
	require.PanicsWithValue(t, "empty operation stack", func() {
		op := &DoubleDoneOp{}
		op.Run(newTaskWithRepoID(t, 1))
	})
}

// An operation that calls done twice (which is an error)
type DoubleDoneOp struct{}

func (o *DoubleDoneOp) Run(task *Task) {
	task.Begin(o)

	task.Done(nil)
	task.Done(nil)
}
func (o *DoubleDoneOp) OnDone(task *Task, err error) {}
