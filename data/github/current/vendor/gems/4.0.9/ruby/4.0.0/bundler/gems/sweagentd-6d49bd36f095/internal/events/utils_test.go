package events

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/automations"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func TestShouldIgnorePRCommentOrReview(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	handler, _, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)

	t.Run("ignores closed PR", func(t *testing.T) {
		pr := EventPullRequest()
		pr.IsOpen = false

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorWriter())

		require.NoError(t, err)
		require.True(t, ignore, "Should ignore comments on closed PRs")
	})

	t.Run("ignores comments from Copilot", func(t *testing.T) {
		pr := EventPullRequest()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorCopilot())

		require.NoError(t, err)
		require.True(t, ignore, "Should ignore comments from Copilot")
	})

	t.Run("ignores comments from bot users", func(t *testing.T) {
		pr := EventPullRequest()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorBot())

		require.NoError(t, err)
		require.True(t, ignore, "Should ignore comments from bots")
	})

	t.Run("ignores comments from users without write access", func(t *testing.T) {
		gh := ghFactory.NewClient("test-token")

		hasPermissions, err := handler.PRCommentOrReviewAuthorHasPushPermissions(ctx, gh, EventRepository(), EventActorReader())
		require.NoError(t, err)
		require.False(t, hasPermissions, "User should not have write access")
	})

	t.Run("actorHasPushPermissionsForRepository returns false for read actor", func(t *testing.T) {
		gh := ghFactory.NewClient("test-token")

		hasPermissions, err := handler.actorHasPushPermissionsForRepository(ctx, gh, EventRepository().ID, EventActorReader().Login)
		require.NoError(t, err)
		require.False(t, hasPermissions)
	})

	t.Run("actorHasPushPermissionsForRepository returns true for write actor", func(t *testing.T) {
		gh := ghFactory.NewClient("test-token")

		hasPermissions, err := handler.actorHasPushPermissionsForRepository(ctx, gh, EventRepository().ID, EventActorWriter().Login)
		require.NoError(t, err)
		require.True(t, hasPermissions)
	})

	t.Run("processes comments from users with write access", func(t *testing.T) {
		pr := EventPullRequest()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorAdmin())

		require.NoError(t, err)
		require.False(t, ignore, "Should not ignore comments from users with write access")
	})

	t.Run("processes comments when pr ID is nil", func(t *testing.T) {
		pr := EventPullRequestIssue()

		ignore, err := handler.ShouldIgnorePRCommentOrReview(ctx, pr, EventActorAdmin())

		require.NoError(t, err)
		require.False(t, ignore, "Should not ignore comments from users with write access")
	})
}

