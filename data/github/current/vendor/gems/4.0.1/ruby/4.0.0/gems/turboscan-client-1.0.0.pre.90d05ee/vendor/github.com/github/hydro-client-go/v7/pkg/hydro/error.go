package hydro

import (
	"context"
	"fmt"
	"strings"
)

// Errors is the interface that extends the standard error interface by adding
// an Errors method that allows for returning multiple errors.
//
// Errors returns a slice of errors. It returns a nil slice when there are no
// errors.
type Errors interface {
	error
	Errors() []error
}

// ErrorList represents a slice of errors that enables returning multiple
// errors from a single function or method. It implements the error interface
// for use in conventional error handling. It also implements the Errors
// interface to allow access to the underlying errors.
type ErrorList []error

// Error returns the error string representation of the ErrorList by calling
// its String method.
func (el ErrorList) Error() string {
	return el.String()
}

// Errors returns a slice of errors.
func (el ErrorList) Errors() []error {
	return el
}

// String returns the string representation of the ErrorList. The returned
// string is formatted depending on the length of the backing slice. When
// len(el) == 0 it returns an empty string. When len(el) == 1 it returns the
// string from calling the Error method on the single error. When len(el) > 1
// it calls the Error method on each error and returns a string formatted as:
//
//	errors: ["err 1", "err 2", ...]
func (el ErrorList) String() string {
	switch len(el) {
	case 0:
		return ""
	case 1:
		return el[0].Error()
	default:
		var b strings.Builder
		for i, err := range el {
			if i != 0 {
				b.WriteString(", ")
			}
			fmt.Fprintf(&b, "%q", err.Error())
		}
		return fmt.Sprintf("errors: [%s]", b.String())
	}
}

func isCtxError(e error) bool {
	return e == context.Canceled || e == context.DeadlineExceeded
}
