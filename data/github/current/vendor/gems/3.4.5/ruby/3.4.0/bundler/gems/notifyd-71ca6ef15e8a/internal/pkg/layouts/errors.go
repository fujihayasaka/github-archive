// Package layouts implements error handling when unmarshalling layouts.
package layouts

import "fmt"

// UnmarshallingError wraps the errors that can happen when we unmarshall a layout.
type UnmarshallingError struct {
	cause   error
	typeURL string
}

// NewUnmarshallingError builds an UnmarshallingError that treats `err` as its cause for a layout
// identified by typeURL
func NewUnmarshallingError(err error, typeURL string) UnmarshallingError {
	return UnmarshallingError{
		cause:   err,
		typeURL: typeURL,
	}
}

// Error implements the `error` interface for UnmarshallingError
func (err UnmarshallingError) Error() string {
	base := fmt.Sprintf("layout %s: unmarshalling", err.typeURL)
	if err.cause != nil {
		return fmt.Sprintf("%s: %s", base, err.cause)
	}
	return base
}

// Unwrap makes it possible to use errors.Unwrap with UmarshallingError.
func (err UnmarshallingError) Unwrap() error {
	if err.cause != nil {
		return err.cause
	}
	return err
}

// TypeError happens when we couldn't find the type of a layout.
type TypeError struct {
	typeURL string
}

// NewTypeError returns an error for the given typeURL
func NewTypeError(typeURL string) TypeError {
	return TypeError{
		typeURL: typeURL,
	}
}

func (err TypeError) Error() string {
	return fmt.Sprintf("layout: %s unrecognized", err.typeURL)
}
