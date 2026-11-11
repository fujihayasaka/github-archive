package document

import (
	"context"
	"fmt"
	"time"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	blackbird "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/messages"
	"github.com/github/blackbird-mw/internal/types"
)

var ErrAbusiveRepoContent = errors.New("abusive content: repository contains documents with too many locations")

// unindexable is a marker interface for errors. External packages should use
// `IsUnindexable` to check if a document should be skipped..
type unindexable interface {
	Unindexable() bool
	KVPs() []kvp.Field
}

type emptyBlobError struct {
	repoID types.RepoID
	oid    gitaccess.ObjectID
}

// Error meets the Go error interface.
//
// NOTE: It does not include PII in the error message to avoid sending it to
// third parties, use KVPs() to log this sensitive information.
func (e *emptyBlobError) Error() string {
	return fmt.Sprintf("repo %d blob %s is empty", e.repoID, e.oid)
}

// Unindexable makes this match the unindexable marker interface.
func (e *emptyBlobError) Unindexable() bool {
	return true
}

func (e *emptyBlobError) KVPs() []kvp.Field {
	return []kvp.Field{kvp.Int("repo_id", int(e.repoID)), kvp.String("oid", e.oid.String())}
}

// IsUnindexable returns true when the error indicates the content is
// unindexable. The only remaining reason is: empty blob content.
func IsUnindexable(err error) bool {
	var unidx unindexable
	return errors.As(err, &unidx)
}

// invalidDocumentError is returned when a change can not be converted to a
// document because it is invalid.
type invalidDocumentError struct {
	message string
}

func (i *invalidDocumentError) Error() string {
	return i.message
}

func newInvalidDocumentError(message string) error {
	return &invalidDocumentError{message: message}
}

// IsInvalidDocument returns true if this error was returned due to failing to
// convert a document.
func IsInvalidDocument(err error) bool {
	var ide *invalidDocumentError
	return errors.As(err, &ide)
}

// NewGitDocumentFromOID returns a GitDocument for an entry without content to
// be sent to the cache server for lookup.
//
// Callers should check if the returned error IsUnindexable and these documents
// should be skipped. If the document cannot be created, the error will return
// true for IsInvalidDocument. This is a permanent error for the crawl and the
// repository should not be retried.
func NewGitDocumentFromOID(ctx context.Context, msg *messages.Ingest, entry *gitaccess.BlobOIDChange) (*blackbird.GitDocument, error) {
	validateMessage(msg)

	// Blobs with empty content should be excluded here, to prevent the excessive
	// location ban due to empty files like .gitkeep or __init__.py files.
	if entry.ObjectID.IsEmptyBlob() {
		return nil, &emptyBlobError{repoID: msg.RepoID, oid: entry.ObjectID}
	}

	if err := hasValidLocations(ctx, entry, msg.EpochMode); err != nil {
		return nil, err
	}

	return newDocumentWithoutContent(ctx, msg, entry), nil
}

// NewGitDocumentFromContent returns a GitDocument for an entry with content.
//
// If the document cannot be created, the error will return true for
// IsInvalidDocument. This is a permanent error for the crawl and the repository
// should not be retried.
func NewGitDocumentFromContent(ctx context.Context, msg *messages.Ingest, blob *gitaccess.BlobContentChange) (*blackbird.GitDocument, error) {
	validateMessage(msg)

	if err := isValidBlob(ctx, blob, msg.EpochMode); err != nil {
		return nil, err
	}
	if allLocationsDeleted(blob) {
		return newDeletedDocument(ctx, msg, blob), nil
	}

	return newDocumentWithContent(ctx, msg, blob), nil
}

func validateMessage(msg *messages.Ingest) {
	if msg.IngestStartedAt.IsZero() {
		panic(fmt.Sprintf("a zero IngestStartedAt is invalid, use StartIngest set a valid time, repo_id=%d", msg.RepoID))
	}
}

func hasValidLocations(ctx context.Context, blob gitaccess.BlobChangeEntry, mode epoch.EpochMode) error {
	if len(blob.Locations()) == 0 {
		return newInvalidDocumentError("cannot create document with no locations")
	}

	if epoch.EpochFeaturesDedupingByContentAndPath.SupportedBy(mode) && len(blob.Locations()) > 1 {
		return newInvalidDocumentError("cannot create document with multiple locations in DedupeByContentAndPath mode")
	}

	statting.Distribution(ctx, "document.locations", float64(len(blob.Locations())))

	// We log any repos with documents that have locations per doc in excess of 1000 locations.
	const excessiveLocsThreshold = 1000
	if len(blob.Locations()) > excessiveLocsThreshold {
		logging.Info(ctx, "repo with excessive locations per doc", kvp.Int("num_locations", len(blob.Locations())), kvp.Int("excessive_threshold", excessiveLocsThreshold))
	}

	for _, loc := range blob.Locations() {
		if len(loc.Path) == 0 {
			return newInvalidDocumentError("invalid location: no path")
		}
		statting.Distribution(ctx, "document.path.length", float64(len(loc.Path)))
	}

	return nil
}

