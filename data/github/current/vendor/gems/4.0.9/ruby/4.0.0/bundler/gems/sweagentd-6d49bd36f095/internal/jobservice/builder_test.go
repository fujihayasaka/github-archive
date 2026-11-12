package jobservice

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/feature-management-client-go/githubexp"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/tips"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

func newTestService(t *testing.T) *Service {
	t.Helper()
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(nil)
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	// Avoid nil panic in DetermineModel -> GetCopilotPlan
	twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		// Return a BUSINESS plan to exercise DefaultModelForBusinessOrPro path
		return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
	}
	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			// Return false for all branch existence checks to avoid copilot branch collision
			return make([]bool, len(refNames)), nil
		}))
	return New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)
}

func baseAssignment() *jobs.Assignment {
	return jobs.NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", false)
}

func baseRepo() gg.Repository {
	return gg.Repository{
		DefaultBranch: gg.Ptr("main"),
		Name:          gg.Ptr("repo"),
		Owner: &gg.User{
			Login: gg.Ptr("owner"),
		},
	}
}
func baseActor() jobs.JobActor { return jobs.JobActor{ID: 42, Login: "actor", DisplayLogin: "actor"} }

// --- Tests ---

func TestJobBuilder_ForAssignmentBasic(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	ps := jobs.ProblemStatement{Content: "fix the thing", CommitCount: 0}
	runOpts := jobs.RunOptions{RunName: "Run 1"}

	asn, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&ps).
		WithRunOptions(runOpts).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, asn)
	require.NotNil(t, job)
	require.Equal(t, ps.Content, job.ProblemStatement.Content)
	require.Equal(t, runOpts.RunName, job.RunOptions.RunName)
	require.Equal(t, jobs.JobStatusPending, job.Status)
	require.Equal(t, assignment.ID, job.AssignmentID)
	require.Greater(t, job.PreparedAt, int64(0), "PreparedAt should be set on full build")
}

func TestJobBuilder_PreparedAtSkippedOnPartialBuild(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
		WithoutCreatingFeatures().
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, job)
	require.Equal(t, int64(0), job.PreparedAt, "PreparedAt should not be set on partial build (WithoutCreatingFeatures)")
}

func TestJobBuilder_WithNewAssignment(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	actor := baseActor()
	repo := baseRepo()

	ps := jobs.ProblemStatement{Content: "fix the thing", CommitCount: 0}
	runOpts := jobs.RunOptions{RunName: "Run 1"}

	asn, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo", false).
		WithJobActor(actor).
		WithProblemStatement(&ps).
		WithRunOptions(runOpts).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, asn)
	require.NotNil(t, job)
	require.Equal(t, ps.Content, job.ProblemStatement.Content)
	require.Equal(t, runOpts.RunName, job.RunOptions.RunName)
	require.Equal(t, jobs.JobStatusPending, job.Status)
	require.NotEmpty(t, job.AssignmentID)
}

func TestJobBuilder_WithAssignmentPullRequest(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	actor := baseActor()
	repo := baseRepo()

	prID := int64(12345)
	prNumber := 42

	asn, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo", false).
		WithAssignmentPullRequest(prID, prNumber).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, asn)
	require.Equal(t, prID, asn.PullRequestID)
	require.Equal(t, prNumber, asn.PullRequestNumber)
}

func TestJobBuilder_BranchlessMode_SkipsBranchAndPRCreation(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(nil)
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
	}

	// Track whether CreatePullRequest is called — it should NOT be.
	prCreated := false
	twirp.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
		prCreated = true
		return &sweagentdtwirp.CreatePullRequestResponse{PullRequest: &sweagentdtwirp.PullRequest{Id: 999, GithubNumber: 321, RepositoryId: req.RepositoryId}}, nil
	}

	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			return make([]bool, len(refNames)), nil
		}))

	// Register the CCR app — it implements AgenticAppBranchlessMode.
	ccrAppID := int64(42)
	ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
	provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

	svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, provider, nil)
	actor := baseActor()
	repo := baseRepo()
	gh := &github.NoopClient{}

	// Features with PullRequest (HeadRef + BaseRef) — normally triggers PR creation.
	feat := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			BaseRef: "main",
			HeadRef: "feature-branch",
		},
	}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		WithNewAssignment(int64(1), 2, "owner-node", "repo-node", "owner", "repo", false).
		WithJobActor(actor).
		WithAgentID(ccrAppID).
		WithProblemStatement(&jobs.ProblemStatement{Content: "review the PR"}).
		WithFeatures(feat).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, job)

	// The CCR app's branchless mode should prevent PR and branch creation.
	require.False(t, prCreated, "should not create a new PR for branchless-mode apps")
	require.NotZero(t, job.PreparedAt, "PreparedAt should be set (unlike WithoutCreatingFeatures)")
	// BranchName should still be adopted from HeadRef for downstream checkout.
	require.Equal(t, "feature-branch", job.BranchName, "HeadRef should be adopted as BranchName even when skipping PR creation")
}

func TestJobBuilder_BranchlessMode_SkipsBranchProtectionRulesCheck(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(nil)
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
	}

	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			return make([]bool, len(refNames)), nil
		}))

	// Register the CCR app — it implements AgenticAppBranchlessMode.
	ccrAppID := int64(42)
	ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
	provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

	svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, provider, nil)
	actor := baseActor()
	repo := baseRepo()

	// Simulate a branch with RequiresApprovingReviews=true — this is the exact rule that
	// triggered the "Changes must be made through a pull request" error for CCR review jobs.
	gh := &github.NoopClient{
		MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
			return &[]github.GQLBranchProtectionRule{
				{
					Pattern:                  "*", // matches any branch
					RequiresApprovingReviews: true,
				},
			}, nil
		},
		MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
			return &gg.BranchRules{
				PullRequest: []*gg.PullRequestBranchRule{{BranchRuleMetadata: gg.BranchRuleMetadata{RulesetID: 1}}}, // would block a non-CCR agent
			}, nil
		},
	}

	// Features with PullRequest (HeadRef + BaseRef) — simulates a CCR review job on an existing PR.
	feat := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			BaseRef: "main",
			HeadRef: "dev",
		},
	}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		WithNewAssignment(int64(1), 2, "owner-node", "repo-node", "owner", "repo", false).
		WithJobActor(actor).
		WithAgentID(ccrAppID).
		WithProblemStatement(&jobs.ProblemStatement{Content: "review the PR"}).
		WithFeatures(feat).
		Build(context.Background(), gh)

	// CCR jobs should succeed even when branch protection rules would block pushes.
	require.NoError(t, err, "CCR review job should not fail due to branch protection rules")
	require.NotNil(t, job)
}

func TestJobBuilder_BranchlessMode_SkipsAINameGeneration(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: true})
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
	}

	// Track whether ChatCompletions is called — it should NOT be for branchless agents.
	aiCalled := false
	capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
		aiCalled = true
		return &openai.ChatCompletion{}, nil
	}

	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			return make([]bool, len(refNames)), nil
		}))

	// Register the CCR app — it implements AgenticAppBranchlessMode.
	ccrAppID := int64(42)
	ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
	provider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

	svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, provider, nil)
	actor := baseActor()
	repo := baseRepo()
	gh := &github.NoopClient{}

	feat := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			BaseRef: "main",
			HeadRef: "feature-branch",
		},
	}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		WithNewAssignment(int64(1), 2, "owner-node", "repo-node", "owner", "repo", false).
		WithJobActor(actor).
		WithAgentID(ccrAppID).
		WithProblemStatement(&jobs.ProblemStatement{Content: "review the PR"}).
		WithFeatures(feat).
		WithAINameGen().
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, job)

	require.False(t, aiCalled, "ChatCompletions should not be called for branchless-mode agents")
}

