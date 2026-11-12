package jobservice

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MockBranchRuleChecker implements the BranchRuleChecker interface for testing
type MockBranchRuleChecker struct {
	MockGetActionsPermissions        func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error)
	MockListBranchProtectionRules    func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error)
	MockListRepositoryRulesForBranch func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error)
}

func (m *MockBranchRuleChecker) GetActionsPermissions(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
	if m.MockGetActionsPermissions != nil {
		return m.MockGetActionsPermissions(ctx, ownerLogin, repoName)
	}
	return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(true)}, nil
}

func (m *MockBranchRuleChecker) ListBranchProtectionRules(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
	if m.MockListBranchProtectionRules != nil {
		return m.MockListBranchProtectionRules(ctx, repoNodeID)
	}
	return &[]github.GQLBranchProtectionRule{}, nil
}

func (m *MockBranchRuleChecker) ListRepositoryRulesForBranch(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
	if m.MockListRepositoryRulesForBranch != nil {
		return m.MockListRepositoryRulesForBranch(ctx, ownerLogin, repoName, branchName, excludeRulesetIDs)
	}
	return &gg.BranchRules{}, nil
}

func TestCheckRules(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(nil)

	t.Run("no rules when copilot branch doesn't exist and actions are enabled", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(true)}, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		require.NotNil(t, result)
		assert.Empty(t, result.Rules)
		assert.False(t, result.HasBranchProtectionRules)
		assert.False(t, result.HasRepositoryRules)
	})

	t.Run("detects copilot branch exists", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				results := make([]bool, len(refNames))
				for i, ref := range refNames {
					results[i] = ref == "refs/heads/"+agenticapp.CopilotBranchPrefix
				}

				return results, nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		require.NotNil(t, result)
		assert.Contains(t, result.Rules, fmt.Sprintf(github.RuleAgentPrefixBranchExists, agenticapp.CopilotBranchPrefix))
	})

	t.Run("no longer checks for actions disabled", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(false)}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		require.NotNil(t, result)
		// Even with actions disabled, the rule should NOT be added since the feature flag is fully enabled
		assert.NotContains(t, result.Rules, github.RuleRequireGitHubActions)
	})

	t.Run("detects repository rules - creation blocked", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(true)}, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				// Return rules with Creation populated (non-empty slice)
				return &gg.BranchRules{
					Creation: []*gg.BranchRuleMetadata{{}},
				}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		require.NotNil(t, result)
		assert.True(t, result.HasRepositoryRules)
		assert.False(t, result.HasBranchProtectionRules)
		assert.Greater(t, len(result.Rules), 0)
	})

	t.Run("detects branch protection rules", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(true)}, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{
					{
						Pattern:         "test-*",
						BlocksCreations: true,
					},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		require.NotNil(t, result)
		assert.False(t, result.HasRepositoryRules)
		assert.True(t, result.HasBranchProtectionRules)
		assert.Greater(t, len(result.Rules), 0)
	})

	t.Run("handles errors gracefully and continues checking", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return nil, errors.New("check branch error")
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return nil, errors.New("permissions error")
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return nil, errors.New("repo rules error")
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return nil, errors.New("branch protection error")
			},
		}

		// Should not panic despite all errors
		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		require.NotNil(t, result)
		// No rules should be detected due to errors
		assert.Empty(t, result.Rules)
	})

	t.Run("combines multiple rules", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				results := make([]bool, len(refNames))
				for i, ref := range refNames {
					results[i] = ref == "refs/heads/"+agenticapp.CopilotBranchPrefix
				}

				return results, nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(false)}, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					Creation: []*gg.BranchRuleMetadata{{}},
				}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{
					{
						Pattern:         "test-*",
						BlocksCreations: true,
					},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		require.NotNil(t, result)
		assert.True(t, result.HasRepositoryRules)
		assert.True(t, result.HasBranchProtectionRules)
		// Should have copilot branch, repo rules, and branch protection rules (but NOT actions rule)
		assert.GreaterOrEqual(t, len(result.Rules), 2)
		assert.Contains(t, result.Rules, fmt.Sprintf(github.RuleAgentPrefixBranchExists, agenticapp.CopilotBranchPrefix))
		assert.NotContains(t, result.Rules, github.RuleRequireGitHubActions)
	})

	t.Run("skips rule checks when Copilot is bypass actor", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		ffWithBypassCheck := featureflags.NewNoopClient(map[string]bool{})

		// Configure the bypass actor response directly
		twirp.NoopSweagentdAPI.MockIsBypassActor = func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
			return &sweagentdTwirp.IsBypassActorResponse{
				IsBypassActor: true,
				Rulesets: []*sweagentdTwirp.BypassableRuleset{
					{
						RulesetId:   123,
						RulesetName: "Test Ruleset",
						BypassMode:  sweagentdTwirp.BypassMode_BYPASS_MODE_ANY,
					},
				},
			}, nil
		}

		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))

		svc := New(obsv, ffWithBypassCheck, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)
		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(true)}, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				// Since Copilot is bypass actor for ruleset 123, it should be excluded
				// The real implementation would filter it out, so we return empty rules
				return &gg.BranchRules{}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				// Return rules that would normally block, but should be ignored
				return &[]github.GQLBranchProtectionRule{
					{
						Pattern:         "copilot-*",
						BlocksCreations: true,
					},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)

		// Even though we have rules that would block, they should not be reported
		// because Copilot is a bypass actor
		require.Empty(t, result.Rules)
		require.False(t, result.HasBranchProtectionRules)
		require.False(t, result.HasRepositoryRules)
	})

	t.Run("checks rules when Copilot is not bypass actor", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		ffWithBypassCheck := featureflags.NewNoopClient(map[string]bool{})

		// Configure Copilot as NOT a bypass actor
		twirp.NoopSweagentdAPI.MockIsBypassActor = func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
			return &sweagentdTwirp.IsBypassActorResponse{
				IsBypassActor: false,
				Rulesets:      []*sweagentdTwirp.BypassableRuleset{},
			}, nil
		}

		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))

		svc := New(obsv, ffWithBypassCheck, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(true)}, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					Creation: []*gg.BranchRuleMetadata{{}},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)

		// Rules should be reported since Copilot is not a bypass actor
		require.NotEmpty(t, result.Rules)
		require.True(t, result.HasRepositoryRules)
	})

	t.Run("continues checking when bypass actor check fails", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		ffWithBypassCheck := featureflags.NewNoopClient(map[string]bool{})

		// Configure the mock to return an error
		twirp.NoopSweagentdAPI.MockIsBypassActor = func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
			return nil, errors.New("API error")
		}

		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))

		svc := New(obsv, ffWithBypassCheck, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
				return &gg.ActionsPermissionsRepository{Enabled: gg.Ptr(true)}, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					Creation: []*gg.BranchRuleMetadata{{}},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)

		// Should continue checking rules even if bypass actor check fails
		require.NotEmpty(t, result.Rules)
		require.True(t, result.HasRepositoryRules)
	})

	t.Run("only blocks rules from non-bypassable rulesets when Copilot is partial bypass actor", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		ffWithBypassCheck := featureflags.NewNoopClient(map[string]bool{})

		// Configure the bypass actor response - Copilot can bypass ruleset 100, but NOT ruleset 200
		twirp.NoopSweagentdAPI.MockIsBypassActor = func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
			return &sweagentdTwirp.IsBypassActorResponse{
				IsBypassActor: true,
				Rulesets: []*sweagentdTwirp.BypassableRuleset{
					{
						RulesetId:   100,
						RulesetName: "Bypassable Ruleset",
						BypassMode:  sweagentdTwirp.BypassMode_BYPASS_MODE_ANY,
					},
				},
			}, nil
		}
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}))

		svc := New(obsv, ffWithBypassCheck, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				// Return rules from BOTH bypassable (100) and non-bypassable (200) rulesets
				return &gg.BranchRules{
					Creation: []*gg.BranchRuleMetadata{
						{RulesetID: 100}, // This should be skipped (Copilot can bypass)
						{RulesetID: 200}, // This should block (Copilot cannot bypass)
					},
					RequiredSignatures: []*gg.BranchRuleMetadata{
						{RulesetID: 100}, // This should be skipped
					},
				}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)

		// Should only report rules from ruleset 200 (non-bypassable)
		// Rules from ruleset 100 should be filtered out
		require.NotEmpty(t, result.Rules, "Should have rules from non-bypassable ruleset 200")
		require.True(t, result.HasRepositoryRules)
		require.True(t, result.IsBypassActor, "Should recognize Copilot as bypass actor")

		// Should contain the creation rule (from ruleset 200), but not signatures (from ruleset 100)
		assert.Contains(t, result.Rules, "Branch creation is blocked due to repository rules")
	})

	t.Run("require signatures does not block and sets RequireSignedCommits", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					RequiredSignatures: []*gg.BranchRuleMetadata{{RulesetID: 1}},
				}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{
					{
						Pattern:                  "test-*",
						RequiresCommitSignatures: true,
					},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		assert.Empty(t, result.Rules, "signing rules should not block")
		assert.False(t, result.HasRepositoryRules)
		assert.False(t, result.HasBranchProtectionRules)
		assert.True(t, result.RequireSignedCommits, "should detect signing requirement")
	})

	t.Run("RequireSignedCommits is false when no signing rules exist", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{
					{
						Pattern:                  "test-*",
						RequiresCommitSignatures: false,
					},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		assert.Empty(t, result.Rules)
		assert.False(t, result.RequireSignedCommits, "should be false when no signing rules exist")
	})

	t.Run("RequireSignedCommits is true when only repository rulesets require signing", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					RequiredSignatures: []*gg.BranchRuleMetadata{{RulesetID: 1}},
				}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		assert.Empty(t, result.Rules)
		assert.True(t, result.RequireSignedCommits, "should be true when only repo rulesets require signing")
	})

	t.Run("RequireSignedCommits is true when only branch protection requires signing", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		mockChecker := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{
					{
						Pattern:                  "test-*",
						RequiresCommitSignatures: true,
					},
				}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agenticapptest.NewTestCopilot(t), job, "test-owner", "test-repo", job.BranchName, true)
		assert.Empty(t, result.Rules)
		assert.True(t, result.RequireSignedCommits, "should be true when only branch protection requires signing")
	})

	t.Run("commit author email pattern uses agent commit email not committer email", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))

		agent := agenticapptest.NewTestCopilot(t)

		// Use a committer email that differs from the agent commit email so
		// we can verify the correct one is matched against the pattern.
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "GitHub", "noreply@github.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		// Create a regex that matches the agent's commit email but NOT the
		// web-flow committer email (noreply@github.com).
		agentEmail := agent.CommitEmail()
		mockChecker := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					CommitAuthorEmailPattern: []*gg.PatternBranchRule{
						{
							BranchRuleMetadata: gg.BranchRuleMetadata{RulesetID: 1},
							Parameters: gg.PatternRuleParameters{
								Operator: gg.PatternRuleOperatorRegex,
								Pattern:  "^" + regexp.QuoteMeta(agentEmail) + "$",
							},
						},
					},
				}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agent, job, "test-owner", "test-repo", job.BranchName, true)
		assert.Empty(t, result.Rules, "commit author email pattern should match against the agent's commit email, not the web-flow committer email")
	})

	t.Run("commit author email pattern blocks when agent email does not match", func(t *testing.T) {
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))

		agent := agenticapptest.NewTestCopilot(t)

		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "GitHub", "noreply@github.com", spokes, agenticapptest.NewTestProvider(t), nil)

		job := &jobs.Job{
			RepoNodeID: "node-id",
			BranchName: "test-branch",
			RepoID:     123,
		}

		// Create a regex that does NOT match the agent's commit email.
		mockChecker := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					CommitAuthorEmailPattern: []*gg.PatternBranchRule{
						{
							BranchRuleMetadata: gg.BranchRuleMetadata{RulesetID: 1},
							Parameters: gg.PatternRuleParameters{
								Operator: gg.PatternRuleOperatorRegex,
								Pattern:  "^no-match@example\\.com$",
							},
						},
					},
				}, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				return &[]github.GQLBranchProtectionRule{}, nil
			},
		}

		result := svc.CheckRules(ctx, mockChecker, agent, job, "test-owner", "test-repo", job.BranchName, true)
		assert.NotEmpty(t, result.Rules, "should block when agent email does not match commit author email pattern")
		assert.True(t, result.HasRepositoryRules)
	})
}

