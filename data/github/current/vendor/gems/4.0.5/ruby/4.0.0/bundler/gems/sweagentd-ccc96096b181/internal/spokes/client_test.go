package spokes

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/references"
	"github.com/github/spokes-proto/gen/go/v1/trees"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/sweagentd/internal/observability"
	"github.com/twitchtv/twirp"
)

func TestClient(t *testing.T) {
	t.Run("ReadBlob returns ErrNotFound for missing blob", func(t *testing.T) {
		blobsAPI := &mockBlobAPI{
			getBlobContentsFunc: func(ctx context.Context, req *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
				return nil, twirp.NewError(twirp.NotFound, "blob not found")
			},
		}
		c := &Client{
			obsv:             observability.NewNoopExporters(),
			blobClient:       blobsAPI,
			referencesClient: &mockReferencesAPI{},
		}
		_, _, err := c.ReadBlob(context.Background(), 1, "missing.txt")
		if !errors.Is(err, ErrNotFound) {
			t.Fatalf("expected ErrNotFound, got %v", err)
		}
	})

	t.Run("ListTrees returns empty list for no files", func(t *testing.T) {
		treesAPI := &mockTreesAPI{
			listTreesFunc: func(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
				return &trees.ListTreesResponse{
					Entries: []*types.TreeEntry{},
				}, nil
			},
		}
		c := &Client{
			obsv:             observability.NewNoopExporters(),
			treesClient:      treesAPI,
			referencesClient: &mockReferencesAPI{},
		}
		files, commit, err := c.ListTrees(context.Background(), 1, "empty/")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(files) != 0 {
			t.Fatalf("expected empty list, got %v", files)
		}
		if commit == "" {
			t.Fatal("expected commit, got empty")
		}
	})

	t.Run("ListTrees returns ErrNotFound for missing path", func(t *testing.T) {
		treesAPI := &mockTreesAPI{
			listTreesFunc: func(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
				return nil, twirp.NewError(twirp.NotFound, "path not found")
			},
		}
		c := &Client{
			obsv:             observability.NewNoopExporters(),
			treesClient:      treesAPI,
			referencesClient: &mockReferencesAPI{},
		}
		_, _, err := c.ListTrees(context.Background(), 1, "missing/")
		if !errors.Is(err, ErrNotFound) {
			t.Fatalf("expected ErrNotFound, got %v", err)
		}
	})

	t.Run("GetObjectIDForRef handles different ref formats", func(t *testing.T) {
		testCases := []struct {
			name        string
			ref         string
			expectError bool
			expectedOID string
		}{
			{
				name:        "full branch ref",
				ref:         "refs/heads/main",
				expectError: false,
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
			},
			{
				name:        "branch name without prefix",
				ref:         "main",
				expectError: false,
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
			},
			{
				name:        "full tag ref",
				ref:         "refs/tags/v1.0.0",
				expectError: false,
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
			},
			{
				name:        "valid SHA-1 object ID",
				ref:         "1234567890123456789012345678901234567890",
				expectError: false,
				expectedOID: "1234567890123456789012345678901234567890",
			},
			{
				name:        "valid SHA-256 object ID",
				ref:         "1234567890123456789012345678901234567890123456789012345678901234",
				expectError: false,
				expectedOID: "1234567890123456789012345678901234567890123456789012345678901234",
			},
			{
				name:        "invalid object ID",
				ref:         "invalid-sha",
				expectError: false, // Should resolve as branch name
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				c := &Client{
					obsv:             observability.NewNoopExporters(),
					referencesClient: &mockReferencesAPI{},
				}

				oid, err := c.GetObjectIDForRef(context.Background(), 1, tc.ref)
				if tc.expectError && err == nil {
					t.Fatal("expected error but got none")
				}
				if !tc.expectError && err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				if !tc.expectError && oid != tc.expectedOID {
					t.Fatalf("expected OID %s, got %s", tc.expectedOID, oid)
				}
			})
		}
	})

	t.Run("committishToOID handles different ref formats", func(t *testing.T) {
		testCases := []struct {
			name        string
			ref         string
			expectError bool
			expectedOID string
		}{
			{
				name:        "full branch ref",
				ref:         "refs/heads/main",
				expectError: false,
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
			},
			{
				name:        "branch name without prefix",
				ref:         "main",
				expectError: false,
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
			},
			{
				name:        "valid SHA-1 object ID",
				ref:         "1234567890123456789012345678901234567890",
				expectError: false,
				expectedOID: "1234567890123456789012345678901234567890",
			},
			{
				name:        "valid SHA-256 object ID",
				ref:         "1234567890123456789012345678901234567890123456789012345678901234",
				expectError: false,
				expectedOID: "1234567890123456789012345678901234567890123456789012345678901234",
			},
			{
				name:        "tag ref not supported",
				ref:         "refs/tags/v1.0.0",
				expectError: true,
			},
			{
				name:        "invalid object ID",
				ref:         "invalid-sha",
				expectError: false, // Should resolve as branch name
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				c := &Client{
					obsv:             observability.NewNoopExporters(),
					referencesClient: &mockReferencesAPI{},
				}

				oid, err := c.committishToOID(context.Background(), 1, tc.ref)
				if tc.expectError && err == nil {
					t.Fatal("expected error but got none")
				}
				if !tc.expectError && err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				if !tc.expectError && oid != tc.expectedOID {
					t.Fatalf("expected OID %s, got %s", tc.expectedOID, oid)
				}
			})
		}
	})

	t.Run("isValidObjectID validates object IDs correctly", func(t *testing.T) {
		testCases := []struct {
			name     string
			id       string
			expected bool
		}{
			{
				name:     "valid SHA-1 (40 chars)",
				id:       "1234567890123456789012345678901234567890",
				expected: true,
			},
			{
				name:     "valid SHA-256 (64 chars)",
				id:       "1234567890123456789012345678901234567890123456789012345678901234",
				expected: true,
			},
			{
				name:     "uppercase SHA-1",
				id:       "ABCDEF1234567890123456789012345678901234",
				expected: true,
			},
			{
				name:     "mixed case SHA-1",
				id:       "aBcDeF1234567890123456789012345678901234",
				expected: true,
			},
			{
				name:     "too short",
				id:       "123456789012345678901234567890123456789",
				expected: false,
			},
			{
				name:     "too long for SHA-1, too short for SHA-256",
				id:       "12345678901234567890123456789012345678901",
				expected: false,
			},
			{
				name:     "too long for SHA-256",
				id:       "12345678901234567890123456789012345678901234567890123456789012345",
				expected: false,
			},
			{
				name:     "contains invalid characters",
				id:       "123456789012345678901234567890123456789g",
				expected: false,
			},
			{
				name:     "empty string",
				id:       "",
				expected: false,
			},
			{
				name:     "branch name",
				id:       "main",
				expected: false,
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				result := isValidObjectID(tc.id)
				if result != tc.expected {
					t.Fatalf("expected %v for ID %s, got %v", tc.expected, tc.id, result)
				}
			})
		}
	})

	t.Run("committishToOID handles resolution errors", func(t *testing.T) {
		mockRef := &mockReferencesAPI{
			MockResolveReferences: func(ctx context.Context, req *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error) {
				return nil, errors.New("network error")
			},
		}

		c := &Client{
			obsv:             observability.NewNoopExporters(),
			referencesClient: mockRef,
		}

		_, err := c.committishToOID(context.Background(), 1, "nonexistent-branch")
		if err == nil {
			t.Fatal("expected error but got none")
		}
		if !strings.Contains(err.Error(), "failed to resolve ref") {
			t.Fatalf("unexpected error message: %v", err)
		}
	})
}

