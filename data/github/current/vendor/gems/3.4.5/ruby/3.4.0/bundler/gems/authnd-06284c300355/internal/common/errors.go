package common

import (
	"github.com/pkg/errors"
)

// StoreErrUnsupported is returned when a store does not support a method
var StoreErrUnsupported error = errors.New("unsupported")

// StoreErrUnexpectedMultipleResults is returned when more than one result is returned for a query that expects a single result
var StoreErrUnexpectedMultipleResults error = errors.New("ambiguous")

// StoreErrDeviceKeyUnexpectedExpired is returned when
var StoreErrDeviceKeyUnexpectedExpired error = errors.New("expired")

// StoreErrDeviceKeyUnexpectedRevoked is returned when
var StoreErrDeviceKeyUnexpectedRevoked error = errors.New("revoked")

// NewErrorIsOneOf returns a new function which returns true if the observed error
// is any of the provided errors.
func NewErrorIsOneOf(errs ...error) func(error) bool {
	return func(err error) bool {
		for _, e := range errs {
			if errors.Is(err, e) {
				return true
			}
		}
		return false
	}
}
