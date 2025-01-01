package build

import (
	"fmt"
)

// WorkflowState captures the state of a workflow execution.  These states are
// a progression: the build starts out as None, then proceeds to Started.
// From there, the value can increase (move down the list) but never
// decrease.  That is, it's possible to go from Succeeded to Cancelled but
// not the reverse.
// Do not reorder these constants.
type WorkflowState int

// If you modify these constants, ensure the methods on WorkflowState are still valid
const (
	// WorkflowStateNone means the workflow hasn't been queued.
	WorkflowStateNone WorkflowState = iota
	// WorkflowStateQueued means the workflow has been accepted and will start, but has not started yet
	WorkflowStateQueued
	// WorkflowStateStarted means workflow execution has begun
	WorkflowStateStarted
	// WorkflowStateSucceeded means the workflow completed successfully
	WorkflowStateSucceeded
	// WorkflowStateFailed means the workflow completed with an error
	WorkflowStateFailed
	// WorkflowStateCanceled means the workflow was canceled
	WorkflowStateCanceled
	// WorkflowStateSkipped means the workflow was skipped
	WorkflowStateSkipped
	// WorkflowStateTimedOut means we timed out the workflow, probably via cron after 72-720 hours, depending on gates
	WorkflowStateTimedOut
	// WorkflowStateNeverStarted means the workflow was never queued for some reason
	WorkflowStateNeverStarted
)

var workflowStateStrings = map[WorkflowState]string{
	WorkflowStateNone:         "None",
	WorkflowStateQueued:       "Queued",
	WorkflowStateStarted:      "Started",
	WorkflowStateSucceeded:    "Succeeded",
	WorkflowStateFailed:       "Failed",
	WorkflowStateCanceled:     "Canceled",
	WorkflowStateSkipped:      "Skipped",
	WorkflowStateTimedOut:     "TimedOut",
	WorkflowStateNeverStarted: "NeverStarted",
}

func (st WorkflowState) String() string {
	if ret, ok := workflowStateStrings[st]; ok {
		return ret
	}
	return fmt.Sprintf("unknown#%d", st)
}

// IsFinal returns true if the build is in a state that will not change
func (st WorkflowState) IsFinal() bool {
	return st >= WorkflowStateSucceeded
}
