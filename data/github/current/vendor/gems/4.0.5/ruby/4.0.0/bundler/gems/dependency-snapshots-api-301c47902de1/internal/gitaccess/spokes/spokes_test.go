package spokes

import (
	"context"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/references"
	"github.com/github/spokes-proto/gen/go/v1/trees"
	"github.com/github/spokes-proto/gen/go/v1/types"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// ============================================================
// Mock Twirp Client implementations for unit testing spokesClient
// ============================================================

// mockBlobsClient is a mock implementation of blobs.BlobsAPI
type mockBlobsClient struct {
	mock.Mock
}

func (m *mockBlobsClient) GetBlobContents(ctx context.Context, req *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*blobs.GetBlobContentsResponse), args.Error(1)
}

func (m *mockBlobsClient) ListChangedBlobs(ctx context.Context, req *blobs.ListChangedBlobsRequest) (*blobs.ListChangedBlobsResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*blobs.ListChangedBlobsResponse), args.Error(1)
}

func (m *mockBlobsClient) ListReachableBlobs(ctx context.Context, req *blobs.ListReachableBlobsRequest) (*blobs.ListReachableBlobsResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*blobs.ListReachableBlobsResponse), args.Error(1)
}

func (m *mockBlobsClient) ListBlobsAtTips(ctx context.Context, req *blobs.ListBlobsAtTipsRequest) (*blobs.ListBlobsAtTipsResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*blobs.ListBlobsAtTipsResponse), args.Error(1)
}

func (m *mockBlobsClient) ListBlobOrigin(ctx context.Context, req *blobs.ListBlobOriginRequest) (*blobs.ListBlobOriginResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*blobs.ListBlobOriginResponse), args.Error(1)
}

// mockTreesClient is a mock implementation of trees.TreesAPI
type mockTreesClient struct {
	mock.Mock
}

func (m *mockTreesClient) ListTrees(ctx context.Context, req *trees.ListTreesRequest) (*trees.ListTreesResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*trees.ListTreesResponse), args.Error(1)
}

func (m *mockTreesClient) CompareTrees(ctx context.Context, req *trees.CompareTreesRequest) (*trees.CompareTreesResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*trees.CompareTreesResponse), args.Error(1)
}

// mockObjectsClient is a mock implementation of objects.ObjectsAPI
type mockObjectsClient struct {
	mock.Mock
}

func (m *mockObjectsClient) ResolveObject(ctx context.Context, req *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*objects.ResolveObjectResponse), args.Error(1)
}

// mockReferencesClient is a mock implementation of references.ReferencesAPI
type mockReferencesClient struct {
	mock.Mock
}

func (m *mockReferencesClient) ListReferences(ctx context.Context, req *references.ListReferencesRequest) (*references.ListReferencesResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*references.ListReferencesResponse), args.Error(1)
}

func (m *mockReferencesClient) GetDefaultBranch(ctx context.Context, req *references.GetDefaultBranchRequest) (*references.GetDefaultBranchResponse, error) {
	args := m.Called(ctx, req)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*references.GetDefaultBranchResponse), args.Error(1)
}

// newTestSpokesClient creates a spokesClient with mocked Twirp clients for unit testing
func newTestSpokesClient(
	blobsClient blobs.BlobsAPI,
	treesClient trees.TreesAPI,
	objectsClient objects.ObjectsAPI,
	refsClient references.ReferencesAPI,
) *spokesClient {
	return &spokesClient{
		URL:           "http://test-spokes",
		blobsClient:   blobsClient,
		treesClient:   treesClient,
		objectsClient: objectsClient,
		refsClient:    refsClient,
	}
}

// ============================================================
// Unit tests for spokesClient with mocked Twirp clients
// ============================================================

