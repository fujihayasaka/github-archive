package facade

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/gitaccess/mock"
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

func (fc *facadeClient) shouldMock(repositoryID uint64) bool {
	return fc.devStandalone
}
