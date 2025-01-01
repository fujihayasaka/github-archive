// This file contains a mock implementation of the gitaccess.Client interface
// that is used for tests and standalone mode. It sidesteps the hard dependency
// on Spokes that would otherwise make it cumbersome to run the service for local
// development.
package mock

import (
	"context"
	"math/rand"
	"time"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
)

type mockGitaccessClient struct {
	minimumDelay time.Duration
	maximumDelay time.Duration
}

// ExpectedSHA is expected latest SHA for our gitaccess mock
const ExpectedSHA = gitaccess.SHA("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")

// HistoricalSHAs Represents a history of commits for a repository in reverse topological order
// (newest to oldest).
// They happen to also be in reverse alphabetical order to make debugging easier.
// These are returned, in this order, by the gitaccess mock.
var HistoricalSHAs = []gitaccess.SHA{
	ExpectedSHA,
	"dddddddddddddddddddddddddddddddddddddddd",
	"cccccccccccccccccccccccccccccccccccccccc",
	"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
}

func (m *mockGitaccessClient) delay() {
	if m.maximumDelay > 0 {
		time.Sleep(m.minimumDelay + time.Duration(rand.Int63n(int64(m.maximumDelay-m.minimumDelay))))
	}
}

// GetDefaultBranch - given a GitHub repository ID, obtain the default branch
// name, usable as an input (Git revision) to GetRecentCommits or GetHEADCommit.
func (m *mockGitaccessClient) GetDefaultBranch(ctx context.Context, gitHubRepoID uint64) (string, error) {
	m.delay()
	return "main", nil
}

// GetHEADCommit - Obtain the latest commit SHA for the given GitHub repository ID
// and optional branch name (default branch is assumed if absent.)
func (m *mockGitaccessClient) GetHEADCommit(ctx context.Context, gitHubRepoID uint64, optionalBranchName ...string) (gitaccess.SHA, error) {
	return gitaccess.SHA(""), nil
}

// GetRecentCommits - given:
// - a GitHub repository ID
// - a nonzero number of latest commit SHAs to fetch
// - an (optional) branch name
//
// Obtain the most recent N commit SHAs as an ordered array
// (most recent to oldest) starting at HEAD, or return an error.
// If no branch name is specified, we fall back to the default branch.
func (m *mockGitaccessClient) GetRecentCommits(ctx context.Context, gitHubRepoID uint64, numCommits uint, optionalBranchName ...string) ([]gitaccess.SHA, error) {
	m.delay()
	return HistoricalSHAs, nil
}

// NewClient - create a new mock gitaccess.Client. delayMs is the minimum amount of time that mock requests will take to return.
// The maximum delay is automatically 3x the minimum delay.
func NewClient(delayMs int) gitaccess.Client {
	return &mockGitaccessClient{
		minimumDelay: time.Duration(delayMs) * time.Millisecond,
		maximumDelay: time.Duration(delayMs*3) * time.Millisecond,
	}
}
