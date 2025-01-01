// Package validations implements a composable way to build complex validations.
package validations

import (
	"errors"

	"github.com/hashicorp/go-multierror"
)

type validator func() error

/*
Validation is a composable way to build complex validations that are lazily executed when needed.

It works by using a pattern known as functional options to compose a list of functions that need to
return no error in order to consider a validation as valid.

When errors exist, they are all returned together on a multierror.

An empty validation is invalid by definition and always returns ErrIsEmpty
*/
type Validation struct {
	validators []validator
}

// New creates a new validation.
func New() *Validation {
	return &Validation{}
}

// Add will append a validator function to the given validation.
func (v *Validation) Add(fn validator) {
	v.validators = append(v.validators, fn)
}

// IsValid return true when all the validators return no error, false as soon as one of them returns
// an error.
func (v *Validation) IsValid() bool {
	if err := v.isEmpty(); err != nil {
		return false
	}

	for _, fn := range v.validators {
		if err := fn(); err != nil {
			return false
		}
	}

	return true
}

// ToError aggregates all the errors returned by validators in this validation.
func (v *Validation) ToError() error {
	var allErr error
	if err := v.isEmpty(); err != nil {
		return err
	}

	for _, fn := range v.validators {
		if err := fn(); err != nil {
			allErr = multierror.Append(allErr, err)
		}
	}

	return allErr
}

// ErrIsEmpty is an error returned when a validation is empty.
var ErrIsEmpty = errors.New("the validation is empty")

func (v *Validation) isEmpty() error {
	if len(v.validators) == 0 {
		return ErrIsEmpty
	}

	return nil
}