func TestJobBuilder_UseAsyncSessions(t *testing.T) {
	testCases := []struct {
		name                     string
		useAsyncSessions         bool
		expectedUseAsyncSessions bool
	}{
		{
			name:                     "UseAsyncSessions_true",
			useAsyncSessions:         true,
			expectedUseAsyncSessions: true,
		},
		{
			name:                     "UseAsyncSessions_false",
			useAsyncSessions:         false,
			expectedUseAsyncSessions: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			svc := newTestService(t)
			gh := &github.NoopClient{}
			actor := baseActor()
			repo := baseRepo()

			asn, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
				WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo", tc.useAsyncSessions).
				WithJobActor(actor).
				WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
				Build(context.Background(), gh)
			require.NoError(t, err)
			require.NotNil(t, asn)
			require.Equal(t, tc.expectedUseAsyncSessions, asn.UseAsyncSessions, "UseAsyncSessions should match the value passed to WithNewAssignment")
		})
	}
}

func TestJobBuilder_WithJobActor_UserType(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	actor := baseActor()
	repo := baseRepo()

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo", false).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
		Build(context.Background(), gh)

	require.NoError(t, err)
	require.NotNil(t, job)
	require.Equal(t, jobs.ActorType(""), job.ActorType, "WithJobActor should leave ActorType empty (default user)")
	require.False(t, job.IsOrgActor())
	require.False(t, job.IsBillToOrg())
}

func TestJobBuilder_WithTrigger_MarksTriggeredWithoutChangingActor(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(nil)
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
	}
	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			return make([]bool, len(refNames)), nil
		}))
	svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)
	gh := &github.NoopClient{}
	actor := baseActor()

	orgRepo := gg.Repository{
		DefaultBranch: gg.Ptr("main"),
		Name:          gg.Ptr("repo"),
		Owner: &gg.User{
			ID:    gg.Ptr(int64(999)),
			Login: gg.Ptr("my-org"),
			Type:  gg.Ptr("Organization"),
		},
	}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &orgRepo, orgRepo.GetDefaultBranch()).
		WithNewAssignment(999, 2, "owner-node", "repo-node", "my-org", "repo", false).
		WithJobActor(actor).
		WithTrigger().
		WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
		Build(context.Background(), gh)

	require.NoError(t, err)
	require.NotNil(t, job)
	require.True(t, job.IsTriggered)
	require.Empty(t, job.ActorType)
	require.Equal(t, actor.ID, job.ActorID)
	require.Equal(t, actor.Login, job.ActorLogin)
	require.Equal(t, actor.DisplayLogin, job.ActorDisplayLogin)
	require.False(t, job.IsOrgActor())
	require.False(t, job.IsBillToOrg())
}

func TestJobBuilder_RunOptionsHookOverrides(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	baseOpts := jobs.RunOptions{RunName: "base"}
	hookOpts := jobs.RunOptions{RunName: "hook"}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithRunOptions(baseOpts).
		WithRunOptionsHook(func(j *jobs.Job) jobs.RunOptions { return hookOpts }).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.Equal(t, "hook", job.RunOptions.RunName)
}

func TestJobBuilder_WithAutomationID(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	t.Run("sets AutomationID on job", func(t *testing.T) {
		_, job, err := svc.NewJobBuilder(jobs.AgentActionTask, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithTrigger().
			WithAutomationID("auto-abc-123").
			WithProblemStatement(&jobs.ProblemStatement{Content: "fix it"}).
			Build(context.Background(), gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "auto-abc-123", job.AutomationID)
		require.True(t, job.IsTriggered)
	})

	t.Run("empty AutomationID when not set", func(t *testing.T) {
		_, job, err := svc.NewJobBuilder(jobs.AgentActionTask, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithTrigger().
			WithProblemStatement(&jobs.ProblemStatement{Content: "fix it"}).
			Build(context.Background(), gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		require.Empty(t, job.AutomationID)
	})
}

// TestJobBuilder_WithCanWriteWorkflows verifies all three tri-state values
// are persisted on the job unchanged.
func TestJobBuilder_WithCanWriteWorkflows(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	build := func(t *testing.T, val *bool) *jobs.Job {
		t.Helper()
		_, job, err := svc.NewJobBuilder(jobs.AgentActionTask, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithWorkflowsAccess(val).
			WithProblemStatement(&jobs.ProblemStatement{Content: "fix it"}).
			Build(context.Background(), gh)
		require.NoError(t, err)
		require.NotNil(t, job)
		return job
	}

	t.Run("nil when not set", func(t *testing.T) {
		job := build(t, nil)
		require.Nil(t, job.CanWriteWorkflows, "nil ⇒ no check was performed")
	})

	t.Run("&true persists as &true", func(t *testing.T) {
		truth := true
		job := build(t, &truth)
		require.NotNil(t, job.CanWriteWorkflows)
		require.True(t, *job.CanWriteWorkflows)
	})

	t.Run("&false persists as &false", func(t *testing.T) {
		falsehood := false
		job := build(t, &falsehood)
		require.NotNil(t, job.CanWriteWorkflows)
		require.False(t, *job.CanWriteWorkflows)
	})
}

// TestJobBuilder_ForJob_PreservesCanWriteWorkflows guards against a regression
// where Build() unconditionally overwrites job.CanWriteWorkflows with the
// builder's (unset) value, silently erasing a value that was previously
// determined and persisted on the job.
func TestJobBuilder_ForJob_PreservesCanWriteWorkflows(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	rebuild := func(t *testing.T, initial *bool) *jobs.Job {
		t.Helper()
		existingJob := assignment.NewJob(jobs.AgentActionFixPRComment, actor, repo.GetDefaultBranch())
		existingJob.CanWriteWorkflows = initial
		_, job, err := svc.JobBuilderForJob(assignment, existingJob, &repo).
			WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
			WithNewSession().
			Build(requestctx.NewContext(context.Background()), gh)
		require.NoError(t, err)
		require.NotNil(t, job)
		return job
	}

	t.Run("preserves &true", func(t *testing.T) {
		truth := true
		job := rebuild(t, &truth)
		require.NotNil(t, job.CanWriteWorkflows)
		require.True(t, *job.CanWriteWorkflows)
	})

	t.Run("preserves &false", func(t *testing.T) {
		falsehood := false
		job := rebuild(t, &falsehood)
		require.NotNil(t, job.CanWriteWorkflows)
		require.False(t, *job.CanWriteWorkflows)
	})

	t.Run("preserves nil (no check ever performed)", func(t *testing.T) {
		job := rebuild(t, nil)
		require.Nil(t, job.CanWriteWorkflows)
	})

	t.Run("explicit WithWorkflowsAccess overrides seeded value", func(t *testing.T) {
		truth := true
		falsehood := false
		existingJob := assignment.NewJob(jobs.AgentActionFixPRComment, actor, repo.GetDefaultBranch())
		existingJob.CanWriteWorkflows = &truth
		_, job, err := svc.JobBuilderForJob(assignment, existingJob, &repo).
			WithWorkflowsAccess(&falsehood).
			WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
			WithNewSession().
			Build(requestctx.NewContext(context.Background()), gh)
		require.NoError(t, err)
		require.NotNil(t, job.CanWriteWorkflows)
		require.False(t, *job.CanWriteWorkflows, "explicit override must beat ForJob seed")
	})
}

func TestJobBuilder_ProblemStatementBuilderError(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	wantErr := errors.New("boom")
	_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatementBuilder(func(ctx context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			return jobs.ProblemStatement{}, wantErr
		}).
		Build(context.Background(), gh)
	require.Error(t, err)
	require.Contains(t, err.Error(), "failed to build problem statement")
}

func TestJobBuilder_AlwaysRunsModelSelection(t *testing.T) {
	// Need FF enabled for model selection
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(nil)
	capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
				HasPaidAccess: true,
			}}, nil
	}
	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			// Return false for all branch existence checks to avoid copilot branch collision
			return make([]bool, len(refNames)), nil
		}))
	svc := New(obsv, ff, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		Build(context.Background(), gh)
	require.NoError(t, err)

	// Expecting default model to be "auto" (concrete model resolved at job-fetch time)
	require.Equal(t, capi.AutoMode, job.Model)
}

