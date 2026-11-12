package spokes

import (
	"context"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// CreateMockGitAccess - a mock that meets the `gitaccess.Client` contract.
// Inputs:
//   - targetRepoID:             the GitHub repo ID we expect the mock APIs to be called against
//   - expectedLatestCommitSHAs: a nonempty list of commit SHAs ordered from most to least recent
//     that will be returned (in part or whole) by the mocked APIs
//
// method return values from, returns a mock gitaccess.Client
func CreateMockGitAccess(t *testing.T, targetRepoID uint64, expectedLatestCommitSHAs []gitaccess.SHA, branchName string) *MockedGitAccessClient {
	t.Helper()

	require.NotEmpty(t, expectedLatestCommitSHAs, "required array of commit SHAs to return is empty")
	headSHA := expectedLatestCommitSHAs[0]
	numCommits := uint(len(expectedLatestCommitSHAs))

	mock := &MockedGitAccessClient{}
	mock.On("GetHEADCommit", context.Background(), targetRepoID).Return(headSHA, nil)
	mock.On("GetDefaultBranch", context.Background(), targetRepoID).Return(branchName, nil)
	mock.On("GetRecentCommits", context.Background(), targetRepoID, numCommits, branchName).Return(expectedLatestCommitSHAs, nil)

	return mock
}

// MockedGitAccessClient - quick and dirty HEAD commit SHA mock for storage tests
type MockedGitAccessClient struct {
	mock.Mock
}

func (mgac *MockedGitAccessClient) GetDefaultBranch(ctx context.Context, repoID uint64) (string, error) {
	args := mgac.Called(ctx, repoID)
	return args.Get(0).(string), args.Error(1)
}

func (mgac *MockedGitAccessClient) GetHEADCommit(ctx context.Context, repoID uint64, optionalBranchName ...string) (gitaccess.SHA, error) {
	var args mock.Arguments
	if len(optionalBranchName) > 0 {
		args = mgac.Called(ctx, repoID, optionalBranchName[0])
	} else {
		args = mgac.Called(ctx, repoID)
	}
	return args.Get(0).(gitaccess.SHA), args.Error(1)
}

func (mgac *MockedGitAccessClient) GetRecentCommits(ctx context.Context, repoID uint64, numCommits uint, optionalBranchName ...string) ([]gitaccess.SHA, error) {
	var args mock.Arguments
	if len(optionalBranchName) > 0 {
		args = mgac.Called(ctx, repoID, numCommits, optionalBranchName[0])
	} else {
		args = mgac.Called(ctx, repoID, numCommits)
	}

	return args.Get(0).([]gitaccess.SHA), args.Error(1)
}

func (mgac *MockedGitAccessClient) ListTreeByRef(ctx context.Context, repoID uint64, ref []byte) ([]*types.TreeEntry, error) {
	args := mgac.Called(ctx, repoID, ref)
	return args.Get(0).([]*types.TreeEntry), args.Error(1)
}

func (mgac *MockedGitAccessClient) ListTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	args := mgac.Called(ctx, repoID, commitOID)
	return args.Get(0).([]*types.TreeEntry), args.Error(1)
}

func (mgac *MockedGitAccessClient) ListRootTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	args := mgac.Called(ctx, repoID, commitOID)
	return args.Get(0).([]*types.TreeEntry), args.Error(1)
}

func (mgac *MockedGitAccessClient) CompareTrees(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
	args := mgac.Called(ctx, repoID, beforeCommit, afterCommit)
	return args.Get(0).([]*types.DiffEntry), args.Error(1)
}

func (mgac *MockedGitAccessClient) GetBlobByOID(ctx context.Context, repoID uint64, blobOID string) ([]byte, uint64, error) {
	args := mgac.Called(ctx, repoID, blobOID)
	return args.Get(0).([]byte), args.Get(1).(uint64), args.Error(2)
}

func (mgac *MockedGitAccessClient) GetBlobByPath(ctx context.Context, repoID uint64, ref []byte, path string) ([]byte, uint64, error) {
	args := mgac.Called(ctx, repoID, ref, path)
	return args.Get(0).([]byte), args.Get(1).(uint64), args.Error(2)
}

func (mgac *MockedGitAccessClient) GetBlobByPathAndCommit(ctx context.Context, repoID uint64, commit string, path string) ([]byte, uint64, error) {
	args := mgac.Called(ctx, repoID, commit, path)
	return args.Get(0).([]byte), args.Get(1).(uint64), args.Error(2)
}

func (mgac *MockedGitAccessClient) ResolveRef(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
	args := mgac.Called(ctx, repoID, ref)
	return args.Get(0).(*types.ObjectID), args.Error(1)
}
