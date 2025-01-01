package gitaccess

import (
	"context"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/github/go-kvp"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/types"
)

const (
	// Minimum size of a blob that will be returned. Blobs smaller than this will
	// be skipped.
	MinBlobSize = 3
	// Maximum size of a blob that will be returned. Blobs bigger than this will
	// be skipped.
	MaxBlobSize = 350 * 1024
)

//go:generate counterfeiter . Client
type Client interface {
	// Diff takes a location limit and two Treeish objects and computes the diff as a slice of diff
	// entries. If base is nil, it will return the tree for head. The location limit is enforced
	// when listing trees for base and head only, and if the number of diff entries in either
	// treeish object exceeds the location limit, a location limit exceeded error is returned.
	//
	// NOTE: base and head may belong to different repositories. The location limit is assumed
	// to always be the location limit for the head repository, and always applies to both
	// base and head repositories. A location limit of 0 means no limit.
	Diff(ctx context.Context, locationLimit int, base, head *Treeish) (RepoDiff, error)

	// GetBlobsForDiff fetches blobs for a diff, calling the provided callback
	// with a BlobChangeEntry that is suitable for indexing (including deleted
	// blobs).
	GetBlobsForDiff(ctx context.Context, cancel context.CancelFunc, diff RepoDiff, f func(*BlobContentChange)) error

	// GetTreeOIDForCommit peels a commit oid to a tree oid.
	GetTreeOIDForCommit(ctx context.Context, repoID types.RepoID, commitOID ObjectID) (ObjectID, error)

	// GetDefaultRef returns the tip of the default branch.
	GetDefaultRef(ctx context.Context, repoID types.RepoID) (*RefTip, error)

	// ResolveBlobs mutates the RepoBlobsMap of repo_ids, leaving only oids that cannot be resolved.
	ResolveBlobs(ctx context.Context, blobs RepoBlobsMap) error

	// GetBlobs fetches blob content for the given batch of blob OIDs and calls the provided callback
	GetBlobs(ctx context.Context, repoID types.RepoID, oids []*spokes.ObjectID, f func(*BlobEntry)) error
}

type RepoBlobsMap map[types.RepoID]BlobSet

type BlobSet map[ObjectID]bool

// A tuple struct for a (repo ID, spokes treeish) pair.
type Treeish struct {
	RepoID  types.RepoID
	Treeish *spokes.Treeish
}

// ChangeType for the blob location.
type ChangeType int

const (
	Add ChangeType = iota
	Delete
)

func (c ChangeType) String() string {
	return []string{"Add", "Delete"}[c]
}

// BlobLocationEntry represents an added or deleted git blob at a path.
type BlobLocationEntry struct {
	Change ChangeType
	Path   string
}

// BlobChangeEntry is the interface for blob changes and their associated
// locations. Implementations may additionally have content, or not. Methods
// using this interface can perform operations on the (oid, locations) tuple
// without regard to the blob content.
type BlobChangeEntry interface {
	OID() ObjectID
	Locations() []*BlobLocationEntry
}

// BlobOIDChange represents a git blob OID and a list of location changes
// (adds, deletes) without content. Implements BlobChange.
type BlobOIDChange struct {
	ObjectID      ObjectID
	BlobLocations []*BlobLocationEntry
}

func (b *BlobOIDChange) OID() ObjectID {
	return b.ObjectID
}

func (b *BlobOIDChange) Locations() []*BlobLocationEntry {
	return b.BlobLocations
}

// BlobContentChange represents a git blob with its content and a list of
// location changes (adds, deletes). Implements BlobChangeEntry.
type BlobContentChange struct {
	ObjectID      ObjectID
	Content       []byte
	BlobLocations []*BlobLocationEntry
}

func (b *BlobContentChange) OID() ObjectID {
	return b.ObjectID
}

func (b *BlobContentChange) Locations() []*BlobLocationEntry {
	return b.BlobLocations
}

// BlobEntry represents a git blob including its content.
type BlobEntry struct {
	OID     ObjectID
	Content []byte
}

// RefTip is a named ref and the commit oid it points to.
type RefTip struct {
	RefName   string
	CommitOID ObjectID
}

// A diff (potentially cross-repo). There can be either one or two keys
// (repoIDs) in the map depending on if the diff was intra-repo or inter-repo
// respectively. Diff entries are associated with the repository where it is
// possible to fetch blob content.
type RepoDiff map[types.RepoID][]*DiffEntry