func TestJobBuilder_WithModel(t *testing.T) {
	testCases := []struct {
		name                      string
		staffFlagEnabled          bool
		actualModel               string
		expectedModel             string
		existingJobModel          string
		expectedError             string
		mockListCodingAgentModels func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error)
	}{
		{
			name:          "WithModel sets custom model for individual user",
			actualModel:   "custom-model",
			expectedModel: "sweagent-capi:custom-model",
		},
		{
			name:          "WithModel takes precedence over label-based selection",
			actualModel:   "explicit-model",
			expectedModel: "sweagent-capi:explicit-model",
		},
		{
			name:             "Existing job model is preserved",
			actualModel:      "new-model",
			expectedModel:    "sweagent-capi:existing-model",
			existingJobModel: "sweagent-capi:existing-model",
		},
		{
			name:          "validates model exists in ListCodingAgentModels",
			actualModel:   "claude-3.5-sonnet",
			expectedModel: "sweagent-capi:claude-3.5-sonnet",
			mockListCodingAgentModels: func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
				return []capi.Model{
					{ID: "gpt-4o", Name: "GPT-4o", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
					{ID: "claude-3.5-sonnet", Name: "Claude 3.5 Sonnet", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
					{ID: "o1-mini", Name: "O1 Mini", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				}, nil
			},
		},
		{
			name:          "fails when model does not exist in ListCodingAgentModels",
			actualModel:   "claude-3.5-sonnet",
			expectedError: "no valid model found for user: determining model: model not found or not enabled for user",
			mockListCodingAgentModels: func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
				return []capi.Model{
					{ID: "gpt-4o", Name: "GPT-4o", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
					{ID: "o1-mini", Name: "O1 Mini", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
				}, nil
			},
		},
		{
			name:          "fails when ListCodingAgentModels returns error",
			actualModel:   "claude-3.5-sonnet",
			expectedError: "failed to determine model for job: listing models: capi service unavailable",
			mockListCodingAgentModels: func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
				return nil, errors.New("capi service unavailable")
			},
		},
		{
			name:        "does not validate when no model provided",
			actualModel: "",
			// Empty model defaults to auto; concrete model is resolved at job-fetch time.
			expectedModel: capi.AutoMode,
		},
		{
			name:             "allows non-CAPI model when CopilotSWEAgentCanSelectModel is enabled",
			staffFlagEnabled: true,
			actualModel:      "azopenai:gpt-4o",
			expectedModel:    "azopenai:gpt-4o",
		},
		{
			name:          "fails non-CAPI model when CopilotSWEAgentCanSelectModel is disabled",
			actualModel:   "azopenai:gpt-4o",
			expectedError: "no valid model found for user: determining model: model not found or not enabled for user",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			obsv := observability.NewNoopExporters()

			ff := featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentCanSelectModel: tc.staffFlagEnabled,
				capi.CopilotAPIAgentSessions:               true,
			})

			capiClient, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

			// Set up ListCodingAgentModels mock
			if tc.mockListCodingAgentModels != nil {
				capiClient.MockListCodingAgentModels = tc.mockListCodingAgentModels
			} else {
				// Default mock for existing tests
				capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
					return []capi.Model{
						{ID: "custom-model", Name: "Custom Model", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
						{ID: "explicit-model", Name: "Explicit Model", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
						{ID: "new-model", Name: "New Model", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
						{ID: "claude-sonnet-4.5", Name: "Claude Sonnet 4.5", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}},
					}, nil
				}
			}

			// Track the model passed to CreateSession
			var sessionModel string
			capiClient.MockCreateSession = func(ctx context.Context, create capi.SessionCreate) (*capi.CreateSessionResponse, error) {
				sessionModel = create.Model
				// Call the default NoopSessionClient implementation
				sessionClient := &capi.NoopSessionClient{}
				return sessionClient.CreateSession(ctx, create)
			}

			twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
						HasPaidAccess: true,
					}}, nil
			}
			spokes := spokestest.NewClient(t,
				spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
					return make([]bool, len(refNames)), nil
				}))
			svc := New(obsv, ff, store, capiClient, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)
			gh := &github.NoopClient{}
			assignment := baseAssignment()
			actor := baseActor()
			repo := baseRepo()

			var builder *JobBuilderWithAssignmentAndActor

			// Handle existing job scenario
			if tc.existingJobModel != "" {
				existingJob := assignment.NewJob(jobs.AgentActionFix, actor, repo.GetDefaultBranch())
				existingJob.Model = tc.existingJobModel
				builder = svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
					ForAssignment(assignment).
					ForJob(existingJob)
			} else {
				builder = svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
					ForAssignment(assignment).
					WithJobActor(actor)
			}

			_, job, err := builder.
				WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
				WithModel(tc.actualModel).
				WithNewSession().
				Build(requestctx.NewContext(context.Background()), gh)

			if tc.expectedError != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), tc.expectedError)
				return
			}

			require.NoError(t, err)
			require.Equal(t, tc.expectedModel, job.Model)
			require.True(t, job.HasSession(), "session should be created")
			// Session service should receive model without the sweagent-capi: prefix
			expectedSessionModel := strings.TrimPrefix(tc.expectedModel, "sweagent-capi:")
			require.Equal(t, expectedSessionModel, sessionModel, "session should be created with model stripped of prefix")
		})
	}
}

// TestJobBuilder_WithCustomAgent_PropagatesModel verifies that WithCustomAgent
// adopts the agent's model when no explicit model has been set on the builder.
// This is critical for automation-triggered jobs (issue created, workflow run
// failed, merge conflict, scheduler) which call WithCustomAgent but do not
// call WithModel — without this propagation, the automation's configured
// model is silently discarded.
func TestJobBuilder_WithCustomAgent_PropagatesModel(t *testing.T) {
	svc := newTestService(t)
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	tests := []struct {
		name          string
		agentModel    string
		callWithModel bool
		explicitModel string
		expectedModel string
	}{
		{
			name:          "agent model adopted when WithModel not called",
			agentModel:    "claude-sonnet-4.5",
			expectedModel: "claude-sonnet-4.5",
		},
		{
			name:          "empty agent model leaves builder model empty",
			agentModel:    "",
			expectedModel: "",
		},
		{
			name:          "explicit model after WithCustomAgent overrides agent model",
			agentModel:    "claude-sonnet-4.5",
			callWithModel: true,
			explicitModel: "gpt-5",
			expectedModel: "gpt-5",
		},
		{
			name:          "empty explicit model preserves agent model (WithModel is a no-op)",
			agentModel:    "claude-sonnet-4.5",
			callWithModel: true,
			explicitModel: "",
			expectedModel: "claude-sonnet-4.5",
		},
		{
			name:          "agent model does not overwrite previously set explicit model",
			agentModel:    "claude-sonnet-4.5",
			expectedModel: "gpt-5",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			builder := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
				ForAssignment(assignment).
				WithJobActor(actor)

			// Special-case: explicit model set BEFORE WithCustomAgent should be preserved.
			if tc.name == "agent model does not overwrite previously set explicit model" {
				builder = builder.WithModel("gpt-5").
					WithCustomAgent(&fakeCustomAgent{model: tc.agentModel})
			} else {
				builder = builder.WithCustomAgent(&fakeCustomAgent{model: tc.agentModel})
				if tc.callWithModel {
					builder = builder.WithModel(tc.explicitModel)
				}
			}

			require.Equal(t, tc.expectedModel, builder.model)
		})
	}
}

// fakeCustomAgent is a minimal sweagentd.CustomAgent stub used to exercise
// model propagation in WithCustomAgent. Only Model() is meaningful; all other
// methods return zero values.
type fakeCustomAgent struct {
	model string
}

