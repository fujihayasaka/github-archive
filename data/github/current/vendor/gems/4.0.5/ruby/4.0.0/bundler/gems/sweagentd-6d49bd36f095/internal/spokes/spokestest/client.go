package spokestest

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/spokes"
	sweagentd "github.com/github/sweagentd/internal/sweagentd"
)

// Client is a mock Spokes client for testing.
type Client struct {
	blobs                    map[string][]byte
	repoBlobs                map[uint64]map[string][]byte // Repository-specific blobs
	commitSHA                string                       // Simulated branch commit SHA
	repositoryToReturnDataID uint64                       // Simulated repository ID

	// Mock functions for overriding default behavior
	MockReadBlob             func(ctx context.Context, repoID uint64, path string) ([]byte, string, error)
	MockCreateEmptyCommit    func(ctx context.Context, opts sweagentd.CreateEmptyCommitOpts) (string, error)
	MockCreateBranch         func(ctx context.Context, opts sweagentd.CreateBranchOpts) error
	MockCheckForExistingRefs func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error)
	MockGetObjectIDForRef    func(ctx context.Context, repoID uint64, ref string) (string, error)
}

// ClientOption is a function that configures a Client.
type ClientOption func(*Client)

// WithBlob adds a blob with the given path and content to the Client.
// If path is "*", it will be returned for any path not explicitly set.
// This blob will be available to all repositories (backwards compatibility).
func WithBlob(path string, content []byte) ClientOption {
	return WithCommitSHAAndBlob(path, "", content)
}

// WithCommitSHAAndBlob adds a blob with the given path, commit SHA, and content to the Client.
// If path is "*", it will be returned for any path not explicitly set.
// This blob will be available to all repositories (backwards compatibility).
func WithCommitSHAAndBlob(path, version string, content []byte) ClientOption {
	if version != "" {
		path = fmt.Sprintf("%s@%s", path, version)
	}
	return func(c *Client) {
		if c.blobs == nil {
			c.blobs = make(map[string][]byte)
		}

		c.blobs[path] = content
	}
}

// WithRepoBlob adds a blob with the given path and content to a specific repository.
// If path is "*", it will be returned for any path not explicitly set in that repository.
func WithRepoBlob(repoID uint64, path string, content []byte) ClientOption {
	return func(c *Client) {
		if c.repoBlobs == nil {
			c.repoBlobs = make(map[uint64]map[string][]byte)
		}
		if c.repoBlobs[repoID] == nil {
			c.repoBlobs[repoID] = make(map[string][]byte)
		}

		c.repoBlobs[repoID][path] = content
	}
}

// WithMockReadBlob sets a custom mock function for ReadBlob
func WithMockReadBlob(mockFn func(ctx context.Context, repoID uint64, path string) ([]byte, string, error)) ClientOption {
	return func(c *Client) {
		c.MockReadBlob = mockFn
	}
}

// WithMockCreateEmptyCommit sets a custom mock function for CreateEmptyCommit
func WithMockCreateEmptyCommit(mockFn func(ctx context.Context, opts sweagentd.CreateEmptyCommitOpts) (string, error)) ClientOption {
	return func(c *Client) {
		c.MockCreateEmptyCommit = mockFn
	}
}

// WithMockCreateBranch sets a custom mock function for CreateBranch
func WithMockCreateBranch(mockFn func(ctx context.Context, opts sweagentd.CreateBranchOpts) error) ClientOption {
	return func(c *Client) {
		c.MockCreateBranch = mockFn
	}
}

// WithMockCheckForExistingRefs sets a custom mock function for CheckForExistingRefs.
func WithMockCheckForExistingRefs(mockFn func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error)) ClientOption {
	return func(c *Client) {
		c.MockCheckForExistingRefs = mockFn
	}
}

// WithMockGetObjectIDForRef sets a custom mock function for GetObjectIDForRef
func WithMockGetObjectIDForRef(mockFn func(ctx context.Context, repoID uint64, ref string) (string, error)) ClientOption {
	return func(c *Client) {
		c.MockGetObjectIDForRef = mockFn
	}
}

// NewClient creates a new mock Spokes client with the given options.
func NewClient(t *testing.T, opts ...ClientOption) *Client {
	return NewClientWithCommitSHA(t, "", opts...)
}

// NewClientWithCommitSHA creates a new mock Spokes client with the given options and a commit SHA.
func NewClientWithCommitSHA(t *testing.T, commitSHA string, opts ...ClientOption) *Client {
	t.Helper()

	c := &Client{}
	for _, opt := range opts {
		opt(c)
	}

	if commitSHA == "" {
		commitSHA = "sha-0123456789101112131415161718192021222324252627"
	}
	c.commitSHA = commitSHA

	return c
}

