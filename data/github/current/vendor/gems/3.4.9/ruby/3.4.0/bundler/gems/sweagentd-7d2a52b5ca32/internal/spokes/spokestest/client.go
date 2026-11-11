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
}

// ClientOption is a function that configures a Client.
type ClientOption func(*Client)

// ClientWithBlob adds a blob with the given path and content to the Client.
// If path is "*", it will be returned for any path not explicitly set.
// This blob will be available to all repositories (backwards compatibility).
func ClientWithBlob(path string, content []byte) ClientOption {
	return ClientWithCommitSHAAndBlob(path, "", content)
}

// ClientWithCommitSHAAndBlob adds a blob with the given path, commit SHA, and content to the Client.
// If path is "*", it will be returned for any path not explicitly set.
// This blob will be available to all repositories (backwards compatibility).
func ClientWithCommitSHAAndBlob(path, version string, content []byte) ClientOption {
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

// ClientWithRepoBlob adds a blob with the given path and content to a specific repository.
// If path is "*", it will be returned for any path not explicitly set in that repository.
func ClientWithRepoBlob(repoID uint64, path string, content []byte) ClientOption {
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
// If the blob does not exist, it returns nil, "", nil.
// First checks repository-specific blobs, then falls back to global blobs.
func (c *Client) ReadBlob(ctx context.Context, repoID uint64, path string) ([]byte, string, error) {
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

// ListTrees returns the list of files under the given path.
// If no files exist under the path, it returns an empty list.
// First checks repository-specific blobs, then falls back to global blobs.
func (c *Client) ListTrees(ctx context.Context, repoID uint64, path string) ([]*sweagentd.SpokesObject, string, error) {
	var files []*sweagentd.SpokesObject
	seenPaths := make(map[string]bool)

	// Simulate that custom agents only exist in a specific repository if set
	if c.repositoryToReturnDataID != 0 && c.repositoryToReturnDataID != repoID {
		return files, c.commitSHA, nil
	}

	// First check repository-specific blobs
	if c.repoBlobs != nil && c.repoBlobs[repoID] != nil {
		for blobPath := range c.repoBlobs[repoID] {
			if after, ok := strings.CutPrefix(blobPath, path); ok {
				if !seenPaths[blobPath] {
					file := &sweagentd.SpokesObject{
						Oid:  blobPath, // OID is not used in this mock
						Path: after,
					}
					files = append(files, file)
					seenPaths[blobPath] = true
				}
			}
		}
	}

	// Then check global blobs (backwards compatibility)
	if c.blobs != nil {
		for blobPath := range c.blobs {
			if after, ok := strings.CutPrefix(blobPath, path); ok {
				if !seenPaths[blobPath] {
					file := &sweagentd.SpokesObject{
						Oid:  blobPath, // OID is not used in this mock
						Path: after,
					}
					files = append(files, file)
					seenPaths[blobPath] = true
				}
			}
		}
	}

	if len(files) == 0 {
		return nil, "", spokes.ErrNotFound
	}

	return files, c.commitSHA, nil
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

// CreateEmptyBranch creates a new empty branch in the specified repository based on the given base branch.
// This is a mock implementation for testing that returns a fake commit SHA.
func (c *Client) CreateEmptyBranch(ctx context.Context, opts sweagentd.CreateEmptyBranchOpts) (string, error) {
	// Return a mock commit SHA for testing purposes
	return "abcdef1234567890abcdef1234567890abcdef12", nil
}
