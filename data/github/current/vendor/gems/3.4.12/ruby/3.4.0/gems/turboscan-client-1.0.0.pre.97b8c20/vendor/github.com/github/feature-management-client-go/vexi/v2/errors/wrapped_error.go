package errors

import "fmt"

// WrappedError is an error that wraps another error to provider more context. Only wrap errors if you deem that the inner error alone will not make sense when seen in isolation in logs. Unnecessary wrapping will lead to bloat. Take for example a case where 2 same operations are performed in a single workflow and the error message that might be received from those along will not have enough context to tell which instance of the operation caused the error. Another case for wrapping errors would be where the underlying error never has enough context like potentially a deadline exceeded error which will just say "context cancelled deadline exceeded" and will need some wrapping to indicate what operation actually timed out.
type WrappedError struct {
	InnerError error
	Message    string
}

// NewWrappedError creates a new WrappedError.
func NewWrappedError(innerError error, msg string) *WrappedError {
	return &WrappedError{
		InnerError: innerError,
		Message:    msg,
	}
}

// Error returns the error message.
func (e WrappedError) Error() string {
	if e.InnerError == nil {
		return e.Message
	}
	return fmt.Errorf("%s: %w", e.Message, e.InnerError).Error()
}

// Unwrap returns the inner error.
func (e WrappedError) Unwrap() error {
	return e.InnerError
}

// Is returns true if the given error is a WrappedError.
func (e WrappedError) Is(err error) bool {
	_, ok := err.(*WrappedError)
	return ok
}
