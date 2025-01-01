package deltaingest

import (
	"errors"
	"fmt"

	entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/types"
)

var errTooManyBlobLocations = errors.New("repository has too many blob/path locations")

// permanentError represents a permanent error that occurred after crawling
// began. Permanent errors are recorded in the index. Future ingest events for
// the repository will be skipped.
//
// NOTE: permanentError does not contain an NWO because IndexResponse does not
// contain one.
type permanentError struct {
	err         error
	errorType   entities.PermanentErrorType
	repoID      types.RepoID
	commitSeqNo uint64
	repoSeqNo   types.RepoSeqNo
}

func (e *permanentError) Error() string {
	return e.err.Error()
}

// Full version of the error that's sent to the indexer in `SnapshotEntry.permanent_error`.
func (e *permanentError) Description() string {
	return fmt.Sprintf("%s: %v", e.legacyReason(), e.err)
}

func (e *permanentError) Unwrap() error {
	return e.err
}

func (e *permanentError) Is(target error) bool {
	_, ok := target.(*permanentError)
	return ok
}

// legacyReason converts PermanentErrorType into the old category string that
// was used previously. This can be removed after a full round of backfills has
// switched us to the new enum values.
//
// These values match the old IngestFailureCategory.String() with the addition
// of new strings for the new error types. IngestFailureCategoryUnableToDiff is
// not mapped because it was unused and wasn't ported.
func (e *permanentError) legacyReason() string {
	switch e.errorType {
	case entities.PermanentErrorType_ERROR_UNKNOWN:
		return "unknown"
	case entities.PermanentErrorType_SYSTEM_LIMIT:
		return "system-limit"
	case entities.PermanentErrorType_RETRIES_EXHAUSTED:
		return "retries-exhausted"
	case entities.PermanentErrorType_INVALID_DEFAULT_REF:
		return "invalid-default-ref"
	case entities.PermanentErrorType_BAD_COMMIT:
		return "bad-commit"
	case entities.PermanentErrorType_LEGACY_ERROR:
		return "legacy"
	case entities.PermanentErrorType_FETCHING_METADATA_FAILED:
		return "fetching-metadata-failed"
	default:
		panic(fmt.Sprintf("unexpected error type: %d", e.errorType))
	}
}

// newPermanentError creates an error with a categorized failure associated with
// a specific repository ID and sequence number. It is used to mark a repository
// permanently failed after crawling has begun. This type of error is not
// retried.
func newPermanentError(err error, errorType entities.PermanentErrorType, repoID types.RepoID, commitSeqNo uint64, repoSeqNo types.RepoSeqNo) error {
	if err == nil {
		return nil
	}

	return &permanentError{err, errorType, repoID, commitSeqNo, repoSeqNo}
}

// newTransientError creates an error associated with a valid NWO. It is used to
// associate metadata with a non-permanent error. These errors are retried; if
// the ingest ultimately fails by running out of retries, the NWO is recorded in
// the index.
func newTransientError(err error, nwoStr string) error {
	var nwo types.NWO
	if valid, err := types.NewNWO(nwoStr); err == nil {
		nwo = valid
	}
	return &transientError{err, nwo}
}

// transientError represents an error associated with an NWO, but no other
// information. This is used for errors that occur before crawling could begin
// or transitory/unexpected errors that should be retried.
type transientError struct {
	err error
	nwo types.NWO
}

func (e *transientError) Error() string {
	return e.err.Error()
}

func (e *transientError) Unwrap() error {
	return e.err
}

func (e *transientError) Is(target error) bool {
	_, ok := target.(*transientError)
	return ok
}

// nwoFromErr extracts an NWO from the error if possible. If not, it returns an
// zero-value NWO.
func nwoFromErr(err error) types.NWO {
	var pcErr *transientError
	if errors.As(err, &pcErr) {
		return pcErr.nwo
	}

	return types.NWO{}
}