func (f *fakeCustomAgent) Name() string                             { return "" }
func (f *fakeCustomAgent) RepoOwnerID() int64                       { return 0 }
func (f *fakeCustomAgent) RepoOwner() string                        { return "" }
func (f *fakeCustomAgent) RepoID() int64                            { return 0 }
func (f *fakeCustomAgent) RepoName() string                         { return "" }
func (f *fakeCustomAgent) DisplayName() string                      { return "" }
func (f *fakeCustomAgent) Description() string                      { return "" }
func (f *fakeCustomAgent) Prompt() string                           { return "" }
func (f *fakeCustomAgent) Tools() []string                          { return nil }
func (f *fakeCustomAgent) Version() string                          { return "" }
func (f *fakeCustomAgent) Target() string                           { return "" }
func (f *fakeCustomAgent) ConfigError() string                      { return "" }
func (f *fakeCustomAgent) Metadata() map[string]string              { return nil }
func (f *fakeCustomAgent) ArgumentHint() string                     { return "" }
func (f *fakeCustomAgent) InferenceEnabled() bool                   { return false }
func (f *fakeCustomAgent) DisableModelInvocation() bool             { return false }
func (f *fakeCustomAgent) UserInvocable() bool                      { return false }
func (f *fakeCustomAgent) Model() string                            { return f.model }
func (f *fakeCustomAgent) Handoffs() []sweagentd.CustomAgentHandoff { return nil }
func (f *fakeCustomAgent) Triggers() sweagentd.CustomAgentTriggers {
	return sweagentd.CustomAgentTriggers{}
}
func (f *fakeCustomAgent) GitHubMCPToolsets() []string { return nil }
func (f *fakeCustomAgent) Skills() []string            { return nil }
func (f *fakeCustomAgent) Scope() string               { return "" }

func TestJobBuilder_CustomAgentBuilder(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	// Override CreatePullRequest to set distinct IDs so we can assert.
	if noop, ok := svc.twirp.(*githubtwirp.NoopClient); ok {
		noop.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
			return &sweagentdtwirp.CreatePullRequestResponse{PullRequest: &sweagentdtwirp.PullRequest{Id: 999, GithubNumber: 321, RepositoryId: req.RepositoryId}}, nil
		}
	} else {
		t.Fatal("expected noop twirp client")
	}

	feat := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			TitlePlaceholder: "[WIP] Fix stuff",
			BodyPlaceholder:  "body",
			BaseRef:          "main",
			HeadRef:          "fix-123",
		},
	}

	asn, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		WithFeatures(feat).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, job)
	require.NotEmpty(t, job.BranchName)
	require.Equal(t, int64(999), asn.PullRequestID)
	require.Equal(t, 321, asn.PullRequestNumber)
	require.Equal(t, asn.PullRequestID, job.PullRequestID)
	require.Equal(t, asn.PullRequestNumber, job.PullRequestNumber)
}

func TestJobBuilder_SkipsTipsForNonCopilotApp(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	copilot := agenticapptest.NewTestCopilotWithID(t, 101)
	nonCopilotID := int64(202)
	nonCopilot := agenticapptest.NewTestApp(nonCopilotID)
	svc.appProvider = agenticapp.NewProvider(copilot, nonCopilot)
	svc.ffs = featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_tips":            true,
		"copilot_swe_agent_tips_onboarding": true,
	})

	features := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			TitlePlaceholder: "[WIP] Fix stuff",
			BodyPlaceholder:  "initial body",
			BaseRef:          "main",
		},
	}

	var capturedBody string
	noop, ok := svc.twirp.(*githubtwirp.NoopClient)
	require.True(t, ok, "expected noop twirp client")
	noop.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
		capturedBody = req.PrDescription
		return &sweagentdtwirp.CreatePullRequestResponse{
			PullRequest: &sweagentdtwirp.PullRequest{
				Id:           999,
				GithubNumber: 321,
				RepositoryId: req.RepositoryId,
			},
		}, nil
	}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "problem statement"}).
		WithFeatures(features).
		WithAgentID(nonCopilotID).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, job)

	// Tips remain available when queried directly
	require.NotEmpty(t, tips.GetRandomTipForJob(context.Background(), svc.ffs, job, &repo))

	require.NotContains(t, capturedBody, tips.PullRequestBodyTipSeparator)
	require.NotContains(t, capturedBody, "Let Copilot coding agent")
}

func TestJobBuilder_AgentIDSetWhenBuilderHasOneAndJobDoesNot(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	agentID := int64(12345)
	// Create a test provider with a specific agent ID
	svc.appProvider = agenticapptest.NewTestProviderWithID(t, agentID)

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
		WithAgentID(agentID).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.Equal(t, agentID, job.AgentID)
}

func TestJobBuilder_AgentIDPreservedWhenJobAlreadyHasOne(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	existingAgentID := int64(99999)
	builderAgentID := int64(12345)

	// Create a test provider with a specific agent ID
	svc.appProvider = agenticapptest.NewTestProviderWithID(t, existingAgentID)

	// Create a job with an existing agent ID
	existingJob := &jobs.Job{
		AssignmentID: assignment.ID,
		ActorID:      actor.ID,
		RepoID:       assignment.RepoID,
		AgentID:      existingAgentID,
	}

	builder := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
		WithAgentID(builderAgentID)

	// Simulate rebuilding a job that already has an agent ID
	builder.job = existingJob

	_, job, err := builder.Build(context.Background(), gh)
	require.NoError(t, err)
	// Job should preserve its existing agent ID
	require.Equal(t, existingAgentID, job.AgentID)
}

func TestJobBuilder_AgentIDSetBeforeProblemStatementBuilderRuns(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	agentID := int64(12345)
	customApp := agenticapptest.NewTestAppWithDetails(agentID, 456, "my-custom-agent", "my-custom-agent")
	copilot := agenticapptest.NewTestCopilot(t)
	svc.appProvider = agenticapp.NewProvider(copilot, customApp)

	var agentIDInBuilder int64
	var builtContent string
	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatementBuilder(func(ctx context.Context, j *jobs.Job) (jobs.ProblemStatement, error) {
			agentIDInBuilder = j.AgentID
			// Simulate what the real problem statement builder does: resolve the mentionable slug
			app, findErr := svc.appProvider.FindByID(ctx, j.AgentID)
			if findErr != nil {
				return jobs.ProblemStatement{}, findErr
			}
			content := fmt.Sprintf("## Comments on the PR (you are @%s in this section)\n", app.MentionableSlug())
			builtContent = content
			return jobs.ProblemStatement{Content: content}, nil
		}).
		WithAgentID(agentID).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.Equal(t, agentID, agentIDInBuilder, "AgentID must be set on the job before the problem statement builder runs")
	require.Equal(t, agentID, job.AgentID)
	require.Contains(t, builtContent, "@my-custom-agent[agent]", "problem statement must use the custom app's mentionable slug, not @copilot")
	require.NotContains(t, builtContent, "@copilot")
}

func TestJobBuilder_AgentIDNotSetWhenBothJobAndBuilderHaveZero(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.Equal(t, int64(0), job.AgentID)
}

func TestJobBuilder_BranchRuleViolationHookCalled(t *testing.T) {
	svc := newTestService(t)
	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			results := make([]bool, len(refNames))
			for i, ref := range refNames {
				results[i] = ref == "refs/heads/"+agenticapp.CopilotBranchPrefix
			}

			return results, nil
		}))
	svc.spokes = spokes

	// Configure GH so that actions are disabled and the reserved branch exists, creating rule violations.
	gh := &github.NoopClient{
		MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
			enabled := false
			return &gg.ActionsPermissionsRepository{Enabled: &enabled}, nil
		},
	}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	var hookCalled bool
	hook := func(ctx context.Context, ghc github.ClientInterface, actorLogin string, assignment *jobs.Assignment, result *CheckRulesResult) error {
		hookCalled = true
		if len(result.Rules) == 0 {
			return errors.New("expected rule violations for test")
		}
		return nil
	}

	_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		WithFeatures(jobs.EnvironmentFeatures{PullRequest: &jobs.PullRequestFeature{TitlePlaceholder: "t", BodyPlaceholder: "b"}, Branch: &jobs.BranchFeature{BaseRef: "main", Name: "s"}}).
		WithBranchRuleViolationHook(hook).
		Build(context.Background(), gh)
	require.Error(t, err)
	require.Contains(t, err.Error(), "repository rules violation")
	require.True(t, hookCalled, "expected branch rule violation hook to be called")
}

