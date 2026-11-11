package errors

// ValidationError is an error that is returned when a validation fails.
type ValidationError struct {
	Message string
}

// NewValidationError creates a new ValidationError.
func NewValidationError(message string) *ValidationError {
	return &ValidationError{
		Message: message,
	}
}

// Error returns the error message.
func (e ValidationError) Error() string {
	return e.Message
}

// Is returns true if the target error is an ValidationError.
func (e ValidationError) Is(target error) bool {
	_, ok := target.(*ValidationError) //nolint:errorlint // Members don't need to be not being checked.
	return ok
}
