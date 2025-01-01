package wfparser

import (
	"math"
)

// WorkflowParseError is an error that occurs when parsing a workflow file.
type WorkflowParseError struct {
	Errors []error
}

func NewWorkflowParseError(errors []error) error {
	return &WorkflowParseError{Errors: errors}
}

// Report first 2 error messages, due to space limit on printing this error message in UI
func (e WorkflowParseError) Error() string {
	errMsg := "The workflow is not valid."

	errs := e.Errors[:int(math.Min(2, float64(len(e.Errors))))]
	for _, err := range errs {
		errMsg += " " + err.Error()
	}

	return errMsg
}

type Positioner interface {
	Position() (string, int, int)
}

// Position returns the line and column the error occured on. -1 for both values if
// the position cannot be parsed.
func (e *WorkflowParseError) Position() (int, int) {
	if len(e.Errors) == 0 {
		return -1, -1
	}

	firstErr := e.Errors[0]
	if p, ok := firstErr.(Positioner); ok {
		_, line, col := p.Position()
		return line, col
	}
	return -1, -1
}