func TestJobBuilder_AINameGeneration(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("does not AI-gen names if feature flag is disabled", func(t *testing.T) {
		// Create service with AI name generation feature flag disabled
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: false})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		// Avoid nil panic in DetermineModel -> GetCopilotUser
		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			// Return a BUSINESS plan to exercise DefaultModelForBusinessOrPro path
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		// Mock the AI client - this should not be called when feature flag is disabled
		var aiCalled bool
		capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			aiCalled = true
			return nil, errors.New("AI should not be called when feature flag is disabled")
		}

		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks to avoid copilot branch collision
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		// Mock the Twirp service to capture the PR title
		var createdPRTitle string
		twirp.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
			createdPRTitle = req.PrName
			return &sweagentdtwirp.CreatePullRequestResponse{
				PullRequest: &sweagentdtwirp.PullRequest{
					Id:           999,
					GithubNumber: 321,
					RepositoryId: req.RepositoryId,
				},
			}, nil
		}

		ctx := requestctx.NewContext(context.Background())
		gh := &github.NoopClient{}
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix the authentication bug"}).
			WithFeatures(jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					TitlePlaceholder: "Original PR Title",
					BodyPlaceholder:  "PR body",
				},
				Branch: &jobs.BranchFeature{
					BaseRef: "main",
					Name:    "original-suffix",
				},
			}).
			WithNewSession().
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		// AI should not have been called
		require.False(t, aiCalled, "AI should not be called when feature flag is disabled")
		// The PR should be created with the original title, not AI-generated
		require.Equal(t, "Original PR Title", createdPRTitle)
		// The branch name should use the original suffix
		require.Contains(t, job.BranchName, "original-suffix")
	})

	t.Run("generates names", func(t *testing.T) {
		// Create service with AI name generation feature flag enabled
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: true})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		// Avoid nil panic in DetermineModel -> GetCopilotUser
		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			// Return a BUSINESS plan to exercise DefaultModelForBusinessOrPro path
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		// Mock the AI client to return specific names for all components
		capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			response := `{
					"branch_name": "comprehensive-security-fix",
					"session_name": "Comprehensive Security Vulnerability Fix",
					"pull_request_title": "Fix multiple security vulnerabilities in auth system"
				}`
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: response,
						},
					},
				},
			}, nil
		}

		ctx := requestctx.NewContext(context.Background())
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks to avoid copilot branch collision
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		// Mock the Twirp service to capture the PR title
		var createdPRTitle string
		twirp.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
			createdPRTitle = req.PrName
			return &sweagentdtwirp.CreatePullRequestResponse{
				PullRequest: &sweagentdtwirp.PullRequest{
					Id:           999,
					GithubNumber: 321,
					RepositoryId: req.RepositoryId,
				},
			}, nil
		}

		gh := &github.NoopClient{}
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix security vulnerabilities"}).
			WithNewSession().
			WithAINameGen().
			WithFeatures(jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					TitlePlaceholder: "Original PR Title",
					BodyPlaceholder:  "PR body",
					BaseRef:          "main",
				},
			}).
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify all AI-generated names were applied
		// Branch name should contain the AI-generated suffix (since no explicit suffix was provided)
		require.Contains(t, job.BranchName, "comprehensive-security-fix")

		// PR should be created with the AI-generated title
		require.Equal(t, "[WIP] Fix multiple security vulnerabilities in auth system", createdPRTitle)

		// Session should be created (we can't easily verify the name without mocking the session service)
		require.True(t, job.HasSession())
	})

	t.Run("preserves explicitly provided branch name suffix even when generated branch names is enabled", func(t *testing.T) {
		// Create service with AI name generation feature flag enabled
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: true})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		// Avoid nil panic in DetermineModel -> GetCopilotUser
		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			// Return a BUSINESS plan to exercise DefaultModelForBusinessOrPro path
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		// Mock the AI client to return specific names for all components
		capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			response := `{
				"branch_name": "ai-generated-branch-name",
				"session_name": "AI Generated Session",
				"pull_request_title": "AI Generated PR Title"
			}`
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: response,
						},
					},
				},
			}, nil
		}

		ctx := requestctx.NewContext(context.Background())
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks to avoid copilot branch collision
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		// Mock the Twirp service to capture the PR title
		var createdPRTitle string
		twirp.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
			createdPRTitle = req.PrName
			return &sweagentdtwirp.CreatePullRequestResponse{
				PullRequest: &sweagentdtwirp.PullRequest{
					Id:           999,
					GithubNumber: 321,
					RepositoryId: req.RepositoryId,
				},
			}, nil
		}

		gh := &github.NoopClient{}
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		// When an explicit NameSuffix is provided, it should be preserved even with AI enabled
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix security vulnerabilities"}).
			WithNewSession().
			WithAINameGen().
			WithFeatures(jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					TitlePlaceholder: "Original PR Title",
					BodyPlaceholder:  "PR body",
				},
				Branch: &jobs.BranchFeature{
					BaseRef: "main",
					Name:    "user-provided-branch", // This should be ignored in favor of NameSuffix below
				},
			}).
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)

		// The explicitly provided branch name suffix should be preserved
		require.Contains(t, job.BranchName, "user-provided-branch")
		require.NotContains(t, job.BranchName, "ai-generated-branch-name")

		// PR title should still be AI-generated since no explicit title logic exists
		require.Equal(t, "[WIP] AI Generated PR Title", createdPRTitle)

		// Session should be created
		require.True(t, job.HasSession())
	})

	t.Run("uses generated branch name candidate when branch name follows rules flag is enabled", func(t *testing.T) {
		ff := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentAIBranchNameGenerationFollowsRules: true,
			featureflags.CopilotSWEAgentAINameGeneration:                   true,
		})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}
		capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			response := `{
				"branch_name": "pattern-compliant-branch",
				"session_name": "AI Generated Session",
				"pull_request_title": "AI Generated PR Title"
			}`
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: response,
						},
					},
				},
			}, nil
		}

		var createdBranchName string
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				createdBranchName = opts.BranchName
				return nil
			}),
		)
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		ctx := requestctx.NewContext(context.Background())
		gh := &github.NoopClient{}
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix security vulnerabilities"}).
			WithAINameGen().
			WithFeatures(jobs.EnvironmentFeatures{
				Branch: &jobs.BranchFeature{
					BaseRef: "main",
					Name:    "user-provided-branch",
				},
			}).
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "copilot/pattern-compliant-branch", createdBranchName)
		require.Equal(t, "copilot/pattern-compliant-branch", job.BranchName)
	})

	t.Run("uses fallback values if AI-generating fails", func(t *testing.T) {
		// Create service with AI name generation feature flag enabled
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: true})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		// Mock the AI client to return an error
		capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			return nil, errors.New("AI service unavailable")
		}

		ctx := requestctx.NewContext(context.Background())
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks to avoid copilot branch collision
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		// Mock the Twirp service to capture the PR title
		var createdPRTitle string
		twirp.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
			createdPRTitle = req.PrName
			return &sweagentdtwirp.CreatePullRequestResponse{
				PullRequest: &sweagentdtwirp.PullRequest{
					Id:           999,
					GithubNumber: 321,
					RepositoryId: req.RepositoryId,
				},
			}, nil
		}

		// Avoid nil panic in DetermineModel -> GetCopilotUser
		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			// Return a BUSINESS plan to exercise DefaultModelForBusinessOrPro path
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		gh := &github.NoopClient{}
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		// Even when AI fails, the job creation should still succeed with fallback values
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix the authentication bug"}).
			WithFeatures(jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{
					TitlePlaceholder: "Fallback PR Title",
					BodyPlaceholder:  "PR body",
				},
				Branch: &jobs.BranchFeature{
					BaseRef: "main",
					Name:    "fallback-suffix",
				},
			}).
			WithNewSession().
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		// When AI fails, should fall back to original values
		require.Equal(t, "Fallback PR Title", createdPRTitle)
		require.Contains(t, job.BranchName, "fallback-suffix")
	})
}

