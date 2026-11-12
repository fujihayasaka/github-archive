package mock

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/spokes-proto/gen/go/v1/types"
)

// MockGitClient is a lightweight gitaccess.Client test double with optional function hooks per method.
// Any method without a provided hook returns zero values.
type MockGitClient struct {
	GetDefaultBranchFn       func(ctx context.Context, repoID uint64) (string, error)
	GetHEADCommitFn          func(ctx context.Context, repoID uint64, optionalBranchName ...string) (gitaccess.SHA, error)
	GetRecentCommitsFn       func(ctx context.Context, repoID uint64, numCommits uint, optionalBranchName ...string) ([]gitaccess.SHA, error)
	ListTreeByRefFn          func(ctx context.Context, repoID uint64, ref []byte) ([]*types.TreeEntry, error)
	ListTreeByCommitFn       func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error)
	ListRootTreeByCommitFn   func(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error)
	CompareTreesFn           func(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error)
	GetBlobByOIDFn           func(ctx context.Context, repoID uint64, blobOID string) ([]byte, uint64, error)
	GetBlobByPathFn          func(ctx context.Context, repoID uint64, ref []byte, path string) ([]byte, uint64, error)
	GetBlobByPathAndCommitFn func(ctx context.Context, repoID uint64, commit string, path string) ([]byte, uint64, error)
	ResolveRefFn             func(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error)
}

func (m *MockGitClient) GetDefaultBranch(ctx context.Context, repoID uint64) (string, error) {
	if m.GetDefaultBranchFn != nil {
		return m.GetDefaultBranchFn(ctx, repoID)
	}
	return "", nil
}

func (m *MockGitClient) GetHEADCommit(ctx context.Context, repoID uint64, optionalBranchName ...string) (gitaccess.SHA, error) {
	if m.GetHEADCommitFn != nil {
		return m.GetHEADCommitFn(ctx, repoID, optionalBranchName...)
	}
	return "", nil
}

func (m *MockGitClient) GetRecentCommits(ctx context.Context, repoID uint64, numCommits uint, optionalBranchName ...string) ([]gitaccess.SHA, error) {
	if m.GetRecentCommitsFn != nil {
		return m.GetRecentCommitsFn(ctx, repoID, numCommits, optionalBranchName...)
	}
	return nil, nil
}

func (m *MockGitClient) ListTreeByRef(ctx context.Context, repoID uint64, ref []byte) ([]*types.TreeEntry, error) {
	if m.ListTreeByRefFn != nil {
		return m.ListTreeByRefFn(ctx, repoID, ref)
	}
	return nil, nil
}

func (m *MockGitClient) ListTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	if m.ListTreeByCommitFn != nil {
		return m.ListTreeByCommitFn(ctx, repoID, commitOID)
	}
	return nil, nil
}

func (m *MockGitClient) ListRootTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	if m.ListRootTreeByCommitFn != nil {
		return m.ListRootTreeByCommitFn(ctx, repoID, commitOID)
	}
	return nil, nil
}

func (m *MockGitClient) CompareTrees(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
	if m.CompareTreesFn != nil {
		return m.CompareTreesFn(ctx, repoID, beforeCommit, afterCommit)
	}
	return nil, nil
}

func (m *MockGitClient) GetBlobByOID(ctx context.Context, repoID uint64, blobOID string) ([]byte, uint64, error) {
	if m.GetBlobByOIDFn != nil {
		return m.GetBlobByOIDFn(ctx, repoID, blobOID)
	}
	return nil, 0, nil
}

func (m *MockGitClient) GetBlobByPath(ctx context.Context, repoID uint64, ref []byte, path string) ([]byte, uint64, error) {
	if m.GetBlobByPathFn != nil {
		return m.GetBlobByPathFn(ctx, repoID, ref, path)
	}
	return nil, 0, nil
}

func (m *MockGitClient) GetBlobByPathAndCommit(ctx context.Context, repoID uint64, commit string, path string) ([]byte, uint64, error) {
	if m.GetBlobByPathAndCommitFn != nil {
		return m.GetBlobByPathAndCommitFn(ctx, repoID, commit, path)
	}
	return nil, 0, nil
}

func (m *MockGitClient) ResolveRef(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
	if m.ResolveRefFn != nil {
		return m.ResolveRefFn(ctx, repoID, ref)
	}
	return nil, nil
}

var _ gitaccess.Client = (*MockGitClient)(nil)
