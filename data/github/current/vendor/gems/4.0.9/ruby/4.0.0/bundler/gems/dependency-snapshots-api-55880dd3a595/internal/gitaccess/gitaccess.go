package gitaccess

import (
	"context"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

// MaxRecentCommits - at most, fetch 5 1k pages of results from Spokes.
// in practice, "numCommits" in a call to GetRecentCommits will be 1 page
// or (much) less. At ~20-50ms per page this cap seems reasonable without
// constraining future use cases; Spokes folks don't cap this at all.
const MaxRecentCommits = 5000

// SHA - temporary: placeholder to abstract Spokes specifics away from end users
type SHA string

// HEAD convenience selector for latest commit on default branch
var HEAD = []byte(`HEAD`)

// Client - abstracts the backing implementations for our Git access API.
type Client interface {
	// GetDefaultBranch - given a GitHub repository ID, obtain the default branch
	// name, usable as an input (Git revision) to GetRecentCommits or GetHEADCommit.
	GetDefaultBranch(ctx context.Context, repoID uint64) (string, error)

	// GetHEADCommit - Obtain the latest commit SHA for the given GitHub repository ID
	// and optional branch name (default branch is assumed if absent.)
	GetHEADCommit(ctx context.Context, repoID uint64, optionalBranchName ...string) (SHA, error)

	// GetRecentCommits - given:
	// - a GitHub repository ID
	// - a nonzero number of latest commit SHAs to fetch
	// - an (optional) branch name
	//
	// Obtain the most recent N commit SHAs as an ordered array
	// (most recent to oldest) starting at HEAD, or return an error.
	// If no branch name is specified, we fall back to the default branch.
	GetRecentCommits(ctx context.Context, repoID uint64, numCommits uint, optionalBranchName ...string) ([]SHA, error)

	// ListTreeByRef - lists the entire tree for a repository at a given ref.
	ListTreeByRef(ctx context.Context, repoID uint64, ref []byte) ([]*types.TreeEntry, error)

	// ListTreeByCommit - lists the entire tree for a repository at a given commit OID.
	ListTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error)

	// ListRootTreeByCommit - lists only the root-level tree entries for a repository at a given commit OID.
	ListRootTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error)

	// CompareTrees - compares two commits and returns the diff entries between them.
	CompareTrees(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error)

	// GetBlobByOID - retrieves blob contents by blob OID.
	GetBlobByOID(ctx context.Context, repoID uint64, blobOID string) ([]byte, uint64, error)

	// GetBlobByPath - retrieves blob contents by path at a given ref.
	GetBlobByPath(ctx context.Context, repoID uint64, ref []byte, path string) ([]byte, uint64, error)

	// GetBlobByPathAndCommit - retrieves blob contents by path at a given commit.
	GetBlobByPathAndCommit(ctx context.Context, repoID uint64, commit string, path string) ([]byte, uint64, error)

	// ResolveRef - resolves a ref to an ObjectID (commit sha).
	ResolveRef(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error)
}
