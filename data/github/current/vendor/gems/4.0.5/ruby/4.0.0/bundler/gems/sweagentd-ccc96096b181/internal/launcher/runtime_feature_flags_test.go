package launcher

import (
	"context"
	"slices"
	"testing"

	vexi "github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/sweagentd/internal/sweagentd"
)

// testFFClient is a minimal mock implementing featureflags.Client for this package's tests.
// It only cares about repo-scoped enablement since the memory feature flags are repo-only.
type testFFClient struct {
	repoFlags map[int64]map[string]bool // repoID -> flag -> enabled
}

func newTestFFClient() *testFFClient { return &testFFClient{repoFlags: map[int64]map[string]bool{}} }

// --- Interface implementation (methods unused in these tests return false) ---
func (t *testFFClient) IsEnabled(ctx context.Context, featureFlagName string, _ ...vexi.Actor) bool {
	return false
}
func (t *testFFClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return false
}
func (t *testFFClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	if flags, ok := t.repoFlags[repoID]; ok {
		return flags[featureFlagName]
	}
	return false
}
func (t *testFFClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	return t.IsEnabledForRepo(ctx, featureFlagName, repoID)
}
func (t *testFFClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	return t.IsEnabledForRepo(ctx, featureFlagName, actors.GetRepositoryID())
}
func (t *testFFClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	return t.IsEnabledForRepo(ctx, featureFlagName, actors.GetRepositoryID())
}
func (t *testFFClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return false
}
func (t *testFFClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return false
}

func (t *testFFClient) enableRepoFlag(repoID int64, flag string) {
	if _, ok := t.repoFlags[repoID]; !ok {
		t.repoFlags[repoID] = map[string]bool{}
	}
	t.repoFlags[repoID][flag] = true
}

// This test is guarding against accidental drift of the staffship of
// the memory feature, by ensuring that the memory feature flags are only
// enabled for repos in the GitHub org, and not for personal repos owned by
// staff members for the duration of the staffship.
func TestGetFeatureFlags_MemoryFlagsGitHubOrgVsPersonal(t *testing.T) {
	ctx := context.Background()
	const (
		githubOrgRepoID  int64 = 101
		personalRepoID   int64 = 202
		githubOrgOwnerID int64 = 11
		personalOwnerID  int64 = 22
		actorID          int64 = 33
	)

	// Collect the memory (repo-scoped) flags under test from the source variable to avoid drift.
	memoryFlags := slices.Clone(runtimeFeatureFlags.enabledViaRepo)
	if len(memoryFlags) == 0 {
		t.Fatal("expected repo-scoped memory feature flags to be defined")
	}

	mock := newTestFFClient()
	// Enable all memory flags for the GitHub org repo only.
	for _, f := range memoryFlags {
		mock.enableRepoFlag(githubOrgRepoID, f)
	}

	t.Run("github org repo includes memory flags", func(t *testing.T) {
		opts := LaunchAgentOpts{
			GitHubRepoID:      githubOrgRepoID,
			GitHubRepoOwnerID: githubOrgOwnerID,
			ActorID:           actorID,
			GitHubRepoOwner:   "github",
			GitHubRepoName:    "example",
		}

		flags := getFeatureFlags(ctx, mock, &opts)
		for _, want := range memoryFlags {
			if !slices.Contains(flags, want) {
				t.Fatalf("expected memory flag %q to be present for github org repo; got %v", want, flags)
			}
		}
	})

	t.Run("personal staff repo excludes memory flags", func(t *testing.T) {
		opts := LaunchAgentOpts{
			GitHubRepoID:      personalRepoID,
			GitHubRepoOwnerID: personalOwnerID,
			ActorID:           actorID,
			GitHubRepoOwner:   "staff-user",
			GitHubRepoName:    "personal-repo",
		}

		flags := getFeatureFlags(ctx, mock, &opts)
		for _, forbidden := range memoryFlags {
			if slices.Contains(flags, forbidden) {
				t.Fatalf("did not expect memory flag %q for personal staff repo; got %v", forbidden, flags)
			}
		}
	})
}
