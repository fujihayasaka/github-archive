package spokesd

import (
	"context"
	"fmt"

	"github.com/pkg/errors"
)

type ErrCode int

const (
	ErrUnknown ErrCode = iota
	// The commit is invalid to crawl. It could not be resolved to a git tree.
	// Retrying is unlikely to help.
	ErrInvalidCommit
	// The ref is invalid to crawl. Retrying is unlikely to help.
	ErrInvalidRef
	// An error due to a missing or corrupt diff base. This can happen with force
	// pushes (the base commit no longer exists). These errors can be retried, but
	// the ingest code MUST select a different base of the diff.
	ErrInvalidDiffBase
	// An error with the underlying Git system. For example, the repository is
	// too big to diff or list trees for. Retrying is unlikely to help.
	ErrGitSystem
	// ErrRepoDeleted means the repository was not present on disk while
	// servicing a request.
	ErrRepoDeleted
	// ErrLocationLimitExceeded means while retrieving the repository's indexable
	// locations, the repository's max location limit was exceeded.
	ErrLocationLimitExceeded
	// ErrGitmonTooManyProcesses means the request was rejected because the
	// number of git processes exceeds Gitmon's limits. This causes a "fail
	// fast" error even when using the "delayable" Quality of Service level.
	ErrGitmonTooManyProcesses
)

var LocationLimitExceededError = &Error{Message: "location limit exceeded", Code: ErrLocationLimitExceeded}

// A wrapper around specific spokesd errors that we want to categorize and
// potentially retry (or not).
type Error struct {
	Message string
	Err     error
	Code    ErrCode
}

func (e *Error) Unwrap() error {
	return e.Err
}

func (e *Error) Is(target error) bool {
	_, ok := target.(*Error)
	return ok
}

func (e *Error) Error() string {
	if e.Err != nil {
		return fmt.Sprintf("%s: %s", e.Message, e.Err.Error())
	}

	return e.Message
}

func InvalidCommit(message string, args ...interface{}) *Error {
	return &Error{Message: fmt.Sprintf(message, args...), Code: ErrInvalidCommit}
}

func WrapInvalidCommit(err error, message string, args ...interface{}) *Error {
	return wrapErr(err, ErrInvalidCommit, message, args...)
}

func IsInvalidCommitError(err error) bool {
	return isErrCode(err, ErrInvalidCommit)
}

func WrapInvalidRefError(err error, message string, args ...interface{}) *Error {
	return wrapErr(err, ErrInvalidRef, message, args...)
}

func IsInvalidRefError(err error) bool {
	return isErrCode(err, ErrInvalidRef)
}

// Wraps an error with an invalid diff base error (ingest *can* retry, but should pick a new diff base).
func WrapInvalidDiffBaseError(err error, message string, args ...interface{}) *Error {
	return wrapErr(err, ErrInvalidDiffBase, message, args...)
}

// IsInvalidDiffBaseError returns true if this is an error that can be retried only if a different diff base is selected.
func IsInvalidDiffBaseError(err error) bool {
	return isErrCode(err, ErrInvalidDiffBase)
}

// Wraps an error with a Git system error. Retrying is unlikely to work.
func WrapGitSystemError(err error, message string, args ...interface{}) *Error {
	return wrapErr(err, ErrGitSystem, message, args...)
}

// IsGitSystemError returns true if this is an error with the underlying Git
// system that should not be retried.
func IsGitSystemError(err error) bool {
	return isErrCode(err, ErrGitSystem)
}

// Wraps an error with a Git system error. Retrying is unlikely to work.
func WrapRepoDeletedError(err error, message string, args ...interface{}) *Error {
	return wrapErr(err, ErrRepoDeleted, message, args...)
}

// IsRepoDeletedError returns true if this is an error with the underlying Git
// system that should not be retried.
func IsRepoDeletedError(err error) bool {
	return isErrCode(err, ErrRepoDeleted)
}

// IsLocationLimitExceededError returns true if this is an error with the underlying Git
// system that should not be retried.
func IsLocationLimitExceededError(err error) bool {
	return isErrCode(err, ErrLocationLimitExceeded)
}

// Wraps an error with a Gitmon too-many-processes error. We should retry later.
func WrapGitmonTooManyProcessesError(err error, message string, args ...interface{}) *Error {
	return wrapErr(err, ErrGitmonTooManyProcesses, message, args...)
}

// IsGitmonTooManyProcesses returns true if this is an error that occurred
// because the host is running more git processes than Gitmon allows.
func IsGitmonTooManyProcessesError(err error) bool {
	return isErrCode(err, ErrGitmonTooManyProcesses)
}

func wrapErr(err error, code ErrCode, message string, args ...interface{}) *Error {
	return &Error{Message: fmt.Sprintf(message, args...), Err: err, Code: code}
}

func isErrCode(err error, code ErrCode) bool {
	var e *Error
	return errors.As(err, &e) && e.Code == code && !errors.Is(err, context.Canceled)
}