func TestResolveActorPermissionContext(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	repo := EventRepository()

	readOnlyConfig := automations.RuntimeConfig{RequireActorWritePermission: false}
	writeOnlyConfig := automations.RuntimeConfig{RequireActorWritePermission: true}

	t.Run("returns zero-value context when actor login is missing", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghTwirp := githubtwirp.NewNoopClient()
		policyCalls := 0
		ghTwirp.NoopSweagentdAPI.MockGetEffectiveTriggerActorPolicy = func(ctx context.Context, req *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
			policyCalls++
			return &sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse{}, nil
		}
		handler, _, _ := NewTestHandler(t, obsv, nil, ffClient, memory.NewStore(), ghTwirp, ghFactory)

		gh := ghFactory.NewClient("test-token")
		actorCtx, err := handler.resolveActorPermissionContext(ctx, gh, repo, "", []automations.RuntimeConfig{readOnlyConfig})
		require.NoError(t, err)
		require.Equal(t, "", actorCtx.actorLogin)
		require.False(t, actorCtx.hasPushPermissions)
		require.False(t, actorCtx.policyLookupFailed)
		require.False(t, actorCtx.allowReadAccessTriggers)
		require.Equal(t, 0, policyCalls, "policy RPC must not be called when actor login is missing")
	})

	t.Run("does not consult policy when actor has write access", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghTwirp := githubtwirp.NewNoopClient()
		policyCalls := 0
		ghTwirp.NoopSweagentdAPI.MockGetEffectiveTriggerActorPolicy = func(ctx context.Context, req *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
			policyCalls++
			return &sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse{AllowReadAccessTriggers: true}, nil
		}
		handler, _, _ := NewTestHandler(t, obsv, nil, ffClient, memory.NewStore(), ghTwirp, ghFactory)

		gh := ghFactory.NewClient("test-token")
		actorCtx, err := handler.resolveActorPermissionContext(ctx, gh, repo, EventActorWriter().Login, []automations.RuntimeConfig{readOnlyConfig, writeOnlyConfig})
		require.NoError(t, err)
		require.True(t, actorCtx.hasPushPermissions)
		require.Equal(t, 0, policyCalls, "policy RPC must not be called when actor has push permissions")
	})

	t.Run("does not consult policy when all configs require write", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghTwirp := githubtwirp.NewNoopClient()
		policyCalls := 0
		ghTwirp.NoopSweagentdAPI.MockGetEffectiveTriggerActorPolicy = func(ctx context.Context, req *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
			policyCalls++
			return &sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse{AllowReadAccessTriggers: true}, nil
		}
		handler, _, _ := NewTestHandler(t, obsv, nil, ffClient, memory.NewStore(), ghTwirp, ghFactory)

		gh := ghFactory.NewClient("test-token")
		actorCtx, err := handler.resolveActorPermissionContext(ctx, gh, repo, EventActorReader().Login, []automations.RuntimeConfig{writeOnlyConfig, writeOnlyConfig})
		require.NoError(t, err)
		require.False(t, actorCtx.hasPushPermissions)
		require.False(t, actorCtx.policyLookupFailed)
		require.False(t, actorCtx.allowReadAccessTriggers)
		require.Equal(t, 0, policyCalls, "policy RPC must not be called when no config can be allowed by the org policy")
	})

	t.Run("consults policy once when at least one config allows reads", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				},
			}, nil
		}
		policyCalls := 0
		ghTwirp.NoopSweagentdAPI.MockGetEffectiveTriggerActorPolicy = func(ctx context.Context, req *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
			policyCalls++
			require.Equal(t, uint64(repo.ID), req.RepositoryId)
			return &sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse{AllowReadAccessTriggers: true}, nil
		}
		handler, _, _ := NewTestHandler(t, obsv, nil, ffClient, memory.NewStore(), ghTwirp, ghFactory)

		gh := ghFactory.NewClient("test-token")
		// Mixed configs: even with multiple matching automations, the policy is consulted once.
		actorCtx, err := handler.resolveActorPermissionContext(ctx, gh, repo, EventActorReader().Login, []automations.RuntimeConfig{writeOnlyConfig, readOnlyConfig, readOnlyConfig})
		require.NoError(t, err)
		require.False(t, actorCtx.hasPushPermissions)
		require.False(t, actorCtx.policyLookupFailed)
		require.True(t, actorCtx.allowReadAccessTriggers)
		require.Equal(t, 1, policyCalls, "policy RPC must be called exactly once per event")
	})

	t.Run("marks policy lookup failed when RPC errors", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
				},
			}, nil
		}
		ghTwirp.NoopSweagentdAPI.MockGetEffectiveTriggerActorPolicy = func(ctx context.Context, req *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
			return nil, goerrors.New("simulated dotcom outage")
		}
		handler, _, _ := NewTestHandler(t, obsv, nil, ffClient, memory.NewStore(), ghTwirp, ghFactory)

		gh := ghFactory.NewClient("test-token")
		actorCtx, err := handler.resolveActorPermissionContext(ctx, gh, repo, EventActorReader().Login, []automations.RuntimeConfig{readOnlyConfig})
		require.NoError(t, err)
		require.True(t, actorCtx.policyLookupFailed)
		require.False(t, actorCtx.allowReadAccessTriggers)
	})
}