func TestBranchRulePatterns(t *testing.T) {
	ctx := context.Background()
	repoOwner := "test-owner"
	repoName := "test-repo"
	branchName := "copilot/feature"
	excludeRulesetIDs := []uint64{10, 20}

	t.Run("returns message for first branch name pattern and forwards args", func(t *testing.T) {
		var gotOwner string
		var gotRepo string
		var gotBranch string
		var gotExclude []uint64

		gh := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoNameArg, branchNameArg string, excludeRulesetIDsArg []uint64) (*gg.BranchRules, error) {
				gotOwner = ownerLogin
				gotRepo = repoNameArg
				gotBranch = branchNameArg
				gotExclude = excludeRulesetIDsArg

				return &gg.BranchRules{
					BranchNamePattern: []*gg.PatternBranchRule{
						{
							Parameters: gg.PatternRuleParameters{
								Operator: gg.PatternRuleOperatorStartsWith,
								Pattern:  "copilot/",
							},
						},
						{
							Parameters: gg.PatternRuleParameters{
								Operator: gg.PatternRuleOperatorEndsWith,
								Pattern:  "ignored-second-rule",
							},
						},
					},
				}, nil
			},
		}

		svc := &Service{}
		patterns, err := svc.BranchRulePatterns(ctx, gh, repoOwner, repoName, branchName, excludeRulesetIDs)

		require.NoError(t, err)
		require.Equal(t, repoOwner, gotOwner)
		require.Equal(t, repoName, gotRepo)
		require.Equal(t, branchName, gotBranch)
		require.Equal(t, excludeRulesetIDs, gotExclude)
		require.Equal(t, "must starts with copilot/", patterns)
	})

	t.Run("returns regex negation message for branch pattern", func(t *testing.T) {
		gh := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoNameArg, branchNameArg string, excludeRulesetIDsArg []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					BranchNamePattern: []*gg.PatternBranchRule{
						{
							Parameters: gg.PatternRuleParameters{
								Operator: gg.PatternRuleOperatorRegex,
								Pattern:  "^copilot/.+$",
								Negate:   gg.Ptr(true),
							},
						},
					},
				}, nil
			},
		}

		svc := &Service{}
		patterns, err := svc.BranchRulePatterns(ctx, gh, repoOwner, repoName, branchName, nil)

		require.NoError(t, err)
		require.Equal(t, "must not match the pattern ^copilot/.+$", patterns)
	})

	t.Run("returns empty when branch name pattern is absent", func(t *testing.T) {
		gh := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoNameArg, branchNameArg string, excludeRulesetIDsArg []uint64) (*gg.BranchRules, error) {
				return &gg.BranchRules{
					CommitMessagePattern: []*gg.PatternBranchRule{
						{
							Parameters: gg.PatternRuleParameters{
								Operator: gg.PatternRuleOperatorContains,
								Pattern:  "[signed]",
							},
						},
					},
				}, nil
			},
		}

		svc := &Service{}
		patterns, err := svc.BranchRulePatterns(ctx, gh, repoOwner, repoName, branchName, nil)

		require.NoError(t, err)
		require.Empty(t, patterns)
	})

	t.Run("returns empty string when branch rules response is nil", func(t *testing.T) {
		gh := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoNameArg, branchNameArg string, excludeRulesetIDsArg []uint64) (*gg.BranchRules, error) {
				return nil, nil
			},
		}

		svc := &Service{}
		patterns, err := svc.BranchRulePatterns(ctx, gh, repoOwner, repoName, branchName, nil)

		require.NoError(t, err)
		require.Empty(t, patterns)
	})

	t.Run("returns wrapped error when list repository rules fails", func(t *testing.T) {
		gh := &MockBranchRuleChecker{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoNameArg, branchNameArg string, excludeRulesetIDsArg []uint64) (*gg.BranchRules, error) {
				return nil, errors.New("boom")
			},
		}

		svc := &Service{}
		patterns, err := svc.BranchRulePatterns(ctx, gh, repoOwner, repoName, branchName, nil)

		require.Error(t, err)
		require.Empty(t, patterns)
		require.ErrorContains(t, err, "failed to list repository rules for branch")
		require.ErrorContains(t, err, "boom")
	})
}

