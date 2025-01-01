package pagination

import (
	"fmt"
)

// LimitExceededError is an error that occurs when the requested page limit exceeds the upper limit.
type LimitExceededError struct {
	upperLimit     int64
	requestedLimit int64
}

func (e LimitExceededError) Error() string {
	return fmt.Sprintf("Requested page limit %d exceeds upper limit %d", e.requestedLimit, e.upperLimit)
}

// NewLimitExceededError creates a new LimitExceededError.
func NewLimitExceededError(upperLimit, requestedLimit int64) LimitExceededError {
	return LimitExceededError{
		upperLimit:     upperLimit,
		requestedLimit: requestedLimit,
	}
}
