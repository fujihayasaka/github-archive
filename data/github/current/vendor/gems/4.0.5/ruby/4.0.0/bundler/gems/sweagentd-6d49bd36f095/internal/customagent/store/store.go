package store

import (
	"errors"

	"github.com/github/sweagentd/internal/goerrors"
)

// ErrAgentNotFound is returned when the requested agent record does not exist.
var ErrAgentNotFound = errors.New("agent record not found")

// ErrPreconditionFailed is returned when an update fails due to a stale ETag
// (optimistic concurrency conflict).
var ErrPreconditionFailed = errors.New("precondition failed: stale version")

// NewErrAgentNotFound returns ErrAgentNotFound with a stack trace.
func NewErrAgentNotFound() error {
	return goerrors.WithStackOffset(ErrAgentNotFound, 1)
}

// NewErrPreconditionFailed returns ErrPreconditionFailed with a stack trace.
func NewErrPreconditionFailed() error {
	return goerrors.WithStackOffset(ErrPreconditionFailed, 1)
}
