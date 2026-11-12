package spokes

import (
	"context"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"

	"github.com/stretchr/testify/require"
)

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
