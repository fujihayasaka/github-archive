package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewRandomWorkflowExecutionID(t *testing.T) {
	executionID := NewRandomWorkflowExecutionID()
	assert.NotEqual(t, NilWorkflowExecutionID, executionID)
}
