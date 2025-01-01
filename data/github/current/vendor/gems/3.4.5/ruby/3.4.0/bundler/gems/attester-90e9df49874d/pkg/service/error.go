package service

// BadRequestError represents an error caused by an invalid client request. This
// can be used to represent requests that include invalid body content.
type BadRequestError struct {
	wrappedErr error
}

func (e *BadRequestError) Error() string {
	return e.wrappedErr.Error()
}

func (e *BadRequestError) Unwrap() error {
	return e.wrappedErr
}

func NewBadRequestError(err error) *BadRequestError {
	return &BadRequestError{
		wrappedErr: err,
	}
}