func TestSpokesClient_GetBlobByPath(t *testing.T) {
	t.Run("resolves ref and fetches blob by path and commit", func(t *testing.T) {
		ctx := context.Background()
		var repoID uint64 = 12345
		ref := []byte("refs/heads/main")
		path := "package.json"
		commitOID := "abc123def456"
		expectedContents := []byte(`{"name": "test"}`)
		var expectedSize uint64 = 16

		mockObjects := &mockObjectsClient{}
		mockBlobs := &mockBlobsClient{}

		// Expect ResolveObject to be called with the ref
		// Use mock.Anything for ctx because it gets decorated with tracing spans
		mockObjects.On("ResolveObject", mock.Anything, mock.MatchedBy(func(req *objects.ResolveObjectRequest) bool {
			return req.GetRepository().GetId() == repoID &&
				string(req.GetObjectName().GetName()) == string(ref)
		})).Return(&objects.ResolveObjectResponse{
			Oid: &types.ObjectID{Id: commitOID},
		}, nil)

		// Expect GetBlobContents to be called with the commit and path
		mockBlobs.On("GetBlobContents", mock.Anything, mock.MatchedBy(func(req *blobs.GetBlobContentsRequest) bool {
			return req.GetRepository().GetId() == repoID
		})).Return(&blobs.GetBlobContentsResponse{
			Contents: expectedContents,
			Size:     expectedSize,
		}, nil)

		client := newTestSpokesClient(mockBlobs, nil, mockObjects, nil)

		contents, size, err := client.GetBlobByPath(ctx, repoID, ref, path)
		require.NoError(t, err)
		require.Equal(t, expectedContents, contents)
		require.Equal(t, expectedSize, size)

		mockObjects.AssertExpectations(t)
		mockBlobs.AssertExpectations(t)
	})

	t.Run("uses HEAD when ref is empty", func(t *testing.T) {
		ctx := context.Background()
		var repoID uint64 = 12345
		var emptyRef []byte = nil
		path := "README.md"
		commitOID := "head123"
		expectedContents := []byte("# Hello")
		var expectedSize uint64 = 7

		mockObjects := &mockObjectsClient{}
		mockBlobs := &mockBlobsClient{}

		// Expect ResolveObject to be called with "HEAD" when ref is empty
		mockObjects.On("ResolveObject", mock.Anything, mock.MatchedBy(func(req *objects.ResolveObjectRequest) bool {
			return req.GetRepository().GetId() == repoID &&
				string(req.GetObjectName().GetName()) == "HEAD"
		})).Return(&objects.ResolveObjectResponse{
			Oid: &types.ObjectID{Id: commitOID},
		}, nil)

		mockBlobs.On("GetBlobContents", mock.Anything, mock.MatchedBy(func(req *blobs.GetBlobContentsRequest) bool {
			return req.GetRepository().GetId() == repoID
		})).Return(&blobs.GetBlobContentsResponse{
			Contents: expectedContents,
			Size:     expectedSize,
		}, nil)

		client := newTestSpokesClient(mockBlobs, nil, mockObjects, nil)

		contents, size, err := client.GetBlobByPath(ctx, repoID, emptyRef, path)
		require.NoError(t, err)
		require.Equal(t, expectedContents, contents)
		require.Equal(t, expectedSize, size)

		mockObjects.AssertExpectations(t)
		mockBlobs.AssertExpectations(t)
	})

	t.Run("returns error for invalid repo ID", func(t *testing.T) {
		ctx := context.Background()
		client := newTestSpokesClient(nil, nil, nil, nil)

		_, _, err := client.GetBlobByPath(ctx, 0, []byte("ref"), "path")
		require.Error(t, err)
		require.Contains(t, err.Error(), "valid repository ID required")
	})
}

func TestSpokesClient_GetBlobByOID(t *testing.T) {
	t.Run("fetches blob by OID", func(t *testing.T) {
		ctx := context.Background()
		var repoID uint64 = 12345
		blobOID := "blob123abc"
		expectedContents := []byte("file contents")
		var expectedSize uint64 = 13

		mockBlobs := &mockBlobsClient{}
		mockBlobs.On("GetBlobContents", mock.Anything, mock.MatchedBy(func(req *blobs.GetBlobContentsRequest) bool {
			return req.GetRepository().GetId() == repoID
		})).Return(&blobs.GetBlobContentsResponse{
			Contents: expectedContents,
			Size:     expectedSize,
		}, nil)

		client := newTestSpokesClient(mockBlobs, nil, nil, nil)

		contents, size, err := client.GetBlobByOID(ctx, repoID, blobOID)
		require.NoError(t, err)
		require.Equal(t, expectedContents, contents)
		require.Equal(t, expectedSize, size)

		mockBlobs.AssertExpectations(t)
	})
}