// BlobOIDChanges converts a RepoDiff into a slice of BlobOIDChange, grouping
// all updates for each OID.
func (diff RepoDiff) BlobOIDChanges() []*BlobOIDChange {
	changesByOID := map[ObjectID]*BlobOIDChange{}

	for _, entries := range diff {
		for _, entry := range entries {
			if changesByOID[entry.OID] == nil {
				changesByOID[entry.OID] = &BlobOIDChange{
					ObjectID:      entry.OID,
					BlobLocations: []*BlobLocationEntry{{Change: entry.Change, Path: entry.Path}},
				}
			} else {
				changesByOID[entry.OID].BlobLocations = append(changesByOID[entry.OID].BlobLocations, &BlobLocationEntry{Change: entry.Change, Path: entry.Path})
			}
		}
	}

	changes := make([]*BlobOIDChange, 0, len(changesByOID))
	for _, change := range changesByOID {
		changes = append(changes, change)
	}

	return changes
}

// Filter returns a new RepoDiff containing only ObjectIDs in the oids set.
func (diff RepoDiff) Filter(oids map[ObjectID]bool) RepoDiff {
	remainingDiff := RepoDiff{}

	if len(oids) == 0 {
		return remainingDiff
	}

	for repoID, entries := range diff {
		if remainingDiff[repoID] == nil {
			remainingDiff[repoID] = []*DiffEntry{}
		}

		for _, entry := range entries {
			if oids[entry.OID] {
				remainingDiff[repoID] = append(remainingDiff[repoID], entry)
			}
		}
	}

	return remainingDiff
}

// IsEmpty returns true if this RepoDiff has no entries.
func (diff RepoDiff) IsEmpty() bool {
	if len(diff) == 0 {
		return true
	}

	empty := true
	for _, entries := range diff {
		if len(entries) > 0 {
			empty = false
		}
	}

	return empty
}

// DiffEntry
type DiffEntry struct {
	Path   string
	OID    ObjectID
	Change ChangeType
}

// BlobLocation serves two purposes, it helps construct spokes requests with <commit:sha> tuples (keyed by repo id) so that spokes can perform the check. It is
// also used as a key when returning the unresolved blobs so that the calling code can filter out any locations that were not successfully resolved.
type BlobLocation struct {
	RepoID       types.RepoID
	Path         string
	CommitSHA    ObjectID
	BlobSHA      ObjectID
	NetworkID    types.RepoID
	IsRepoPublic bool
}

// Returns kvps that can be used for logging this blob location
func (b *BlobLocation) KVPs() []kvp.Field {
	return kvp.KVPs(
		kvp.Uint64("repo_id", uint64(b.RepoID)),
		kvp.String("path", b.Path),
		kvp.String("commit_sha", b.CommitSHA.String()),
		kvp.String("expected_blob_sha", b.BlobSHA.String()),
		kvp.Uint64("network_id", uint64(b.NetworkID)),
	).Fields()
}

const refsHeadsPrefix = "refs/heads/"

func NewRefTip(refName []byte, oid ObjectID) (*RefTip, error) {
	if !utf8.Valid(refName) {
		return nil, errors.Errorf("%q is an invalid RefName, only utf-8 is supported", refName)
	}

	r := &RefTip{RefName: string(refName), CommitOID: oid}
	if err := r.Validate(); err != nil {
		return nil, err
	}
	return r, nil
}

func (r *RefTip) Validate() error {
	if !strings.HasPrefix(string(r.RefName), refsHeadsPrefix) {
		return errors.Errorf("%q is an invalid RefName, refs must start with %s", r.RefName, refsHeadsPrefix)
	}

	if len(r.RefName) <= len(refsHeadsPrefix) {
		return errors.Errorf("%q is an invalid RefName, refs must be at least one character", r.RefName)
	}

	return nil
}

func (r *RefTip) String() string {
	if r == nil {
		return ""
	}
	return fmt.Sprintf("%s@%s", r.RefName, r.CommitOID.String())
}

// Ensure these meet the BlobChangeEntry interface
var _ BlobChangeEntry = (*BlobOIDChange)(nil)
var _ BlobChangeEntry = (*BlobContentChange)(nil)
