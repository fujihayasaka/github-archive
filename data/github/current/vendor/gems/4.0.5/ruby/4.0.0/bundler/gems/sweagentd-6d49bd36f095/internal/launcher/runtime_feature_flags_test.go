package launcher

import (
	"context"
	"slices"
	"testing"

	vexi "github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/sweagentd/internal/sweagentd"
)

// testFFClient is a minimal mock implementing featureflags.Client for this package's tests.
type testFFClient struct {
	repoFlags map[int64]map[string]bool // repoID -> flag -> enabled
	anyFlags  map[string]bool           // flag -> enabled (for enabledViaAny / user/org scope)
}

func newTestFFClient() *testFFClient {
	return &testFFClient{
		repoFlags: map[int64]map[string]bool{},
		anyFlags:  map[string]bool{},
	}
}

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
func (t *testFFClient) IsEnabledForOrganization(ctx context.Context, featureFlagName string, orgID int64) bool {
	return t.anyFlags[featureFlagName]
}
func (t *testFFClient) IsEnabledForOwner(ctx context.Context, featureFlagName string, ownerID int64) bool {
	return t.anyFlags[featureFlagName]
}
func (t *testFFClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	return t.IsEnabledForRepo(ctx, featureFlagName, actors.GetRepositoryID())
}
func (t *testFFClient) IsEnabledForRepoOrOwnerWithDefaultValue(ctx context.Context, featureFlagName string, _ bool, actors sweagentd.Repository) bool {
	return t.IsEnabledForRepoOrOwner(ctx, featureFlagName, actors)
}
func (t *testFFClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	if t.anyFlags[featureFlagName] {
		return true
	}
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

func (t *testFFClient) enableAnyFlag(flag string) {
	t.anyFlags[flag] = true
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

		flags, err := getFeatureFlags(ctx, mock, &opts, true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
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

		flags, err := getFeatureFlags(ctx, mock, &opts, true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		for _, forbidden := range memoryFlags {
			if slices.Contains(flags, forbidden) {
				t.Fatalf("did not expect memory flag %q for personal staff repo; got %v", forbidden, flags)
			}
		}
	})
}

func TestGetFeatureFlags_MemoryDisabledFlagViaAny(t *testing.T) {
	ctx := context.Background()
	const (
		repoID  int64 = 301
		ownerID int64 = 41
		actorID int64 = 51
	)

	const memoryDisabledFlag = "copilot-feature-agentic-memory-disabled"

	// Verify the flag is in the enabledViaAny list.
	if !slices.Contains(runtimeFeatureFlags.enabledViaAny, memoryDisabledFlag) {
		t.Fatalf("expected %q to be in enabledViaAny", memoryDisabledFlag)
	}

	opts := LaunchAgentOpts{
		GitHubRepoID:      repoID,
		GitHubRepoOwnerID: ownerID,
		ActorID:           actorID,
		GitHubRepoOwner:   "some-org",
		GitHubRepoName:    "some-repo",
	}

	t.Run("includes memory disabled flag when enabled via user/org/repo", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableAnyFlag(memoryDisabledFlag)

		flags, _ := getFeatureFlags(ctx, mock, &opts, true)
		if !slices.Contains(flags, memoryDisabledFlag) {
			t.Fatalf("expected %q in flags; got %v", memoryDisabledFlag, flags)
		}
	})

	t.Run("excludes memory disabled flag when not enabled", func(t *testing.T) {
		mock := newTestFFClient()

		flags, _ := getFeatureFlags(ctx, mock, &opts, true)
		if slices.Contains(flags, memoryDisabledFlag) {
			t.Fatalf("did not expect %q in flags; got %v", memoryDisabledFlag, flags)
		}
	})
}

func TestGetFeatureFlags_MCPPermissionGateCopilotOnly(t *testing.T) {
	ctx := context.Background()
	const flag = "copilot_swe_agent_mcp_permission_gate"

	if !slices.Contains(runtimeFeatureFlags.enabledViaAnyCopilotOnly, flag) {
		t.Fatalf("expected %q to be in enabledViaAnyCopilotOnly", flag)
	}
	if slices.Contains(runtimeFeatureFlags.enabledViaAny, flag) {
		t.Fatalf("did not expect %q in enabledViaAny (would forward to 3p agents)", flag)
	}

	opts := LaunchAgentOpts{
		GitHubRepoID:      777,
		GitHubRepoOwnerID: 88,
		ActorID:           99,
	}

	t.Run("included when agent is the Copilot coding agent", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableAnyFlag(flag)
		flags, err := getFeatureFlags(ctx, mock, &opts, true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !slices.Contains(flags, flag) {
			t.Fatalf("expected %q in flags for CCA; got %v", flag, flags)
		}
	})

	t.Run("excluded when agent is not the Copilot coding agent", func(t *testing.T) {
		mock := newTestFFClient()
		mock.enableAnyFlag(flag)
		flags, err := getFeatureFlags(ctx, mock, &opts, false)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if slices.Contains(flags, flag) {
			t.Fatalf("did not expect %q in flags for non-CCA agent; got %v", flag, flags)
		}
	})
}