func TestSpokesClient_ResolveRef(t *testing.T) {
	t.Run("resolves ref to object ID", func(t *testing.T) {
		ctx := context.Background()
		var repoID uint64 = 12345
		ref := "refs/heads/feature"
		expectedOID := "commit123sha"

		mockObjects := &mockObjectsClient{}
		mockObjects.On("ResolveObject", mock.Anything, mock.MatchedBy(func(req *objects.ResolveObjectRequest) bool {
			return req.GetRepository().GetId() == repoID &&
				string(req.GetObjectName().GetName()) == ref
		})).Return(&objects.ResolveObjectResponse{
			Oid: &types.ObjectID{Id: expectedOID},
		}, nil)

		client := newTestSpokesClient(nil, nil, mockObjects, nil)

		oid, err := client.ResolveRef(ctx, repoID, ref)
		require.NoError(t, err)
		require.Equal(t, expectedOID, oid.GetId())

		mockObjects.AssertExpectations(t)
	})
}

func TestSpokesClient_ListTreeByRef(t *testing.T) {
	t.Run("lists tree entries by ref", func(t *testing.T) {
		ctx := context.Background()
		var repoID uint64 = 12345
		ref := []byte("refs/heads/main")
		expectedEntries := []*types.TreeEntry{
			{Path: &types.Path{Name: []byte("file1.txt")}},
			{Path: &types.Path{Name: []byte("dir/file2.txt")}},
		}

		mockTrees := &mockTreesClient{}
		mockTrees.On("ListTrees", mock.Anything, mock.MatchedBy(func(req *trees.ListTreesRequest) bool {
			return req.GetRepository().GetId() == repoID
		})).Return(&trees.ListTreesResponse{
			Entries:    expectedEntries,
			NextCursor: nil, // no pagination
		}, nil)

		client := newTestSpokesClient(nil, mockTrees, nil, nil)

		entries, err := client.ListTreeByRef(ctx, repoID, ref)
		require.NoError(t, err)
		require.Equal(t, expectedEntries, entries)

		mockTrees.AssertExpectations(t)
	})
}

func TestSpokesClient_CompareTrees(t *testing.T) {
	t.Run("compares two trees", func(t *testing.T) {
		ctx := context.Background()
		var repoID uint64 = 12345
		beforeCommit := "abc123"
		afterCommit := "def456"
		expectedDiff := []*types.DiffEntry{
			{
				Status:      types.DiffEntry_STATUS_ADDITION,
				Destination: &types.Path{Name: []byte("new-file.txt")},
			},
			{
				Status: types.DiffEntry_STATUS_DELETION,
				Source: &types.Path{Name: []byte("old-file.txt")},
			},
		}

		mockTrees := &mockTreesClient{}
		mockTrees.On("CompareTrees", mock.Anything, mock.MatchedBy(func(req *trees.CompareTreesRequest) bool {
			return req.GetRepository().GetId() == repoID
		})).Return(&trees.CompareTreesResponse{
			Entries:    expectedDiff,
			NextCursor: nil,
		}, nil)

		client := newTestSpokesClient(nil, mockTrees, nil, nil)

		diff, err := client.CompareTrees(ctx, repoID, beforeCommit, afterCommit)
		require.NoError(t, err)
		require.Equal(t, expectedDiff, diff)

		mockTrees.AssertExpectations(t)
	})
}

