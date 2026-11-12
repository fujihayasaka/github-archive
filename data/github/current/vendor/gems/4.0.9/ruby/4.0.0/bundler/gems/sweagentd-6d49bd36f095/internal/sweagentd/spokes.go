package sweagentd

import "context"

// Spokes defines the interface for interacting with the Spokes service.
//
//nolint:interfacebloat // Spokes wraps a single external service; grouping all methods here is intentional.
type Spokes interface {
	// ReadBlob reads the content of a blob at the specified path in the given repository for the default branch.
	// It returns the content as a byte slice and the commit SHA for default branch, or an error if the blob cannot be found or read.
	ReadBlob(ctx context.Context, repoID uint64, path string) ([]byte, string, error)

	// ListTrees lists all tree objects (files and directories) at the specified path in the given repository.
	// It returns a slice of SpokesObject the default branch SHA. Each SpokesObject contains the OID and path of the object,
	// or an error if the path cannot be found or read.
	ListTrees(ctx context.Context, repoID uint64, path string) ([]*SpokesObject, string, error)

	// ListTreesByObjectID lists all tree objects (files and directories) at the specified path
	// in the given repository at the specified commit OID.
	ListTreesByObjectID(ctx context.Context, repoID uint64, oid, path string) ([]*SpokesObject, error)

	// ReadBlobObjects reads multiple blob objects by their OIDs in a single request.
	// It returns a slice of byte slices, with one entry per OID, in the order of the provided OIDs.
	ReadBlobObjects(ctx context.Context, repoID uint64, oids []string) ([][]byte, error)

	// ReadBlobByObjectIDPath reads the contents of the blob at the given path in the specified repository.
	// If the blob does not exist, it returns ErrNotFound.
	ReadBlobByObjectIDPath(ctx context.Context, repoID uint64, oid, path string) ([]byte, error)

	// ReadBlobsByPaths reads multiple blobs by their paths in a single batch.
	// It returns a slice of byte slices, one for each path. If a path doesn't exist, its entry will be nil.
	ReadBlobsByPaths(ctx context.Context, repoID uint64, oid string, paths []string) ([][]byte, error)

	// CreateEmptyCommit creates a new empty commit in the specified repository based on the given base branch.
	// It returns the OID of the new commit or an error if the operation fails.
	CreateEmptyCommit(ctx context.Context, opts CreateEmptyCommitOpts) (string, error)

	// CreateEmptyBranch creates a new branch in the specified repository at the given commit
	// It returns nil if the create was successful or an error if the operation fails.
	CreateBranch(ctx context.Context, opts CreateBranchOpts) error

	// CheckForExistingRef checks if a Git reference (branch or tag) with the specified name exists in the given repository.
	CheckForExistingRefs(ctx context.Context, repoID uint64, refNames []string) ([]bool, error)

	// CheckForExistingBranch checks if a branch with the specified name exists in the given repository.
	CheckForExistingBranches(ctx context.Context, repoID uint64, branchNames []string) ([]bool, error)

	// GetDefaultBranchOID resolves the default branch of a repository to its commit OID.
	GetDefaultBranchOID(ctx context.Context, repoID uint64) (string, error)

	// GetObjectIDForRef resolves a tag or branch reference to its corresponding object ID.
	// Accepts full branch refs (e.g., "refs/heads/main"), branch names (e.g., "main"),
	// full tag refs (e.g., "refs/tags/v1.0.0"), tag names (e.g., "v1.0.0"),
	// or object IDs (SHA-1 or SHA-256).
	GetObjectIDForRef(ctx context.Context, repoID uint64, ref string) (string, error)
}

// CreateEmptyCommitOpts contains options for creating a new empty commit in a repository.
type CreateEmptyCommitOpts struct {
	RepoID         uint64
	BaseRef        string // the base ref to build a new branch from. This can be a branch name, a fully qualified ref ("refs/heads/main") or an OID.
	AuthorName     string // the name of the commit author (may differ from committer when signing commits)
	AuthorEmail    string // the email of the commit author (may differ from committer when signing commits)
	CommitterName  string
	CommitterEmail string
	// SignCommit, when non-nil, signs the commit payload and returns a PGP
	// signature that will be embedded in the commit object's gpgsig header.
	SignCommit func(ctx context.Context, payload string) (string, error)
}

// CreateBranchOpts contains options for creating a new branch in a repository.
type CreateBranchOpts struct {
	RepoID         uint64
	CommitOID      string // the commit OID to create the branch on
	BranchName     string // the name of the new branch to be created
	CommitterName  string
	CommitterEmail string
}

// SpokesObject represents a file or directory object in a Git repository.
type SpokesObject struct {
	Oid   string
	Path  string
	IsDir bool // true if this is a directory (tree), false if it's a file (blob)
}