func TestJobBuilder_TitleField(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("sets default Title with AgentActionFix", func(t *testing.T) {
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: false})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		ctx := requestctx.NewContext(context.Background())
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		gh := &github.NoopClient{}
		actor := baseActor()
		repo := baseRepo()

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo", false).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix the bug"}).
			WithNewSession().
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "Initial implementation", job.Title)
		require.True(t, job.HasSession())
	})

	t.Run("sets default Title with AgentActionFixPRComment", func(t *testing.T) {
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: false})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		ctx := requestctx.NewContext(context.Background())
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		gh := &github.NoopClient{}
		actor := baseActor()
		repo := baseRepo()

		// Create an assignment with an existing PR for FixPRComment action
		assignment := jobs.NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", false)
		assignment.PullRequestID = 123
		assignment.PullRequestNumber = 42

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFixPRComment, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Address the review comment"}).
			WithNewSession().
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "Review from @actor", job.Title)
	})

	t.Run("sets AI-generated Title when enabled", func(t *testing.T) {
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: true})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		// Mock AI to return a session name
		capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			response := `{
				"branch_name": "fix-auth-bug",
				"session_name": "Fixing authentication login bug",
				"pull_request_title": "Fix auth bug"
			}`
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: response,
						},
					},
				},
			}, nil
		}

		ctx := requestctx.NewContext(context.Background())
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		gh := &github.NoopClient{}
		actor := baseActor()
		repo := baseRepo()

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo", false).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix the authentication bug"}).
			WithNewSession().
			WithAINameGen().
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "Fixing authentication login bug", job.Title)
		require.True(t, job.HasSession())
	})

	t.Run("sets Title for async sessions", func(t *testing.T) {
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: false})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}

		ctx := requestctx.NewContext(context.Background())
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		gh := &github.NoopClient{}
		actor := baseActor()
		repo := baseRepo()

		// UseAsyncSessions=true means job has a pre-generated SessionID, but should still get a Title
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo", true).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix the bug"}).
			WithNewSession().
			Build(ctx, gh)

		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "Initial implementation", job.Title)
		require.True(t, job.HasSession())
		require.True(t, job.UseAsyncSessions)
	})
}

func TestJobBuilder_WithHeadRefDoesNotCreateBranch(t *testing.T) {
	svc := newTestService(t)
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	gh := &github.NoopClient{}

	// Mock CreatePullRequest to capture the head ref used
	var capturedHeadRef string
	noop, ok := svc.twirp.(*githubtwirp.NoopClient)
	require.True(t, ok, "expected noop twirp client")
	noop.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
		capturedHeadRef = req.HeadBranchName
		return &sweagentdtwirp.CreatePullRequestResponse{
			PullRequest: &sweagentdtwirp.PullRequest{
				Id:           999,
				GithubNumber: 321,
				RepositoryId: req.RepositoryId,
			},
		}, nil
	}

	// Provide a HeadRef to use an existing branch
	feat := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			TitlePlaceholder: "[WIP] Fix stuff",
			BodyPlaceholder:  "body",
			BaseRef:          "main",
			HeadRef:          "existing-branch-123", // Specifying this means no new branch should be created
		},
	}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		WithFeatures(feat).
		Build(context.Background(), gh)

	require.NoError(t, err)
	require.NotNil(t, job)
	// Branch name should be set to the provided HeadRef
	require.Equal(t, feat.PullRequest.HeadRef, job.BranchName)
	// OpenPullRequest should have been called with the provided HeadRef
	require.Equal(t, feat.PullRequest.HeadRef, capturedHeadRef)
}

func TestJobBuilder_WithHeadRefAndBranchFeature(t *testing.T) {
	svc := newTestService(t)
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	gh := &github.NoopClient{}

	// Mock CreatePullRequest to capture the head ref used
	var capturedHeadRef string
	noop, ok := svc.twirp.(*githubtwirp.NoopClient)
	require.True(t, ok, "expected noop twirp client")
	noop.NoopSweagentdAPI.MockCreatePullRequest = func(ctx context.Context, req *sweagentdtwirp.CreatePullRequestRequest) (*sweagentdtwirp.CreatePullRequestResponse, error) {
		capturedHeadRef = req.HeadBranchName
		return &sweagentdtwirp.CreatePullRequestResponse{
			PullRequest: &sweagentdtwirp.PullRequest{
				Id:           999,
				GithubNumber: 321,
				RepositoryId: req.RepositoryId,
			},
		}, nil
	}

	// Provide a HeadRef in PullRequest feature - it should take precedence
	// even when Branch feature is also present
	feat := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			TitlePlaceholder: "[WIP] Fix stuff",
			BodyPlaceholder:  "body",
			BaseRef:          "main",
			HeadRef:          "pr-head-ref",
		},
		Branch: &jobs.BranchFeature{
			BaseRef: "main",
			Name:    "branch-name-from-feature",
		},
	}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		WithFeatures(feat).
		Build(context.Background(), gh)

	require.NoError(t, err)
	require.NotNil(t, job)
	// Branch name should be set to the HeadRef from PullRequest feature, not Branch feature
	require.Equal(t, "pr-head-ref", job.BranchName)
	// OpenPullRequest should have been called with the HeadRef from PullRequest feature
	require.Equal(t, "pr-head-ref", capturedHeadRef)
}

func TestJobBuilder_ExistingBranchRulesViolation(t *testing.T) {
	svc := newTestService(t)
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	// Track how many times rules are checked and ensure the correct branch is used.
	branchCheckCalls := 0

	// Create a NoopClient that returns a repository rule violation
	gh := &github.NoopClient{
		MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
			branchCheckCalls++
			require.Equal(t, "existing-branch", branchName, "expected rules to be checked for the existing branch")

			// Return branch rules that would block the branch
			return &gg.BranchRules{
				Creation: []*gg.BranchRuleMetadata{{}}, // Any non-empty rule list triggers a violation
			}, nil
		},
	}

	// Build a job with an existing branch (HeadRef) that has rules violations
	_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		WithFeatures(jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "[WIP] Fix stuff",
				BodyPlaceholder:  "body",
				BaseRef:          "main",
				HeadRef:          "existing-branch", // Using existing branch
			},
		}).
		Build(context.Background(), gh)

	// The build should fail due to rules violation on the existing branch
	require.Error(t, err)
	require.True(t, IsBuilderFinalizedJobError(err), "expected BuilderFinalizedJobError but got: %v", err)

	// The underlying error should be a RulesViolationError
	var builderErr *BuilderFinalizedJobError

	// Ensure rules were checked exactly once for the existing branch.
	require.Equal(t, 1, branchCheckCalls, "expected rules to be checked exactly once")
	require.True(t, errors.As(err, &builderErr))
	var rulesErr *RulesViolationError
	require.True(t, errors.As(builderErr.Err, &rulesErr), "expected underlying error to be RulesViolationError")
}