// NewClientWithRepoAndCommitSHA creates a new mock Spokes client with the given options and a commit SHA for a specific repo.
func NewClientWithRepoAndCommitSHA(t *testing.T, repoID uint64, commitSHA string, opts ...ClientOption) *Client {
	t.Helper()

	c := NewClientWithCommitSHA(t, commitSHA, opts...)
	c.repositoryToReturnDataID = repoID

	return c
}

// ReadBlob returns the content of the blob at the given path and returns it along with the related branch commit SHA.
// If the blob does not exist, it returns nil, "", spokes.ErrNotFound.
// First checks repository-specific blobs, then falls back to global blobs.
func (c *Client) ReadBlob(ctx context.Context, repoID uint64, path string) ([]byte, string, error) {
	if c.MockReadBlob != nil {
		return c.MockReadBlob(ctx, repoID, path)
	}

	// First check repository-specific blobs
	if c.repoBlobs != nil && c.repoBlobs[repoID] != nil {
		if content, ok := c.repoBlobs[repoID][path]; ok {
			return content, c.commitSHA, nil
		}
		if content, ok := c.repoBlobs[repoID]["*"]; ok {
			return content, c.commitSHA, nil
		}
	}

	// Fall back to global blobs (backwards compatibility)
	if content, ok := c.blobs[path]; ok {
		return content, c.commitSHA, nil
	}

	if content, ok := c.blobs["*"]; ok {
		return content, c.commitSHA, nil
	}

	return nil, "", spokes.ErrNotFound
}

// ReadBlobByObjectIDPath reads the contents of the blob at the given path in the specified repository.
// If the blob does not exist, it returns ErrNotFound.
func (c *Client) ReadBlobByObjectIDPath(ctx context.Context, repoID uint64, oid, path string) ([]byte, error) {
	if content, ok := c.blobs[fmt.Sprintf("%s@%s", path, oid)]; ok {
		return content, nil
	}

	if content, ok := c.blobs["*"]; ok {
		return content, nil
	}

	return nil, spokes.ErrNotFound
}

// ListTrees returns the list of immediate children under the given path.
// Unlike recursive behavior, this only returns direct children (one level deep).
// If no files exist under the path, it returns ErrNotFound.
// First checks repository-specific blobs, then falls back to global blobs.
func (c *Client) ListTrees(ctx context.Context, repoID uint64, path string) ([]*sweagentd.SpokesObject, string, error) {
	objs, err := c.ListTreesByObjectID(ctx, repoID, c.commitSHA, path)
	if err != nil {
		return nil, "", err
	}
	return objs, c.commitSHA, nil
}

// ListTreesByObjectID returns the list of immediate children under the given path at a specific OID.
func (c *Client) ListTreesByObjectID(ctx context.Context, repoID uint64, oid, path string) ([]*sweagentd.SpokesObject, error) {
	var files []*sweagentd.SpokesObject
	seenPaths := make(map[string]bool)

	// Simulate that custom agents only exist in a specific repository if set
	if c.repositoryToReturnDataID != 0 && c.repositoryToReturnDataID != repoID {
		return files, nil
	}

	// Helper to extract immediate child from a path and determine if it's a directory
	// e.g., if path is "skills/" and blobPath is "skills/math/SKILL.md",
	// this returns "math", true (it's a directory because there's more path after it)
	// If blobPath is "skills/README.md", returns "README.md", false (it's a file)
	extractImmediateChild := func(blobPath, prefix string) (string, bool, bool) {
		after, ok := strings.CutPrefix(blobPath, prefix)
		if !ok {
			return "", false, false
		}
		// Get only the first segment (immediate child)
		parts := strings.SplitN(after, "/", 2)
		if len(parts) == 0 || parts[0] == "" {
			return "", false, false
		}
		// If there are more parts after the first segment, it's a directory
		isDir := len(parts) > 1
		return parts[0], isDir, true
	}

	// First check repository-specific blobs
	if c.repoBlobs != nil && c.repoBlobs[repoID] != nil {
		for blobPath := range c.repoBlobs[repoID] {
			if child, isDir, ok := extractImmediateChild(blobPath, path); ok {
				if !seenPaths[child] {
					file := &sweagentd.SpokesObject{
						Oid:   blobPath, // OID is not used in this mock
						Path:  child,    // Just the immediate child name
						IsDir: isDir,
					}
					files = append(files, file)
					seenPaths[child] = true
				}
			}
		}
	}

	// Then check global blobs (backwards compatibility)
	if c.blobs != nil {
		for blobPath := range c.blobs {
			if child, isDir, ok := extractImmediateChild(blobPath, path); ok {
				if !seenPaths[child] {
					file := &sweagentd.SpokesObject{
						Oid:   blobPath, // OID is not used in this mock
						Path:  child,    // Just the immediate child name
						IsDir: isDir,
					}
					files = append(files, file)
					seenPaths[child] = true
				}
			}
		}
	}

	if len(files) == 0 {
		return nil, spokes.ErrNotFound
	}

	return files, nil
}

