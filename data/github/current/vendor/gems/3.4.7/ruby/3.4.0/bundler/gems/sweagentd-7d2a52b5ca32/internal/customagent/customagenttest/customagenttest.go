// Package customagenttest provides utilities for testing custom agents with predefined configurations.
package customagenttest

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// MakeRepoProviderFromGH sets up a NoopClient to return a repository with ID 1 for any GetRepository call.
func MakeRepoProviderFromGH(t *testing.T, gh *github.NoopClient) github.ClientInterface {
	t.Helper()

	gh.MockGetRepository = func(ctx context.Context, owner, repo string) (*gg.Repository, error) {
		return &gg.Repository{
			ID: gg.Ptr(int64(1)),
		}, nil
	}

	return gh
}

// MakeSpokes creates a GitDataProvider with the specified agents.
// The agents map should have keys as agent names and values as their corresponding file contents.
func MakeSpokes(t *testing.T, agents map[string]string) sweagentd.Spokes {
	t.Helper()
	// Use "" for the SHA to get the default value in MakeSpokesWithCommitSHA
	return MakeSpokesWithCommitSHA(t, agents, "")
}

// MakeSpokesWithCommitSHA creates a GitDataProvider with the specified agents and commit SHA.
// The agents map should have keys as agent names and values as their corresponding file contents.
func MakeSpokesWithCommitSHA(t *testing.T, agents map[string]string, commitSHA string) sweagentd.Spokes {
	t.Helper()
	return MakeSpokesWithRepoAndCommitSHA(t, agents, commitSHA, 0)
}

// MakeSpokesWithRepoAndCommitSHA creates a GitDataProvider with the specified agents and commit SHA.
// The agents map should have keys as agent names and values as their corresponding file contents.
func MakeSpokesWithRepoAndCommitSHA(t *testing.T, agents map[string]string, commitSHA string, repoID uint64) sweagentd.Spokes {
	t.Helper()

	// Only add a default blob if nil is provided for agents arg
	fileBlobs := []spokestest.ClientOption{}
	if agents == nil {
		contents := "---\nkey: value\n---\nthis is a prompt"
		fileBlobs = append(fileBlobs, spokestest.ClientWithCommitSHAAndBlob("*", commitSHA, []byte(contents)))
	}

	for path, content := range agents {
		blob := spokestest.ClientWithCommitSHAAndBlob(filepath.Join(customagent.Directory, path+customagent.Extension), commitSHA, []byte(content))
		fileBlobs = append(fileBlobs, blob)
	}

	return spokestest.NewClientWithRepoAndCommitSHA(t, repoID, commitSHA, fileBlobs...)
}