func TestBuilderFinalizedJobError(t *testing.T) {
	t.Run("Error returns correct message with underlying error", func(t *testing.T) {
		underlyingErr := errors.New("test error")
		builderErr := &BuilderFinalizedJobError{Err: underlyingErr}

		expectedMsg := "job builder encountered known error and finalized job: test error"
		require.Equal(t, expectedMsg, builderErr.Error())
	})

	t.Run("Error returns generic message when no underlying error", func(t *testing.T) {
		builderErr := &BuilderFinalizedJobError{Err: nil}

		expectedMsg := "job builder encountered known error and finalized job"
		require.Equal(t, expectedMsg, builderErr.Error())
	})

	t.Run("Unwrap returns underlying error", func(t *testing.T) {
		underlyingErr := errors.New("test error")
		builderErr := &BuilderFinalizedJobError{Err: underlyingErr}

		require.Equal(t, underlyingErr, builderErr.Unwrap())
	})

	t.Run("Unwrap returns nil when no underlying error", func(t *testing.T) {
		builderErr := &BuilderFinalizedJobError{Err: nil}

		require.NoError(t, builderErr.Unwrap())
	})

	t.Run("IsBuilderFinalizedJobError returns true for BuilderFinalizedJobError", func(t *testing.T) {
		builderErr := &BuilderFinalizedJobError{Err: errors.New("test")}

		require.True(t, IsBuilderFinalizedJobError(builderErr))
	})

	t.Run("IsBuilderFinalizedJobError returns true for wrapped BuilderFinalizedJobError", func(t *testing.T) {
		builderErr := &BuilderFinalizedJobError{Err: errors.New("test")}
		wrappedErr := fmt.Errorf("wrapped: %w", builderErr)

		require.True(t, IsBuilderFinalizedJobError(wrappedErr))
	})

	t.Run("IsBuilderFinalizedJobError returns false for other errors", func(t *testing.T) {
		regularErr := errors.New("regular error")

		require.False(t, IsBuilderFinalizedJobError(regularErr))
	})

	t.Run("IsBuilderFinalizedJobError returns false for nil", func(t *testing.T) {
		require.False(t, IsBuilderFinalizedJobError(nil))
	})
}

func TestJobBuilder_BranchRuleViolationFinalizesJob(t *testing.T) {
	svc := newTestService(t)
	spokes := spokestest.NewClient(t,
		spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
			results := make([]bool, len(refNames))
			for i, ref := range refNames {
				results[i] = ref == "refs/heads/"+agenticapp.CopilotBranchPrefix
			}
			return results, nil
		}))
	svc.spokes = spokes

	// Configure GH so that actions are disabled, creating a rule violation.
	gh := &github.NoopClient{
		MockGetActionsPermissions: func(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error) {
			enabled := false
			return &gg.ActionsPermissionsRepository{Enabled: &enabled}, nil
		},
	}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	// Build a job that requires a branch (which triggers rules check during branch creation)
	_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		WithFeatures(jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{TitlePlaceholder: "t", BodyPlaceholder: "b"},
			Branch:      &jobs.BranchFeature{BaseRef: "main", Name: "s"},
		}).
		WithNewSession().
		Build(context.Background(), gh)

	// The error should be a BuilderFinalizedJobError indicating the job was finalized
	require.Error(t, err)
	require.True(t, IsBuilderFinalizedJobError(err), "expected BuilderFinalizedJobError but got: %v", err)

	// The underlying error should be a RulesViolationError
	var builderErr *BuilderFinalizedJobError
	require.True(t, errors.As(err, &builderErr))
	var rulesErr *RulesViolationError
	require.True(t, errors.As(builderErr.Err, &rulesErr), "expected underlying error to be RulesViolationError")
}

func TestJobBuilder_FinalizeUnexecutedJobForError(t *testing.T) {
	t.Run("returns false when job is nil", func(t *testing.T) {
		svc := newTestService(t)
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		builder := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor)

		// Don't initialize the job
		builder.job = nil

		rulesErr := &RulesViolationError{
			CheckRulesResult: &CheckRulesResult{
				Rules: []string{"test rule"},
			},
		}

		// Call finalizeUnexecutedJobForError with nil job
		handled := builder.finalizeUnexecutedJobForError(context.Background(), nil, rulesErr)

		// Should return true when job is nil
		require.True(t, handled)
	})

	t.Run("returns false for non-rules violation errors", func(t *testing.T) {
		svc := newTestService(t)
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		builder := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor)

		builder.job = &jobs.Job{
			AssignmentID: assignment.ID,
			ActorID:      actor.ID,
			RepoID:       assignment.RepoID,
		}

		// Create a non-rules violation error
		regularErr := errors.New("some other error")

		// Call finalizeUnexecutedJobForError
		handled := builder.finalizeUnexecutedJobForError(context.Background(), nil, regularErr)

		// Should return false for non-rules violation errors
		require.False(t, handled)
	})

	t.Run("returns true for rules violation error", func(t *testing.T) {
		svc := newTestService(t)
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		builder := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor)

		builder.job = &jobs.Job{
			AssignmentID: assignment.ID,
			ActorID:      actor.ID,
			RepoID:       assignment.RepoID,
			Status:       jobs.JobStatusPending,
		}

		rulesErr := &RulesViolationError{
			CheckRulesResult: &CheckRulesResult{
				Rules: []string{"test rule"},
			},
		}

		// Call finalizeUnexecutedJobForError - should return true for rules violations
		handled := builder.finalizeUnexecutedJobForError(context.Background(), nil, rulesErr)

		// Should return true indicating the error type was handled
		require.True(t, handled)
	})
}

func TestJobBuilder_RetryBranchCreation(t *testing.T) {
	t.Run("retries branch creation when it fails and more options available", func(t *testing.T) {
		svc := newTestService(t)
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		// Track branch creation attempts
		var attemptedBranches []string
		createBranchCallCount := 0

		// Configure spokes to fail the first two branch creation attempts
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				attemptedBranches = append(attemptedBranches, opts.BranchName)
				createBranchCallCount++
				// Fail the first two attempts, succeed on the third
				if createBranchCallCount <= 2 {
					return errors.New("simulated branch creation failure")
				}
				return nil
			}),
		)
		svc.spokes = spokes

		gh := &github.NoopClient{}
		feat := jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "[WIP] Fix stuff",
				BodyPlaceholder:  "body",
				BaseRef:          "main",
			},
			Branch: &jobs.BranchFeature{
				BaseRef: "main",
			},
		}

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "test content"}).
			WithFeatures(feat).
			Build(context.Background(), gh)

		// Build should succeed after retries
		require.NoError(t, err)
		require.NotNil(t, job)

		// Should have attempted to create 3 branches (failed twice, succeeded third time)
		require.Equal(t, 3, createBranchCallCount)
		require.Len(t, attemptedBranches, 3)

		// Verify that different branch names were tried
		// The first should be the base name, subsequent ones should have suffixes
		require.NotEqual(t, attemptedBranches[0], attemptedBranches[1])
		require.NotEqual(t, attemptedBranches[1], attemptedBranches[2])

		// The final job should have the branch name of the successful attempt
		require.Equal(t, attemptedBranches[2], job.BranchName)
	})

	t.Run("fails when branch creation fails and no more options available", func(t *testing.T) {
		svc := newTestService(t)
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		createBranchCallCount := 0

		// Configure spokes to always fail branch creation
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Return false for all branch existence checks
				return make([]bool, len(refNames)), nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				createBranchCallCount++
				// Always fail
				return errors.New("simulated branch creation failure")
			}),
		)
		svc.spokes = spokes

		gh := &github.NoopClient{}
		feat := jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "[WIP] Fix stuff",
				BodyPlaceholder:  "body",
				BaseRef:          "main",
			},
			Branch: &jobs.BranchFeature{
				BaseRef: "main",
			},
		}

		_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "test content"}).
			WithFeatures(feat).
			Build(context.Background(), gh)

		// Build should fail after exhausting all retry options
		require.Error(t, err)

		// Should have attempted to create multiple branches
		// (base name + suffixes from branchNameSuffixes + UUID fallback)
		// The count should be at least len(branchNameSuffixes) + 2 (base + UUID)
		// Plus 3 additional retry attempts for the last name
		require.GreaterOrEqual(t, createBranchCallCount, 9) // base + 5 suffixes + UUID + 3 retries on last
	})

	t.Run("retries with backoff on last branch name and succeeds", func(t *testing.T) {
		svc := newTestService(t)
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		createBranchCallCount := 0
		var attemptedBranches []string

		// Configure spokes so that only the last branch name (UUID fallback)
		// is reachable, and it fails the first call but succeeds on a retry
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Mark all but the last as existing so only the last name is tried
				result := make([]bool, len(refNames))
				for i := range result {
					if i < len(result)-1 {
						result[i] = true
					}
				}
				return result, nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				attemptedBranches = append(attemptedBranches, opts.BranchName)
				createBranchCallCount++
				// Fail the first call, succeed on the second (first retry)
				if createBranchCallCount <= 1 {
					return errors.New("simulated transient failure")
				}
				return nil
			}),
		)
		svc.spokes = spokes

		gh := &github.NoopClient{}
		feat := jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "[WIP] Fix stuff",
				BodyPlaceholder:  "body",
				BaseRef:          "main",
			},
			Branch: &jobs.BranchFeature{
				BaseRef: "main",
			},
		}

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "test content"}).
			WithFeatures(feat).
			Build(context.Background(), gh)

		require.NoError(t, err)
		require.NotNil(t, job)

		// Should have 2 calls: initial attempt + 1 successful retry
		require.Equal(t, 2, createBranchCallCount)
		// Both attempts should be the same branch name (the last/only one available)
		require.Equal(t, attemptedBranches[0], attemptedBranches[1])
		require.Equal(t, attemptedBranches[1], job.BranchName)
	})

	t.Run("retries with backoff on last branch name exhausts all retries", func(t *testing.T) {
		svc := newTestService(t)
		assignment := baseAssignment()
		actor := baseActor()
		repo := baseRepo()

		createBranchCallCount := 0

		// Configure spokes so that only the last branch name is tried and always fails
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				// Mark all but the last as existing
				result := make([]bool, len(refNames))
				for i := range result {
					if i < len(result)-1 {
						result[i] = true
					}
				}
				return result, nil
			}),
			spokestest.WithMockCreateBranch(func(ctx context.Context, opts sweagentd.CreateBranchOpts) error {
				createBranchCallCount++
				return errors.New("simulated persistent failure")
			}),
		)
		svc.spokes = spokes

		gh := &github.NoopClient{}
		feat := jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				TitlePlaceholder: "[WIP] Fix stuff",
				BodyPlaceholder:  "body",
				BaseRef:          "main",
			},
			Branch: &jobs.BranchFeature{
				BaseRef: "main",
			},
		}

		_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "test content"}).
			WithFeatures(feat).
			Build(context.Background(), gh)

		require.Error(t, err)

		// Should have 4 calls: 1 initial attempt + 3 retries on the last name
		require.Equal(t, 4, createBranchCallCount)
	})
}

