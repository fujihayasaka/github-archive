package sweagentd

import "context"

type Spokes interface {
	// ReadBlob reads the content of a blob at the specified path in the given repository for the default branch.
	// It returns the content as a byte slice and the commit SHA for default branch, or an error if the blob cannot be found or read.
	ReadBlob(ctx context.Context, repoID uint64, path string) ([]byte, string, error)

	// ListTrees lists all tree objects (files and directories) at the specified path in the given repository.
	// It returns a slice of SpokesObject the default branch SHA. Each SpokesObject contains the OID and path of the object,
	// or an error if the path cannot be found or read.
	ListTrees(ctx context.Context, repoID uint64, path string) ([]*SpokesObject, string, error)

	// ReadBlobObjects reads multiple blob objects by their OIDs in a single request.
	// It returns a concatenated byte slice of all blob contents in the order of the provided OIDs.
	ReadBlobObjects(ctx context.Context, repoID uint64, oids []string) ([][]byte, error)

	// ReadBlobByObjectIDPath reads the contents of the bl	ob at the given path in the specified repository.
	// If the blob does not exist, it returns ErrNotFound.
	ReadBlobByObjectIDPath(ctx context.Context, repoID uint64, oid, path string) ([]byte, error)

	// CreateEmptyBranch creates a new empty branch in the specified repository based on the given base branch.
	// It returns the OID of the commit on the newly created branch or an error if the operation fails.
	CreateEmptyBranch(ctx context.Context, opts CreateEmptyBranchOpts) (string, error)
}

// CreateEmptyBranchOpts contains options for creating a new empty branch in a repository.
type CreateEmptyBranchOpts struct {
	RepoID         uint64
	BaseRef        string // the base ref to build a new branch from. This can be a branch name, a fully qualified ref ("refs/heads/main") or an OID.
	BranchName     string // the name of the new branch to be created
	CommitterName  string
	CommitterEmail string
}

// SpokesObject represents a file or directory object in a Git repository.
type SpokesObject struct {
	Oid  string
	Path string
}