type mockBlobAPI struct {
	blobs.BlobsAPI

	getBlobContentsFunc func(context.Context, *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error)
}

// GetBlobContents returns the first megabyte of a blob specified by its oid.
func (m *mockBlobAPI) GetBlobContents(ctx context.Context, _ *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
	if m.getBlobContentsFunc != nil {
		return m.getBlobContentsFunc(ctx, nil)
	}

	return nil, errors.New("not implemented")
}

type mockTreesAPI struct {
	trees.TreesAPI

	listTreesFunc func(context.Context, *trees.ListTreesRequest) (*trees.ListTreesResponse, error)
}

// ListTrees returns a list of tree entries associated with the tree.
func (m *mockTreesAPI) ListTrees(ctx context.Context, _ *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
	if m.listTreesFunc != nil {
		return m.listTreesFunc(ctx, nil)
	}

	panic("not implemented") // TODO: Implement
}

type mockReferencesAPI struct {
	references.ReferencesAPI

	MockResolveReferences func(context.Context, *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error)
}

// ResolveReferences resolves repository references to their object IDs.
func (m *mockReferencesAPI) ResolveReferences(ctx context.Context, req *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error) {
	if m.MockResolveReferences != nil {
		return m.MockResolveReferences(ctx, req)
	}

	return &references.ResolveReferencesResponse{
		Items: []*references.ResolveReferencesResponse_ResolvedReference{
			{Oid: types.NewObjectID("sha-0123456789101112131415161718192021222324252627")},
		},
	}, nil
}