func TestJobBuilder_SDKAssignmentContext(t *testing.T) {
	gh := &github.NoopClient{}
	actor := baseActor()
	repo := baseRepo()

	// newServiceWithSDKClient creates a test service with the given feature flags
	// and exp SDK client. Shared boilerplate for tests in this group.
	newServiceWithSDKClient := func(t *testing.T, flags map[string]bool, sdkClient exp.ExperimentationClient) *Service {
		t.Helper()
		obsv := observability.NewNoopExporters()
		ff := featureflags.NewNoopClient(flags)
		capiClient, store, twirp, gcf, legacyExp, aq, limiter := commonServiceDependencies(obsv)
		twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS, HasPaidAccess: true}}, nil
		}
		spokes := spokestest.NewClient(t,
			spokestest.WithMockCheckForExistingRefs(func(ctx context.Context, repoID uint64, refNames []string) ([]bool, error) {
				return make([]bool, len(refNames)), nil
			}))
		svc := New(obsv, ff, store, capiClient, gcf, twirp, aq, limiter, legacyExp, nil, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)
		if sdkClient != nil {
			svc = svc.WithExpSDKClient(sdkClient)
		}
		return svc
	}

	t.Run("persists assignment context on job and assignment", func(t *testing.T) {
		sdkClient := &mockExpClient{
			assignmentResult: githubexp.NewAssignmentResult(
				map[string]string{"/my_feature": "treatment"},
				"test-flight:100;rollout:200",
				1,
			),
		}
		svc := newServiceWithSDKClient(t, map[string]bool{
			featureflags.CodingAgentLearningMachinePipelineEvents: true,
		}, sdkClient)

		assignment := baseAssignment()
		ctx := requestctx.NewContext(context.Background())
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
			Build(ctx, gh)

		require.NoError(t, err)
		require.Equal(t, "test-flight:100;rollout:200", job.SDKAssignmentContext)
		require.Equal(t, "test-flight:100;rollout:200", assignment.SDKAssignmentContext)

		// The request context should carry the full AssignmentResult for
		// typed access later in the request lifecycle.
		ctxAssignment := exp.AssignmentFromContext(ctx)
		require.Equal(t, "test-flight:100;rollout:200", ctxAssignment.GetAssignmentContext())
	})

	t.Run("skips SDK assignment when flag disabled", func(t *testing.T) {
		sdkClient := &mockExpClient{
			assignmentResult: githubexp.NewAssignmentResult(
				map[string]string{"/my_feature": "treatment"},
				"should-not-appear",
				1,
			),
		}
		svc := newServiceWithSDKClient(t, nil, sdkClient)

		assignment := baseAssignment()
		ctx := requestctx.NewContext(context.Background())
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
			Build(ctx, gh)

		require.NoError(t, err)
		require.Equal(t, "", job.SDKAssignmentContext)
		require.Equal(t, "", assignment.SDKAssignmentContext)

		// When the flag is disabled, no SDK assignment is evaluated, so the
		// context should carry the noop/default assignment.
		ctxAssignment := exp.AssignmentFromContext(ctx)
		require.Equal(t, "", ctxAssignment.GetAssignmentContext())
	})

	t.Run("skips SDK assignment when context already set", func(t *testing.T) {
		sdkClient := &mockExpClient{
			assignmentResult: githubexp.NewAssignmentResult(
				map[string]string{"/my_feature": "treatment"},
				"should-not-overwrite",
				1,
			),
		}
		svc := newServiceWithSDKClient(t, map[string]bool{
			featureflags.CodingAgentLearningMachinePipelineEvents: true,
		}, sdkClient)

		assignment := baseAssignment()
		assignment.SDKAssignmentContext = "pre-existing-ctx"

		ctx := requestctx.NewContext(context.Background())
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
			Build(ctx, gh)

		require.NoError(t, err)
		require.Equal(t, "pre-existing-ctx", job.SDKAssignmentContext)

		// When context is already set, SetSDKAssignmentForJob is skipped,
		// so the request context carries the noop/default assignment.
		ctxAssignment := exp.AssignmentFromContext(ctx)
		require.Equal(t, "", ctxAssignment.GetAssignmentContext())
	})

	t.Run("skips SDK assignment when SDK client not configured", func(t *testing.T) {
		svc := newServiceWithSDKClient(t, map[string]bool{
			featureflags.CodingAgentLearningMachinePipelineEvents: true,
		}, nil) // no SDK client

		assignment := baseAssignment()
		ctx := requestctx.NewContext(context.Background())
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, &repo, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "fix the thing"}).
			Build(ctx, gh)

		require.NoError(t, err)
		// No SDK client → GetExperimentAssignment returns noop with empty context
		require.Equal(t, "", job.SDKAssignmentContext)

		// Without an SDK client the assignment on the request context is still noop.
		ctxAssignment := exp.AssignmentFromContext(ctx)
		require.Equal(t, "", ctxAssignment.GetAssignmentContext())
	})
}

// mockExpClient implements exp.ExperimentationClient for testing.
// Construct test assignments using githubexp.NewAssignmentResult as recommended
// by the feature-management-client-go docs.
type mockExpClient struct {
	assignmentResult *githubexp.AssignmentResult
}

func (m *mockExpClient) ResilientStart(_ context.Context, _ ...githubexp.ResilientStartOption) error {
	return nil
}

func (m *mockExpClient) GetAssignment(_ context.Context, _ map[string]string, _, _ []string) *githubexp.AssignmentResult {
	return m.assignmentResult
}
