package deltaingest

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_AncestorCheckOp(t *testing.T) {
	logOp := NewTestLogOp()
	filter := NewAncestorCheckOp(logOp)

	parentTask := newTaskWithRepoID(t, uint32(helpers.RepoID(t)))
	childTask := newTaskWithRepoID(t, uint32(helpers.RepoID(t)))
	childTask.event.BlackbirdAncestorRepoIds = []uint32{uint32(parentTask.repoID())}
	task := newTaskWithRepoID(t, uint32(helpers.RepoID(t)))
	filter.Run(parentTask)
	filter.Run(childTask)
	filter.Run(task)

	require.Len(t, logOp.log, 3)
	require.Equal(t, logOp.log[0], parentTask)
	require.Equal(t, logOp.log[1], childTask)
	require.Equal(t, logOp.log[2], task)
}

func Test_AncestorCheckOpSkips(t *testing.T) {
	logOp := NewTestLogOp()
	filter := NewAncestorCheckOp(logOp)

	task := newTaskWithRepoID(t, uint32(helpers.RepoID(t)))
	task.event.BlackbirdAncestorRepoIds = []uint32{uint32(task.repoID())}
	filter.Run(task)

	require.Len(t, logOp.log, 0)
}
