package github

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/github/launch/types"
)

func TestWorkflowInvocationReference_IsZeroValue(t *testing.T) {
	ref := types.WorkflowInvocationReference{}
	assert.True(t, ref.IsZeroValue())
	ref2 := types.WorkflowInvocationReference{GitRef: types.GitRef("refs/HEAD")}
	assert.False(t, ref2.IsZeroValue())
	ref3 := types.WorkflowInvocationReference{CommitSHA: types.NullCommitSha}
	assert.False(t, ref3.IsZeroValue())
	ref4 := types.WorkflowInvocationReference{GitRef: types.GitRef("refs/HEAD"), CommitSHA: types.NullCommitSha}
	assert.False(t, ref4.IsZeroValue())
}