func TestShouldSkipTriggerForActorPermissions(t *testing.T) {
	testCases := []struct {
		name                        string
		actorLogin                  string
		hasPushPermissions          bool
		policyLookupFailed          bool
		allowReadAccessTriggers     bool
		requireActorWritePermission bool
		wantSkip                    bool
	}{
		{name: "skips when actor login missing", actorLogin: "", wantSkip: true},
		{name: "skips when actor login missing even with require write", actorLogin: "", requireActorWritePermission: true, wantSkip: true},
		{name: "does not skip writer actor", actorLogin: "writer", hasPushPermissions: true, wantSkip: false},
		{name: "does not skip writer actor when automation requires write", actorLogin: "writer", hasPushPermissions: true, requireActorWritePermission: true, wantSkip: false},
		{name: "skips reader actor when automation requires write", actorLogin: "reader", hasPushPermissions: false, requireActorWritePermission: true, wantSkip: true},
		{name: "skips reader actor when automation requires write even if policy allows", actorLogin: "reader", hasPushPermissions: false, allowReadAccessTriggers: true, requireActorWritePermission: true, wantSkip: true},
		{name: "skips reader actor when policy lookup failed", actorLogin: "reader", hasPushPermissions: false, policyLookupFailed: true, wantSkip: true},
		{name: "skips reader actor when policy disallows", actorLogin: "reader", hasPushPermissions: false, allowReadAccessTriggers: false, wantSkip: true},
		{name: "does not skip reader actor when policy allows", actorLogin: "reader", hasPushPermissions: false, allowReadAccessTriggers: true, wantSkip: false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			actorCtx := actorPermissionContext{
				actorLogin:              tc.actorLogin,
				hasPushPermissions:      tc.hasPushPermissions,
				policyLookupFailed:      tc.policyLookupFailed,
				allowReadAccessTriggers: tc.allowReadAccessTriggers,
			}
			require.Equal(t, tc.wantSkip, shouldSkipTriggerForActorPermissions(actorCtx, tc.requireActorWritePermission))
		})
	}
}

func TestAppPermissionsForRepository(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	const repoID = int64(100)
	const appID = int64(54321)

	newHandler := func(t *testing.T, mock func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error)) *Handler {
		t.Helper()
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.MockGetRepositoryInstallation = mock
		h, _, _ := NewTestHandler(t, obsv, nil, featureflags.NewNoopClient(nil), memory.NewStore(), ghTwirp, ghFactory)
		return h
	}

	t.Run("skips RPC for non-positive appID", func(t *testing.T) {
		for _, id := range []int64{0, -1} {
			called := false
			h := newHandler(t, func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
				called = true
				return &sweagentdTwirp.GetRepositoryInstallationResponse{}, nil
			})

			contents, workflows, err := h.appPermissionsForRepository(ctx, id, repoID)
			require.NoError(t, err)
			require.False(t, contents)
			require.False(t, workflows)
			require.False(t, called, "RPC must not be called for appID=%d", id)
		}
	})

	t.Run("decodes contents and workflows from permissions map", func(t *testing.T) {
		cases := []struct {
			name          string
			perms         map[string]string
			wantContents  bool
			wantWorkflows bool
		}{
			{"contents:write only", map[string]string{"contents": "write"}, true, false},
			{"contents:write + workflows:write", map[string]string{"contents": "write", "workflows": "write"}, true, true},
			{"contents:write + workflows:read", map[string]string{"contents": "write", "workflows": "read"}, true, false},
			{"contents:read", map[string]string{"contents": "read"}, false, false},
			{"contents omitted", map[string]string{"pull_requests": "write"}, false, false},
			{"empty perms", map[string]string{}, false, false},
		}
		for _, tc := range cases {
			t.Run(tc.name, func(t *testing.T) {
				h := newHandler(t, func(_ context.Context, req *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
					require.Equal(t, appID, req.AgentId)
					require.Equal(t, uint64(repoID), req.RepositoryId)
					return &sweagentdTwirp.GetRepositoryInstallationResponse{Permissions: tc.perms}, nil
				})

				contents, workflows, err := h.appPermissionsForRepository(ctx, appID, repoID)
				require.NoError(t, err)
				require.Equal(t, tc.wantContents, contents)
				require.Equal(t, tc.wantWorkflows, workflows)
			})
		}
	})

	t.Run("surfaces error so aqueduct can retry", func(t *testing.T) {
		h := newHandler(t, func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return nil, goerrors.New("simulated dotcom outage")
		})

		_, _, err := h.appPermissionsForRepository(ctx, appID, repoID)
		require.Error(t, err)
	})
}
