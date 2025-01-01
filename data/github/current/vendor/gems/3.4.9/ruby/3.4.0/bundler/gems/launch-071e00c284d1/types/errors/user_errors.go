package errors

import (
	"fmt"
)

// UserError represents a fatal error caused by a user decision, e.g. a malformed Workflow file // or a non-existent secret
type UserError struct {
	s string
}

func (e UserError) Error() string {
	return e.s
}

func (e *UserError) IsUserError() bool {
	return true
}

// NewUserError returns a new UserError
func NewUserError(message string) *UserError {
	return &UserError{message}
}

// NewUserErrorf returns a new UserError
func NewUserErrorf(format string, args ...any) *UserError {
	return &UserError{fmt.Sprintf(format, args...)}
}
