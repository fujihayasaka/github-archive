package healthcheck

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/blackbird/crates/core/pkg/shard"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/parser"
	"github.com/github/blackbird-mw/internal/types"
)

// Create a new contentTracker with epochMode sharding.
func newContentTracker(epochMode epoch.EpochMode) *contentTracker {
	return &contentTracker{
		epochMode:       epochMode,
		docSHAToBlobSHA: map[gitaccess.ObjectID]gitaccess.ObjectID{},
		docSHAToPaths:   map[gitaccess.ObjectID]map[string]bool{},
		pathToDocSHA:    map[string]gitaccess.ObjectID{},
	}
}

// contentTracker keeps track of documents from the Git source repository that
// we expect to find in Blackbird.
type contentTracker struct {
	epochMode       epoch.EpochMode                           // epoch mode to use for computing doc SHA when adding content
	docSHAToBlobSHA map[gitaccess.ObjectID]gitaccess.ObjectID // map from doc SHA -> blob SHA
	docSHAToPaths   map[gitaccess.ObjectID]map[string]bool    // map from doc SHA -> set of paths (must be at least 1 path)
	pathToDocSHA    map[string]gitaccess.ObjectID             // map from path -> doc SHA
}

// Return a set of blob SHAs in sourceDocuments (it is a copy, modifying this
// map will not change the sourceDocuments instance).
func (o *contentTracker) blobSHAs() map[gitaccess.ObjectID]bool {
	blobSHAs := make(map[gitaccess.ObjectID]bool, len(o.docSHAToBlobSHA))
	for _, blobSHA := range o.docSHAToBlobSHA {
		blobSHAs[blobSHA] = true
	}

	return blobSHAs
}

func (o *contentTracker) numDocs() int {
	return len(o.docSHAToBlobSHA)
}

func (o *contentTracker) numPaths() int {
	return len(o.pathToDocSHA)
}

// add a blob SHA and path to the contentTracker. Will compute the doc SHA based on the epoch mode.
func (o *contentTracker) add(blobSHA gitaccess.ObjectID, path string) {
	docSHA := gitaccess.NewObjectIDFromBytes(shard.DocSHAForEpochMode(blobSHA.Bytes(), path, o.epochMode))

	if existingBlobSHA, ok := o.docSHAToBlobSHA[docSHA]; !ok {
		o.docSHAToBlobSHA[docSHA] = blobSHA
	} else if existingBlobSHA != blobSHA {
		panic(fmt.Sprintf("attempted to associate blob sha %q with doc SHA %q, but it already is associated with %q", blobSHA, docSHA, existingBlobSHA))
	}

	if _, ok := o.docSHAToPaths[docSHA]; !ok {
		o.docSHAToPaths[docSHA] = map[string]bool{}
	}

	if o.docSHAToPaths[docSHA][path] {
		panic(fmt.Sprintf("attempted to associate doc SHA %q to path %q, but it already is", docSHA, path))
	}

	o.docSHAToPaths[docSHA][path] = true

	if existingDocSHA, ok := o.pathToDocSHA[path]; !ok {
		o.pathToDocSHA[path] = docSHA
	} else {
		panic(fmt.Sprintf("attempted to associate path %q to doc SHA %q, but it already is associated with %q", path, docSHA, existingDocSHA))
	}
}

// removePathForDocSHA removes the path for the doc SHA if it exists. A doc SHA may
// have one or more paths. If the doc SHA has no more paths after removal of
// this path, it is removed.
//
// Returns true if the path was removed.
func (o *contentTracker) removePathForDocSHA(docSHA gitaccess.ObjectID, path string) bool {
	if _, ok := o.pathToDocSHA[path]; !ok {
		return false
	}

	if _, ok := o.docSHAToPaths[docSHA]; !ok {
		panic(fmt.Sprintf("invariant violated: no paths for doc SHA %s", docSHA))
	}

	delete(o.pathToDocSHA, path)
	delete(o.docSHAToPaths[docSHA], path)

	if len(o.docSHAToPaths[docSHA]) == 0 {
		delete(o.docSHAToPaths, docSHA)
		delete(o.docSHAToBlobSHA, docSHA)
	}

	return true
}