func isValidBlob(ctx context.Context, blob *gitaccess.BlobContentChange, mode epoch.EpochMode) error {
	if err := hasValidLocations(ctx, blob, mode); err != nil {
		return err
	}

	if len(blob.Content) > gitaccess.MaxBlobSize {
		return newInvalidDocumentError(fmt.Sprintf("cannot create document bigger than %d bytes (got %d)", gitaccess.MaxBlobSize, len(blob.Content)))
	}

	// NOTE: This previously was skipped if all locations were deleted, but
	// since delta indexing we fetch deleted content, so it should apply in all
	// cases.
	if len(blob.Content) < gitaccess.MinBlobSize {
		return newInvalidDocumentError(fmt.Sprintf("cannot create document less than %d bytes (got %d)", gitaccess.MinBlobSize, len(blob.Content)))
	}

	return nil
}

// Return a new document with content from Git.
func newDocumentWithContent(ctx context.Context, msg *messages.Ingest, blob *gitaccess.BlobContentChange) *blackbird.GitDocument {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "document.change.to_document.duration", time.Since(start))
	}()

	locations := convertLocationsUsingContent(ctx, blob, msg.RepoID, msg.EntryID)

	var leaseExpiresAt int64
	if msg.Lease != nil {
		leaseExpiresAt = msg.Lease.ExpiresAt()
	}

	// LanguageId and Symbols are computed on the cache server.
	doc := &blackbird.GitDocument{
		RepoId:              int64(msg.RepoID),
		ContentSha:          blob.ObjectID.Bytes(),
		MaxRepoScore:        msg.MaxRepoScore,
		Content:             blob.Content,
		Locations:           locations,
		AllLocationsDeleted: false,
		TreeUpdateBarrier:   msg.SnapshotBarrier,
		LeaseExpiresAt:      leaseExpiresAt,
		Experiments:         msg.EntryExperiments,
	}

	return doc
}

func newDeletedDocument(ctx context.Context, msg *messages.Ingest, blob *gitaccess.BlobContentChange) *blackbird.GitDocument {
	locations := convertLocationsUsingContent(ctx, blob, msg.RepoID, msg.EntryID)

	doc := &blackbird.GitDocument{
		RepoId:              int64(msg.RepoID),
		ContentSha:          blob.ObjectID.Bytes(),
		MaxRepoScore:        msg.MaxRepoScore,
		Content:             blob.Content, // NOTE: Necessary to send content for deletes so cache server knows to publish it as-is.
		Locations:           locations,
		AllLocationsDeleted: true,
		TreeUpdateBarrier:   msg.SnapshotBarrier,
		LeaseExpiresAt:      msg.Lease.ExpiresAt(),
		Experiments:         msg.EntryExperiments,
	}

	return doc
}

func newDocumentWithoutContent(ctx context.Context, msg *messages.Ingest, entry *gitaccess.BlobOIDChange) *blackbird.GitDocument {
	locations := make([]*entities.Location, 0, len(entry.Locations()))
	for _, loc := range entry.Locations() {
		change := entities.Location_CHANGE_ADDED
		if loc.Change == gitaccess.Delete {
			change = entities.Location_CHANGE_DELETED
		}
		locations = append(locations, &entities.Location{
			Path:    loc.Path,
			Change:  change,
			EntryId: msg.EntryID,
		})
	}

	doc := &blackbird.GitDocument{
		RepoId:              int64(msg.RepoID),
		ContentSha:          entry.OID().Bytes(),
		MaxRepoScore:        msg.MaxRepoScore,
		Content:             []byte{}, // NOTE: For a cache lookup, content is always blank. FIXME: if we allow indexing blank documents!
		Locations:           locations,
		AllLocationsDeleted: allLocationsDeleted(entry),
		TreeUpdateBarrier:   msg.SnapshotBarrier,
		LeaseExpiresAt:      msg.Lease.ExpiresAt(),
		Experiments:         msg.EntryExperiments,
	}

	return doc
}

// allLocationsDeleted returns true if all Locations are deletes.
func allLocationsDeleted(b gitaccess.BlobChangeEntry) bool {
	allDeleted := true
	for _, l := range b.Locations() {
		if l.Change != gitaccess.Delete {
			allDeleted = false
			break
		}
	}
	return allDeleted
}

func convertLocationsUsingContent(ctx context.Context, blob *gitaccess.BlobContentChange, repoID types.RepoID, entryID uint64) []*entities.Location {
	addedLocs := 0
	deletedLocs := 0
	locations := make([]*entities.Location, 0, len(blob.Locations()))
	for _, loc := range blob.Locations() {
		change := entities.Location_CHANGE_ADDED
		if loc.Change == gitaccess.Delete {
			change = entities.Location_CHANGE_DELETED
		}

		switch change {
		case entities.Location_CHANGE_ADDED:
			addedLocs++
		case entities.Location_CHANGE_DELETED:
			deletedLocs++
		default:
			// This should never happen, but if it does, log and ignore.
			logging.Error(
				ctx,
				"unexpected location change type",
				kvp.String("change", change.String()),
				kvp.Int("change_id", int(change)),
			)
		}

		locations = append(locations, &entities.Location{
			Path:    loc.Path,
			Change:  change,
			EntryId: entryID,
		})
	}

	statting.Counter(ctx, "document.change.to_document.locations.count", int64(len(locations)))
	statting.Counter(ctx, "document.change.to_document.locations.added", int64(addedLocs))
	statting.Counter(ctx, "document.change.to_document.locations.deleted", int64(deletedLocs))

	return locations
}
