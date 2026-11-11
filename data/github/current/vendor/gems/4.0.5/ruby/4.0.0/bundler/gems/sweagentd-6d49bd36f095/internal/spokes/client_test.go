package spokes

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/objects"
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

	t.Run("ListTreesByObjectID returns entries for valid OID and path", func(t *testing.T) {
		treesAPI := &mockTreesAPI{
			listTreesFunc: func(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
				return &trees.ListTreesResponse{
					Entries: []*types.TreeEntry{
						{
							Object: types.NewBlobObject(types.NewObjectID("file-oid-1"), 100, 0o100644),
							Path:   types.NewPath([]byte("README.md")),
							Mode:   types.NewMode(0o100644),
						},
						{
							Object: types.NewBlobObject(types.NewObjectID("dir-oid-1"), 0, 0o040000),
							Path:   types.NewPath([]byte("src")),
							Mode:   types.NewMode(0o040000),
						},
					},
				}, nil
			},
		}
		c := &Client{
			obsv:        observability.NewNoopExporters(),
			treesClient: treesAPI,
		}
		objs, err := c.ListTreesByObjectID(context.Background(), 1, "abc123", "root/")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(objs) != 2 {
			t.Fatalf("expected 2 objects, got %d", len(objs))
		}
		if objs[0].Path != "README.md" {
			t.Fatalf("expected README.md, got %s", objs[0].Path)
		}
		if objs[0].IsDir {
			t.Fatal("expected README.md to not be a directory")
		}
		if objs[1].Path != "src" {
			t.Fatalf("expected src, got %s", objs[1].Path)
		}
		if !objs[1].IsDir {
			t.Fatal("expected src to be a directory")
		}
	})

	t.Run("ListTreesByObjectID returns ErrNotFound for missing path", func(t *testing.T) {
		treesAPI := &mockTreesAPI{
			listTreesFunc: func(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
				return nil, twirp.NewError(twirp.NotFound, "path not found")
			},
		}
		c := &Client{
			obsv:        observability.NewNoopExporters(),
			treesClient: treesAPI,
		}
		_, err := c.ListTreesByObjectID(context.Background(), 1, "abc123", "missing/")
		if !errors.Is(err, ErrNotFound) {
			t.Fatalf("expected ErrNotFound, got %v", err)
		}
	})

	t.Run("ListTreesByObjectID returns error on API failure", func(t *testing.T) {
		treesAPI := &mockTreesAPI{
			listTreesFunc: func(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
				return nil, errors.New("network error")
			},
		}
		c := &Client{
			obsv:        observability.NewNoopExporters(),
			treesClient: treesAPI,
		}
		_, err := c.ListTreesByObjectID(context.Background(), 1, "abc123", "some/path")
		if err == nil {
			t.Fatal("expected error but got none")
		}
		if !strings.Contains(err.Error(), "failed to list trees by object ID") {
			t.Fatalf("unexpected error message: %v", err)
		}
	})

	t.Run("ListTreesByObjectID returns empty list for no entries", func(t *testing.T) {
		treesAPI := &mockTreesAPI{
			listTreesFunc: func(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
				return &trees.ListTreesResponse{
					Entries: []*types.TreeEntry{},
				}, nil
			},
		}
		c := &Client{
			obsv:        observability.NewNoopExporters(),
			treesClient: treesAPI,
		}
		objs, err := c.ListTreesByObjectID(context.Background(), 1, "abc123", "empty/")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(objs) != 0 {
			t.Fatalf("expected empty list, got %d objects", len(objs))
		}
	})

	t.Run("ListTreesByObjectID passes OID to spokes request", func(t *testing.T) {
		expectedOID := "def456abc123def456abc123def456abc123def4"
		var capturedReq *trees.ListTreesRequest
		treesAPI := &mockTreesAPI{
			listTreesFunc: func(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
				capturedReq = req
				return &trees.ListTreesResponse{
					Entries: []*types.TreeEntry{},
				}, nil
			},
		}
		c := &Client{
			obsv:        observability.NewNoopExporters(),
			treesClient: treesAPI,
		}
		_, err := c.ListTreesByObjectID(context.Background(), 1, expectedOID, "some/path")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if capturedReq == nil {
			t.Fatal("expected request to be captured")
		}
		selector := capturedReq.GetTreeishAndPathSelector()
		if selector == nil {
			t.Fatal("expected TreeishAndPathSelector in request")
		}
		gotOID := selector.GetTreeish().GetOid().GetId()
		if gotOID != expectedOID {
			t.Fatalf("expected OID %s in request, got %s", expectedOID, gotOID)
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

	t.Run("ReadBlobsByPaths returns empty slice for empty paths", func(t *testing.T) {
		c := &Client{
			obsv:          observability.NewNoopExporters(),
			objectsClient: &mockObjectsAPI{},
		}
		results, err := c.ReadBlobsByPaths(context.Background(), 1, "abc123", []string{})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(results) != 0 {
			t.Fatalf("expected empty results, got %v", results)
		}
	})

	t.Run("ReadBlobsByPaths returns blob contents for valid paths", func(t *testing.T) {
		objectsAPI := &mockObjectsAPI{
			readObjectsFunc: func(ctx context.Context, req *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error) {
				// Return mock blob objects for each selector
				return &objects.ReadObjectsResponse{
					Objects: []*objects.Object{
						{Entity: &objects.Object_BlobObject{BlobObject: &objects.BlobObject{Data: []byte("content1")}}},
						{Entity: &objects.Object_BlobObject{BlobObject: &objects.BlobObject{Data: []byte("content2")}}},
					},
				}, nil
			},
		}
		c := &Client{
			obsv:          observability.NewNoopExporters(),
			objectsClient: objectsAPI,
		}
		results, err := c.ReadBlobsByPaths(context.Background(), 1, "abc123", []string{"path1", "path2"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(results) != 2 {
			t.Fatalf("expected 2 results, got %d", len(results))
		}
		if string(results[0]) != "content1" {
			t.Fatalf("expected content1, got %s", string(results[0]))
		}
		if string(results[1]) != "content2" {
			t.Fatalf("expected content2, got %s", string(results[1]))
		}
	})

	t.Run("ReadBlobsByPaths handles nil objects for missing paths", func(t *testing.T) {
		objectsAPI := &mockObjectsAPI{
			readObjectsFunc: func(ctx context.Context, req *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error) {
				// Return mix of found and not found (nil)
				return &objects.ReadObjectsResponse{
					Objects: []*objects.Object{
						{Entity: &objects.Object_BlobObject{BlobObject: &objects.BlobObject{Data: []byte("content1")}}},
						nil, // missing path
						{Entity: &objects.Object_BlobObject{BlobObject: &objects.BlobObject{Data: []byte("content3")}}},
					},
				}, nil
			},
		}
		c := &Client{
			obsv:          observability.NewNoopExporters(),
			objectsClient: objectsAPI,
		}
		results, err := c.ReadBlobsByPaths(context.Background(), 1, "abc123", []string{"path1", "path2", "path3"})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(results) != 3 {
			t.Fatalf("expected 3 results, got %d", len(results))
		}
		if string(results[0]) != "content1" {
			t.Fatalf("expected content1, got %s", string(results[0]))
		}
		if results[1] != nil {
			t.Fatalf("expected nil for missing path, got %v", results[1])
		}
		if string(results[2]) != "content3" {
			t.Fatalf("expected content3, got %s", string(results[2]))
		}
	})

	t.Run("ReadBlobsByPaths returns error on API failure", func(t *testing.T) {
		objectsAPI := &mockObjectsAPI{
			readObjectsFunc: func(ctx context.Context, req *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error) {
				return nil, errors.New("network error")
			},
		}
		c := &Client{
			obsv:          observability.NewNoopExporters(),
			objectsClient: objectsAPI,
		}
		_, err := c.ReadBlobsByPaths(context.Background(), 1, "abc123", []string{"path1"})
		if err == nil {
			t.Fatal("expected error but got none")
		}
		if !strings.Contains(err.Error(), "failed to batch read blobs") {
			t.Fatalf("unexpected error message: %v", err)
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
				name:        "pull request ref",
				ref:         "refs/pull/123/head",
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

	t.Run("GetObjectIDForRef returns ErrRefNotFound when ref cannot be resolved", func(t *testing.T) {
		mockRef := &mockReferencesAPI{
			MockResolveReferences: func(ctx context.Context, req *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error) {
				return &references.ResolveReferencesResponse{
					Items: []*references.ResolveReferencesResponse_ResolvedReference{
						{Oid: types.NewObjectID("")},
					},
				}, nil
			},
		}

		c := &Client{
			obsv:             observability.NewNoopExporters(),
			referencesClient: mockRef,
		}

		_, err := c.GetObjectIDForRef(context.Background(), 1, "nonexistent-branch")
		if !errors.Is(err, ErrRefNotFound) {
			t.Fatalf("expected ErrRefNotFound, got %v", err)
		}
	})

	t.Run("resolveBranchOrTagRef returns ErrRefNotFound for empty resolution", func(t *testing.T) {
		mockRef := &mockReferencesAPI{
			MockResolveReferences: func(ctx context.Context, req *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error) {
				return &references.ResolveReferencesResponse{
					Items: []*references.ResolveReferencesResponse_ResolvedReference{},
				}, nil
			},
		}

		c := &Client{
			obsv:             observability.NewNoopExporters(),
			referencesClient: mockRef,
		}

		_, err := c.resolveBranchOrTagRef(context.Background(), 1, "refs/heads/nonexistent")
		if !errors.Is(err, ErrRefNotFound) {
			t.Fatalf("expected ErrRefNotFound, got %v", err)
		}
	})

	t.Run("resolveBranchOrTagRef returns ErrRefNotFound for empty OID", func(t *testing.T) {
		mockRef := &mockReferencesAPI{
			MockResolveReferences: func(ctx context.Context, req *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error) {
				return &references.ResolveReferencesResponse{
					Items: []*references.ResolveReferencesResponse_ResolvedReference{
						{Oid: types.NewObjectID("")},
					},
				}, nil
			},
		}

		c := &Client{
			obsv:             observability.NewNoopExporters(),
			referencesClient: mockRef,
		}

		_, err := c.resolveBranchOrTagRef(context.Background(), 1, "refs/heads/nonexistent")
		if !errors.Is(err, ErrRefNotFound) {
			t.Fatalf("expected ErrRefNotFound, got %v", err)
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
				name:        "pull request ref",
				ref:         "refs/pull/42/head",
				expectError: false,
				expectedOID: "sha-0123456789101112131415161718192021222324252627",
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

	t.Run("GetObjectIDForRef resolves pull request ref without incorrect prefixing", func(t *testing.T) {
		expectedRef := "refs/pull/123/head"
		mockRef := &mockReferencesAPI{
			MockResolveReferences: func(ctx context.Context, req *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error) {
				gotRef := string(req.References[0].Name)
				if gotRef != expectedRef {
					return &references.ResolveReferencesResponse{
						Items: []*references.ResolveReferencesResponse_ResolvedReference{
							{Oid: types.NewObjectID("")},
						},
					}, nil
				}
				return &references.ResolveReferencesResponse{
					Items: []*references.ResolveReferencesResponse_ResolvedReference{
						{Oid: types.NewObjectID("abc123def456abc123def456abc123def456abc1")},
					},
				}, nil
			},
		}

		c := &Client{
			obsv:             observability.NewNoopExporters(),
			referencesClient: mockRef,
		}

		oid, err := c.GetObjectIDForRef(context.Background(), 1, expectedRef)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if oid != "abc123def456abc123def456abc123def456abc1" {
			t.Fatalf("expected abc123def456abc123def456abc123def456abc1, got %s", oid)
		}
	})

	t.Run("committishToOID resolves pull request ref without incorrect prefixing", func(t *testing.T) {
		expectedRef := "refs/pull/42/head"
		mockRef := &mockReferencesAPI{
			MockResolveReferences: func(ctx context.Context, req *references.ResolveReferencesRequest) (*references.ResolveReferencesResponse, error) {
				gotRef := string(req.References[0].Name)
				if gotRef != expectedRef {
					return &references.ResolveReferencesResponse{
						Items: []*references.ResolveReferencesResponse_ResolvedReference{
							{Oid: types.NewObjectID("")},
						},
					}, nil
				}
				return &references.ResolveReferencesResponse{
					Items: []*references.ResolveReferencesResponse_ResolvedReference{
						{Oid: types.NewObjectID("def456abc123def456abc123def456abc123def4")},
					},
				}, nil
			},
		}

		c := &Client{
			obsv:             observability.NewNoopExporters(),
			referencesClient: mockRef,
		}

		oid, err := c.committishToOID(context.Background(), 1, expectedRef)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if oid != "def456abc123def456abc123def456abc123def4" {
			t.Fatalf("expected def456abc123def456abc123def456abc123def4, got %s", oid)
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
func (m *mockTreesAPI) ListTrees(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
	if m.listTreesFunc != nil {
		return m.listTreesFunc(ctx, req)
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

type mockObjectsAPI struct {
	objects.ObjectsAPI

	readObjectsFunc func(context.Context, *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error)
}

// ReadObjects reads multiple objects by their selectors.
func (m *mockObjectsAPI) ReadObjects(ctx context.Context, req *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error) {
	if m.readObjectsFunc != nil {
		return m.readObjectsFunc(ctx, req)
	}

	return nil, errors.New("not implemented")
}

func TestEmbedGpgsigHeader(t *testing.T) {
	t.Run("embeds signature into commit content", func(t *testing.T) {
		commitContent := "tree abc123\nparent def456\nauthor Test <test@test.com> 1234567890 +0000\ncommitter Test <test@test.com> 1234567890 +0000\n\nInitial plan\n"
		signature := "-----BEGIN PGP SIGNATURE-----\nline1\nline2\n-----END PGP SIGNATURE-----"

		result := embedGpgsigHeader(commitContent, signature)

		// Should contain the gpgsig header
		if !strings.Contains(result, "gpgsig -----BEGIN PGP SIGNATURE-----") {
			t.Errorf("expected gpgsig header, got:\n%s", result)
		}

		// Continuation lines should be space-prefixed
		if !strings.Contains(result, "\n line1\n line2\n -----END PGP SIGNATURE-----") {
			t.Errorf("expected space-prefixed continuation lines, got:\n%s", result)
		}

		// Message should still be present after the headers
		if !strings.Contains(result, "\n\nInitial plan\n") {
			t.Errorf("expected message body preserved, got:\n%s", result)
		}

		// Original headers should still be present
		if !strings.Contains(result, "tree abc123\n") {
			t.Errorf("expected original headers preserved, got:\n%s", result)
		}
	})
}
