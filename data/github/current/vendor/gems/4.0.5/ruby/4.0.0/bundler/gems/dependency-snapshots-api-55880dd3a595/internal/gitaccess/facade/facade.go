package facade

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/gitaccess/mock"
	"github.com/github/spokes-proto/gen/go/v1/types"
)

var mockClient = mock.NewClient(50)

type facadeClient struct {
	realClient    gitaccess.Client
	devStandalone bool
}

func NewFacade(client gitaccess.Client, devStandalone bool) gitaccess.Client {
	return &facadeClient{realClient: client, devStandalone: devStandalone}
}

func (fc *facadeClient) GetDefaultBranch(ctx context.Context, repositoryID uint64) (string, error) {
	if fc.shouldMock(repositoryID) {
		return mockClient.GetDefaultBranch(ctx, repositoryID)
	} else {
		return fc.realClient.GetDefaultBranch(ctx, repositoryID)
	}
}

func (fc *facadeClient) GetHEADCommit(ctx context.Context, repositoryID uint64, optionalBranchName ...string) (gitaccess.SHA, error) {
	if fc.shouldMock(repositoryID) {
		return mockClient.GetHEADCommit(ctx, repositoryID, optionalBranchName...)
	} else {
		return fc.realClient.GetHEADCommit(ctx, repositoryID, optionalBranchName...)
	}
}

func (fc *facadeClient) GetRecentCommits(ctx context.Context, repositoryID uint64, numCommits uint, optionalBranchName ...string) ([]gitaccess.SHA, error) {
	if fc.shouldMock(repositoryID) {
		return mockClient.GetRecentCommits(ctx, repositoryID, numCommits, optionalBranchName...)
	} else {
		return fc.realClient.GetRecentCommits(ctx, repositoryID, numCommits, optionalBranchName...)
	}
}

func (fc *facadeClient) ListTreeByRef(ctx context.Context, repoID uint64, ref []byte) ([]*types.TreeEntry, error) {
	if fc.shouldMock(repoID) {
		return mockClient.ListTreeByRef(ctx, repoID, ref)
	} else {
		return fc.realClient.ListTreeByRef(ctx, repoID, ref)
	}
}

func (fc *facadeClient) ListTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	if fc.shouldMock(repoID) {
		return mockClient.ListTreeByCommit(ctx, repoID, commitOID)
	} else {
		return fc.realClient.ListTreeByCommit(ctx, repoID, commitOID)
	}
}

func (fc *facadeClient) ListRootTreeByCommit(ctx context.Context, repoID uint64, commitOID string) ([]*types.TreeEntry, error) {
	if fc.shouldMock(repoID) {
		return mockClient.ListRootTreeByCommit(ctx, repoID, commitOID)
	} else {
		return fc.realClient.ListRootTreeByCommit(ctx, repoID, commitOID)
	}
}

func (fc *facadeClient) CompareTrees(ctx context.Context, repoID uint64, beforeCommit, afterCommit string) ([]*types.DiffEntry, error) {
	if fc.shouldMock(repoID) {
		return mockClient.CompareTrees(ctx, repoID, beforeCommit, afterCommit)
	} else {
		return fc.realClient.CompareTrees(ctx, repoID, beforeCommit, afterCommit)
	}
}

func (fc *facadeClient) GetBlobByOID(ctx context.Context, repoID uint64, blobOID string) ([]byte, uint64, error) {
	if fc.shouldMock(repoID) {
		return mockClient.GetBlobByOID(ctx, repoID, blobOID)
	} else {
		return fc.realClient.GetBlobByOID(ctx, repoID, blobOID)
	}
}

func (fc *facadeClient) GetBlobByPath(ctx context.Context, repoID uint64, ref []byte, path string) ([]byte, uint64, error) {
	if fc.shouldMock(repoID) {
		return mockClient.GetBlobByPath(ctx, repoID, ref, path)
	} else {
		return fc.realClient.GetBlobByPath(ctx, repoID, ref, path)
	}
}

func (fc *facadeClient) GetBlobByPathAndCommit(ctx context.Context, repoID uint64, commit string, path string) ([]byte, uint64, error) {
	if fc.shouldMock(repoID) {
		return mockClient.GetBlobByPathAndCommit(ctx, repoID, commit, path)
	} else {
		return fc.realClient.GetBlobByPathAndCommit(ctx, repoID, commit, path)
	}
}

func (fc *facadeClient) ResolveRef(ctx context.Context, repoID uint64, ref string) (*types.ObjectID, error) {
	if fc.shouldMock(repoID) {
		return mockClient.ResolveRef(ctx, repoID, ref)
	} else {
		return fc.realClient.ResolveRef(ctx, repoID, ref)
	}
}

func (fc *facadeClient) shouldMock(repositoryID uint64) bool {
	return fc.devStandalone
}
