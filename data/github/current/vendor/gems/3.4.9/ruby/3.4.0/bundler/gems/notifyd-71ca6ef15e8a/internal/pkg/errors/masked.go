package errors

import (
	"errors"
	"fmt"
)

// masked is an implementation of the error interface that hides context so that
// we can present users with a message relevant for them.
type masked struct {
	err error
	msg string
}

// Error returns a message that is relevant for the user.
func (m *masked) Error() string {
	return m.msg
}

// Mask returns an error that is mean to be human readable and user oriented.
// This means we use Mask when we want to wrap an error but hide its causes to
// whoever will consume it.
//
// This is tipically used to build errors that are returned by APIs or shown to
// users.
//
// As oposed to Wrap that adds more context to an error, Mask is meant to be
// used in order to hide all the context possible.
//
// Masking a masked error always discards the previous context and leaves only
// the latest mask applied.
func Mask(err error, msg string) error {
	if err == nil {
		return nil
	}

	return &masked{err, msg}
}

// Maskf works in the same way as Mask but it supports the same formatting
// specifiers as the fmt package https://pkg.go.dev/fmt#hdr-Printing
func Maskf(err error, format string, a ...interface{}) error {
	return Mask(err, fmt.Sprintf(format, a...))
}

// Unmask takes a masked error and returns its cause. We use this so that we can
// report detailed errors with all their context even if they are masked.
//
// Unmasking an error that has been masked more than once always return the
// innermost unmasked error.
func Unmask(err error) error {
	if err == nil {
		return nil
	}

	var maskedErr *masked
	if errors.As(err, &maskedErr) {
		return Unmask(maskedErr.err)
	}

	return err
}