// ReadBlobObjects returns the contents of the blobs with the given OIDs.
// First checks repository-specific blobs, then falls back to global blobs.
func (c *Client) ReadBlobObjects(ctx context.Context, repoID uint64, oids []string) ([][]byte, error) {
	var contents [][]byte
	for _, oid := range oids {
		// First check repository-specific blobs
		if c.repoBlobs != nil && c.repoBlobs[repoID] != nil {
			if content, ok := c.repoBlobs[repoID][oid]; ok {
				contents = append(contents, content)
				continue
			}
		}

		// Fall back to global blobs (backwards compatibility)
		if content, ok := c.blobs[oid]; ok {
			contents = append(contents, content)
		}
	}

	return contents, nil
}

// ReadBlobsByPaths returns the contents of blobs at the given paths.
// First checks repository-specific blobs, then falls back to global blobs.
func (c *Client) ReadBlobsByPaths(ctx context.Context, repoID uint64, oid string, paths []string) ([][]byte, error) {
	results := make([][]byte, len(paths))
	for i, path := range paths {
		// First check repository-specific blobs
		if c.repoBlobs != nil && c.repoBlobs[repoID] != nil {
			if content, ok := c.repoBlobs[repoID][path]; ok {
				results[i] = content
				continue
			}
		}

		// Fall back to global blobs (backwards compatibility)
		if content, ok := c.blobs[path]; ok {
			results[i] = content
		}
		// If not found, leave as nil
	}

	return results, nil
}

// CreateEmptyCommit creates a new empty commit in the specified repository based on the given base branch.
// This is a mock implementation for testing that returns a fake commit SHA.
func (c *Client) CreateEmptyCommit(ctx context.Context, opts sweagentd.CreateEmptyCommitOpts) (string, error) {
	if c.MockCreateEmptyCommit != nil {
		return c.MockCreateEmptyCommit(ctx, opts)
	}
	// Return a mock commit SHA for testing purposes
	return "abcdef1234567890abcdef1234567890abcdef12", nil
}

// CreateBranch creates a new branch in the specified repository
func (c *Client) CreateBranch(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
	if c.MockCreateBranch != nil {
		return c.MockCreateBranch(ctx, opts)
	}
	return nil
}

// CheckForExistingRefs checks if the specified reference exists in the given repository.
// This is a mock implementation for testing that always returns false (the ref does _not_ exist).
func (c *Client) CheckForExistingRefs(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
	if c.MockCheckForExistingRefs != nil {
		return c.MockCheckForExistingRefs(ctx, repoID, refNames)
	}

	return make([]bool, len(refNames)), nil
}

// CheckForExistingBranches checks if the specified branch exists in the given repository.
// This is a mock implementation for testing that always returns true.
func (c *Client) CheckForExistingBranches(ctx context.Context, repoID uint64, branchNames []string) ([]bool, error) {
	refs := make([]string, len(branchNames))
	for i, branchName := range branchNames {
		refs[i] = fmt.Sprintf("refs/heads/%s", branchName)
	}

	return c.CheckForExistingRefs(ctx, repoID, refs)
}

// GetObjectIDForRef resolves a tag or branch reference to its corresponding object ID.
// This is a mock implementation for testing that returns the stored commit SHA.
func (c *Client) GetObjectIDForRef(ctx context.Context, repoID uint64, ref string) (string, error) {
	if c.MockGetObjectIDForRef != nil {
		return c.MockGetObjectIDForRef(ctx, repoID, ref)
	}
	return ref, nil
}

// GetDefaultBranchOID resolves the default branch of a repository to its commit OID.
// This is a mock implementation for testing that returns the stored commit SHA.
func (c *Client) GetDefaultBranchOID(ctx context.Context, repoID uint64) (string, error) {
	return c.commitSHA, nil
}
