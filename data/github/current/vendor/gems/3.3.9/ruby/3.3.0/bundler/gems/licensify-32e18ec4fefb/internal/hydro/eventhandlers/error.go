package eventhandlers

import (
	"fmt"

	"github.com/github/go-stats"
	"github.com/github/licensify/internal/cosmos"
	"go.opentelemetry.io/otel/trace"
)

// Error is a struct that contains an error returned by an event handler.
type Error struct {
	span   trace.Span
	origin string
	Err    error
}

// IsEmpty returns true if the Error struct is empty.
func (e *Error) IsEmpty() bool {
	return e.span == nil && e.origin == "" && e.Err == nil
}

// Origin returns the origin of the error.
func (e *Error) Origin() string {
	var origin string
	if e.origin == "" {
		origin = "unknown"
	} else {
		origin = fmt.Sprintf("%s-error", e.origin)
	}

	if cosmos.IsPreconditionFailedError(e.Err) {
		origin = fmt.Sprintf("%s-precondition-failed", origin)
	}

	return origin
}

// Tags returns the tags for the error.
func (e *Error) Tags() stats.Tags {
	return stats.Tags{"success": "false", "skip": "false", "origin": e.Origin()}
}
