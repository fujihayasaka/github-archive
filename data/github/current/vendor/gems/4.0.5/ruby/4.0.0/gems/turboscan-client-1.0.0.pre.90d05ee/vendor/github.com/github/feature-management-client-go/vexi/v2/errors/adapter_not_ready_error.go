// Package errors provides common error types used throughout the vexi package.
package errors

import "errors"

// ErrAdapterNotReady is returned when the adapter is not ready to serve requests.
var ErrAdapterNotReady = errors.New("adapter not ready")