func TestSpokesClient_GetDefaultBranch(t *testing.T) {
	t.Run("gets default branch name", func(t *testing.T) {
		ctx := context.Background()
		var repoID uint64 = 12345
		expectedBranch := "main"

		mockRefs := &mockReferencesClient{}
		mockRefs.On("GetDefaultBranch", mock.Anything, mock.MatchedBy(func(req *references.GetDefaultBranchRequest) bool {
			return req.GetRepository().GetId() == repoID
		})).Return(&references.GetDefaultBranchResponse{
			Reference: &types.Reference{Name: []byte("refs/heads/main")},
		}, nil)

		client := newTestSpokesClient(nil, nil, nil, mockRefs)

		branch, err := client.GetDefaultBranch(ctx, repoID)
		require.NoError(t, err)
		require.Equal(t, expectedBranch, branch)

		mockRefs.AssertExpectations(t)
	})
}

// ============================================================
// Original tests using MockedGitAccessClient (kept for interface verification)
// ============================================================

func TestGetHEADCommit(t *testing.T) {
	var expectedRepoID uint64 = 12345
	expectedSHA := gitaccess.SHA("0c8cd17c3777efd4c0b1cd29333ed1c97ceafb0b")
	branch := "main"
	gitClient := CreateMockGitAccess(t, expectedRepoID, []gitaccess.SHA{expectedSHA}, branch)

	headCommitSHA, err := gitClient.GetHEADCommit(context.Background(), expectedRepoID)
	require.NoError(t, err)
	require.Equal(t, expectedSHA, headCommitSHA)
}

func TestGetDefaultBranch(t *testing.T) {
	var expectedRepoID uint64 = 12345
	expectedSHA := gitaccess.SHA("0c8cd17c3777efd4c0b1cd29333ed1c97ceafb0b")
	expectedBranch := "official/trunk"
	gitClient := CreateMockGitAccess(t, expectedRepoID, []gitaccess.SHA{expectedSHA}, expectedBranch)

	gotBranch, err := gitClient.GetDefaultBranch(context.Background(), expectedRepoID)
	require.NoError(t, err)
	require.Equal(t, expectedBranch, gotBranch)
}

func TestGetRecentCommits(t *testing.T) {
	var expectedRepoID uint64 = 12345
	expectedSHAs := []gitaccess.SHA{
		gitaccess.SHA("d6a046bd25306981451c09c28e04be1125b84791"),
		gitaccess.SHA("74065c8c5d5fcc87b50fa1cce3b379cf1587e131"),
		gitaccess.SHA("f8e7b666e1aba2fcd743d242bf46e99e75086e06"),
		gitaccess.SHA("c710cbf7372358de8caa7cde001513ed2f76e23b"),
	}
	branch := "main"
	gitClient := CreateMockGitAccess(t, expectedRepoID, expectedSHAs, branch)

	numCommits := uint(len(expectedSHAs))
	gotSHAs, err := gitClient.GetRecentCommits(context.Background(), expectedRepoID, numCommits, branch)
	require.NoError(t, err)
	require.EqualValues(t, expectedSHAs, gotSHAs)
}

func TestMockedGitAccessClient_ListTreeByRef(t *testing.T) {
	var repoID uint64 = 12345
	ref := []byte("refs/heads/main")
	expectedEntries := []*types.TreeEntry{
		{Path: &types.Path{Name: []byte("file1.txt")}},
		{Path: &types.Path{Name: []byte("file2.txt")}},
	}

	mock := &MockedGitAccessClient{}
	mock.On("ListTreeByRef", context.Background(), repoID, ref).Return(expectedEntries, nil)

	entries, err := mock.ListTreeByRef(context.Background(), repoID, ref)
	require.NoError(t, err)
	require.Equal(t, expectedEntries, entries)
}

func TestMockedGitAccessClient_ListTreeByCommit(t *testing.T) {
	var repoID uint64 = 12345
	commitOID := "abc123"
	expectedEntries := []*types.TreeEntry{
		{Path: &types.Path{Name: []byte("file1.txt")}},
	}

	mock := &MockedGitAccessClient{}
	mock.On("ListTreeByCommit", context.Background(), repoID, commitOID).Return(expectedEntries, nil)

	entries, err := mock.ListTreeByCommit(context.Background(), repoID, commitOID)
	require.NoError(t, err)
	require.Equal(t, expectedEntries, entries)
}