// removePathForBlobSHA removes the path for the blob SHA if it exists by
// computing the doc SHA and removing associated entries. If the computed doc
// SHA has no more paths after removal of this path, it is removed.
//
// Returns true if the path was removed.
func (o *contentTracker) removePathForBlobSHA(blobSHA gitaccess.ObjectID, path string) bool {
	docSHA := gitaccess.NewObjectIDFromBytes(shard.DocSHAForEpochMode(blobSHA.Bytes(), path, o.epochMode))
	return o.removePathForDocSHA(docSHA, path)
}

// removeDocSHA removes the doc SHA and all associated mappings.
func (o *contentTracker) removeDocSHA(docSHA gitaccess.ObjectID) {
	pathSet, ok := o.docSHAToPaths[docSHA]
	if !ok {
		panic(fmt.Sprintf("unexpected doc SHA %q, cannot remove", docSHA))
	}
	for path := range pathSet {
		delete(o.pathToDocSHA, path)
	}

	delete(o.docSHAToPaths, docSHA)
	delete(o.docSHAToBlobSHA, docSHA)
}

// pathsForBlobSHA returns the paths for a blobSHA.
//
// NOTE: This does a linear scan through all doc SHAs.
func (o *contentTracker) pathsForBlobSHA(blobSHA gitaccess.ObjectID) []string {
	paths := []string{}
	for docSHA, bs := range o.docSHAToBlobSHA {
		if bs == blobSHA {
			for path := range o.docSHAToPaths[docSHA] {
				paths = append(paths, path)
			}
		}
	}

	return paths
}

func (o *contentTracker) pathExists(path string) bool {
	_, ok := o.pathToDocSHA[path]
	return ok
}

func (o *contentTracker) numPathsForDocSHA(docSHA gitaccess.ObjectID) int {
	return len(o.docSHAToPaths[docSHA])
}

func (o *contentTracker) docPaths() []docPath {
	docPaths := make([]docPath, 0, len(o.pathToDocSHA))
	for path, docSHA := range o.pathToDocSHA {
		docPaths = append(docPaths, docPath{docSHA: docSHA, blobSHA: o.docSHAToBlobSHA[docSHA], path: path})
	}

	return docPaths
}

// For large diffs (lots of blobs) we downsample the paths we're going to
// check based on trailing zero bits in the blob SHA.
func (o *contentTracker) downsampleQuery(ctx context.Context, repoID types.RepoID) (*parser.Query, int, error) {
	numTrailingZeros := 0
	initialSize := o.numDocs()
	for {
		const checkSizeThreshold = 5000
		if o.numDocs() < checkSizeThreshold {
			break
		}
		if numTrailingZeros > 64 {
			logging.Error(
				ctx,
				"trailing_zeros>64, unable to reduce the number of blobs to check",
				kvp.Int("expected_docs", o.numDocs()),
				kvp.Int("initial_expected_docs", initialSize),
			)
			return nil, numTrailingZeros, errors.New("trailing_zeros>64, unable to reduce the number of blobs to check")
		}
		for docSHA := range o.docSHAToBlobSHA {
			if docSHA.TrailingZeros() <= numTrailingZeros {
				o.removeDocSHA(docSHA)
			}
		}
		numTrailingZeros++
	}

	// Search blackbird for this repo with the number of trailing zeros we used.
	q := parser.RepoID(int(repoID))
	if numTrailingZeros > 0 {
		// `trait:trailing_zeros_K` <- means at least K trailing zeros in the binary representation of the blob oid.
		q = parser.And(q, parser.NumTrailingZeros(numTrailingZeros))
		logging.Info(ctx, "downsampled with trailing zeros", kvp.Int("num_trailing_zeros", numTrailingZeros), kvp.Int("num_oids", o.numDocs()))
	}

	return q, numTrailingZeros, nil
}

// docPath is a tuple of (doc SHA, blob SHA, path) used for reporting
// mismatches.
type docPath struct {
	docSHA  gitaccess.ObjectID
	blobSHA gitaccess.ObjectID
	path    string
}

func (dp docPath) String() string {
	return fmt.Sprintf("doc SHA: %s, blob SHA: %s, path: %q", dp.docSHA, dp.blobSHA, dp.path)
}