func TestValidatePatternRule(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	obsv := observability.NewNoopExporters()
	pattern := "copilot/"
	rule := &gg.PatternBranchRule{
		Parameters: gg.PatternRuleParameters{
			Operator: gg.PatternRuleOperatorStartsWith,
			Pattern:  pattern,
		},
	}
	job := &jobs.Job{
		ActorID: 456,
		RepoID:  123,
	}

	tests := []struct {
		name          string
		value         string
		flags         map[string]bool
		expectedValid bool
		expected      string
	}{
		{
			name:          "passes when value matches pattern",
			value:         "copilot/test-branch",
			flags:         nil,
			expectedValid: true,
			expected:      "",
		},
		{
			name:     "omits pattern and value when feature flag is disabled",
			value:    "feature/test-branch",
			flags:    nil,
			expected: "Branch name restrictions apply (must start with ***)",
		},
		{
			name:  "includes pattern and value when feature flag is enabled",
			value: "feature/test-branch",
			flags: map[string]bool{
				featureflags.CopilotSWEAgentPatternRuleFailureDetails: true,
			},
			expected: "Branch name restrictions apply (\"feature/test-branch\" must start with \"copilot/\")",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc := &Service{ffs: featureflags.NewNoopClient(tt.flags)}

			isValid, message := svc.validatePatternRule(ctx, obsv.Logger, job, rule, tt.value, "branch name", github.RuleBranchNamePattern)

			require.Equal(t, tt.expectedValid, isValid)
			assert.Equal(t, tt.expected, message)
		})
	}
}