func TestMockedGitAccessClient_ListRootTreeByCommit(t *testing.T) {
	var repoID uint64 = 12345
	commitOID := "abc123"
	expectedEntries := []*types.TreeEntry{
		{Path: &types.Path{Name: []byte("root-file.txt")}},
	}

	mock := &MockedGitAccessClient{}
	mock.On("ListRootTreeByCommit", context.Background(), repoID, commitOID).Return(expectedEntries, nil)

	entries, err := mock.ListRootTreeByCommit(context.Background(), repoID, commitOID)
	require.NoError(t, err)
	require.Equal(t, expectedEntries, entries)
}

func TestMockedGitAccessClient_CompareTrees(t *testing.T) {
	var repoID uint64 = 12345
	beforeCommit := "abc123"
	afterCommit := "def456"
	expectedEntries := []*types.DiffEntry{
		{
			Status:      types.DiffEntry_STATUS_ADDITION,
			Destination: &types.Path{Name: []byte("new-file.txt")},
		},
	}

	mock := &MockedGitAccessClient{}
	mock.On("CompareTrees", context.Background(), repoID, beforeCommit, afterCommit).Return(expectedEntries, nil)

	entries, err := mock.CompareTrees(context.Background(), repoID, beforeCommit, afterCommit)
	require.NoError(t, err)
	require.Equal(t, expectedEntries, entries)
}

func TestMockedGitAccessClient_GetBlobByOID(t *testing.T) {
	var repoID uint64 = 12345
	blobOID := "blob123"
	expectedContents := []byte("file contents")
	var expectedSize uint64 = 13

	mock := &MockedGitAccessClient{}
	mock.On("GetBlobByOID", context.Background(), repoID, blobOID).Return(expectedContents, expectedSize, nil)

	contents, size, err := mock.GetBlobByOID(context.Background(), repoID, blobOID)
	require.NoError(t, err)
	require.Equal(t, expectedContents, contents)
	require.Equal(t, expectedSize, size)
}

func TestMockedGitAccessClient_GetBlobByPath(t *testing.T) {
	var repoID uint64 = 12345
	ref := []byte("refs/heads/main")
	path := "file.txt"
	expectedContents := []byte("file contents")
	var expectedSize uint64 = 13

	mock := &MockedGitAccessClient{}
	mock.On("GetBlobByPath", context.Background(), repoID, ref, path).Return(expectedContents, expectedSize, nil)

	contents, size, err := mock.GetBlobByPath(context.Background(), repoID, ref, path)
	require.NoError(t, err)
	require.Equal(t, expectedContents, contents)
	require.Equal(t, expectedSize, size)
}

func TestMockedGitAccessClient_GetBlobByPathAndCommit(t *testing.T) {
	var repoID uint64 = 12345
	commit := "abc123"
	path := "file.txt"
	expectedContents := []byte("file contents at commit")
	var expectedSize uint64 = 24

	mock := &MockedGitAccessClient{}
	mock.On("GetBlobByPathAndCommit", context.Background(), repoID, commit, path).Return(expectedContents, expectedSize, nil)

	contents, size, err := mock.GetBlobByPathAndCommit(context.Background(), repoID, commit, path)
	require.NoError(t, err)
	require.Equal(t, expectedContents, contents)
	require.Equal(t, expectedSize, size)
}

func TestMockedGitAccessClient_ResolveRef(t *testing.T) {
	var repoID uint64 = 12345
	ref := "refs/heads/feature-branch"
	expectedOID := &types.ObjectID{Id: "branch-commit-sha"}

	mock := &MockedGitAccessClient{}
	mock.On("ResolveRef", context.Background(), repoID, ref).Return(expectedOID, nil)

	oid, err := mock.ResolveRef(context.Background(), repoID, ref)
	require.NoError(t, err)
	require.Equal(t, expectedOID, oid)
}
