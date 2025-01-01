package build

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestWorkflowState_IsFinal(t *testing.T) {
	assert.False(t, WorkflowStateNone.IsFinal())
	assert.False(t, WorkflowStateQueued.IsFinal())
	assert.True(t, WorkflowStateSucceeded.IsFinal())
	assert.True(t, WorkflowStateFailed.IsFinal())
	assert.True(t, WorkflowStateCanceled.IsFinal())
	assert.True(t, WorkflowStateSkipped.IsFinal())
}
