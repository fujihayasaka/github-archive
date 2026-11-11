package jobservice

import (
	"context"
	"errors"
	"fmt"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

// testLabelable is a minimal implementation of github.Labelable for tests
type testLabelable struct{ labels []github.GQLLabel }

func (t testLabelable) GetLabels() github.GQLConnection[github.GQLLabel] {
	return github.GQLConnection[github.GQLLabel]{Nodes: t.labels}
}

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
	return New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokestest.NewClient(t))
}

func baseAssignment() *jobs.Assignment {
	return jobs.NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo")
}

func baseRepo() gg.Repository  { return gg.Repository{DefaultBranch: gg.Ptr("main")} }
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

	asn, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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
}

func TestJobBuilder_WithNewAssignment(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	actor := baseActor()
	repo := baseRepo()

	ps := jobs.ProblemStatement{Content: "fix the thing", CommitCount: 0}
	runOpts := jobs.RunOptions{RunName: "Run 1"}

	asn, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
		WithNewAssignment(int64(42), 2, "owner-node", "repo-node", "owner", "repo").
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

func TestJobBuilder_RunOptionsHookOverrides(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	baseOpts := jobs.RunOptions{RunName: "base"}
	hookOpts := jobs.RunOptions{RunName: "hook"}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithRunOptions(baseOpts).
		WithRunOptionsHook(func(j *jobs.Job) jobs.RunOptions { return hookOpts }).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.Equal(t, "hook", job.RunOptions.RunName)
}

func TestJobBuilder_ProblemStatementBuilderError(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	wantErr := errors.New("boom")
	_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	twirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL_PRO,
				HasPaidAccess: true,
			}}, nil
	}
	svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokestest.NewClient(t))
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		Build(context.Background(), gh)
	require.NoError(t, err)

	// Expecting default model to be set
	require.Equal(t, DefaultModel, job.Model)
}

func TestJobBuilder_WithLabelsModelSelection(t *testing.T) {
	svc := newTestService(t)

	// Need FF enabled for model selection
	svc.ffs = featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentCanSelectModel: true})

	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	// Provide a label that encodes a model selection.
	label := github.GQLLabel{Name: "copilot:agent=my-special-model"}
	labelable := testLabelable{labels: []github.GQLLabel{label}}

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithLabelsFrom(labelable).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.Equal(t, "my-special-model", job.Model)
}

func TestJobBuilder_WithExplicitLabelsModelSelection(t *testing.T) {
	// Need FF enabled for model selection
	obsv := observability.NewNoopExporters()
	ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentCanSelectModel: true})
	capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)
	spokes := spokestest.NewClient(t)
	svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokes)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	// Provide a label that encodes a model selection.
	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithFeatures(jobs.EnvironmentFeatures{PullRequest: &jobs.PullRequestFeature{Labels: []string{"copilot:agent=my-special-model"}}}).
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.Equal(t, "my-special-model", job.Model)
}

func TestJobBuilder_WithExplicitLabelsCopiedtoPR(t *testing.T) {
	testCases := []struct {
		name   string
		labels []string
	}{{
		name:   "With Copilot and other labels",
		labels: []string{"copilot:agent=my-special-model", "some-other-label"},
	},
		{
			name:   "With only Copilot labels",
			labels: []string{"copilot:agent=my-special-model"},
		}, {
			name:   "With only other labels",
			labels: []string{"some-other-label"},
		}, {
			name:   "With no labels",
			labels: []string{},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			svc := newTestService(t)

			var labelsAdded []string
			gh := &github.NoopClient{
				MockAddLabelsToIssueOrPR: func(ctx context.Context, ownerLogin, repoName string, issueNumber int, lbls []string) error {
					labelsAdded = lbls
					return nil
				},
			}

			assignment := baseAssignment()
			actor := baseActor()
			repo := baseRepo()

			_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
				ForAssignment(assignment).
				WithJobActor(actor).
				WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
				WithFeatures(jobs.EnvironmentFeatures{PullRequest: &jobs.PullRequestFeature{TitlePlaceholder: "t", Labels: tc.labels}, Branch: &jobs.BranchFeature{BaseRef: "main", Name: "s"}}).
				Build(context.Background(), gh)

			require.NoError(t, err)
			require.ElementsMatch(t, tc.labels, labelsAdded)
		})
	}
}

func TestJobBuilder_CustomAgentBuilder(t *testing.T) {
	svc := newTestService(t)
	gh := &github.NoopClient{}
	assignment := baseAssignment()
	actor := baseActor()
	emptyLabels := testLabelable{labels: []github.GQLLabel{}}
	repo := baseRepo()

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(actor).
		WithLabelsFrom(emptyLabels). // avoids nil labelMetadata pointer in builder
		WithProblemStatement(&jobs.ProblemStatement{Content: "content"}).
		WithCustomAgentBuilder(func(ctx context.Context, gh github.ClientInterface, owner, repo string, lm sweagentd.LabelMetadata) (*customagent.Agent, error) {
			return customagent.Copilot(1, 2, "o", "r"), nil
		}).
		Build(context.Background(), gh)
	require.NoError(t, err)
	require.NotNil(t, job.CustomAgent)
}

func TestJobBuilder_NewPullRequestCreatesPRAndBranch(t *testing.T) {
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
		t.Fatalf("expected noop twirp client")
	}

	feat := jobs.EnvironmentFeatures{
		PullRequest: &jobs.PullRequestFeature{
			TitlePlaceholder: "[WIP] Fix stuff",
			BodyPlaceholder:  "body",
			BaseRef:          "main",
			HeadRef:          "fix-123",
		},
	}

	asn, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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

func TestJobBuilder_BranchRuleViolationHookCalled(t *testing.T) {
	svc := newTestService(t)
	// Configure GH so that actions are disabled and the reserved branch exists, creating rule violations.
	gh := &github.NoopClient{
		MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
			if branchName == github.CopilotBranchPrefix {
				return true, nil
			}
			return false, nil
		},
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
			return fmt.Errorf("expected rule violations for test")
		}
		return nil
	}

	_, _, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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

		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokestest.NewClient(t))

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

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokestest.NewClient(t))

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

		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix security vulnerabilities"}).
			WithNewSession().
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
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokestest.NewClient(t))

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
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
			ForAssignment(assignment).
			WithJobActor(actor).
			WithProblemStatement(&jobs.ProblemStatement{Content: "Fix security vulnerabilities"}).
			WithNewSession().
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

	t.Run("uses fallback values if AI-generating fails", func(t *testing.T) {
		// Create service with AI name generation feature flag enabled
		ff := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentAINameGeneration: true})
		capi, store, twirp, gcf, exp, aq, limiter := commonServiceDependencies(obsv)

		// Mock the AI client to return an error
		capi.MockChatCompletions = func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			return nil, errors.New("AI service unavailable")
		}

		ctx := requestctx.NewContext(context.Background())
		svc := New(obsv, ff, store, capi, gcf, twirp, aq, limiter, exp, nil, "test@example.com", spokestest.NewClient(t))

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
		_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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

func TestJobBuilder_WithHeadRefDoesNotCreateBranch(t *testing.T) {
	svc := newTestService(t)
	assignment := baseAssignment()
	actor := baseActor()
	repo := baseRepo()

	// Track whether CreateNewEmptyBranch was called
	gh := &github.NoopClient{
		MockCreateNewEmptyBranch: func(ctx context.Context, ownerLogin, repoName, baseBranchName, branchName string) (*gg.Reference, error) {
			t.Fatalf("CreateNewEmptyBranch should not be called when HeadRef is provided")
			return &gg.Reference{Ref: gg.Ptr("refs/heads/" + branchName)}, nil
		},
	}

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

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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

	// Track whether CreateNewEmptyBranch was called
	gh := &github.NoopClient{
		MockCreateNewEmptyBranch: func(ctx context.Context, ownerLogin, repoName, baseBranchName, branchName string) (*gg.Reference, error) {
			t.Fatal("CreateNewEmptyBranch should not be called when HeadRef is provided")
			return &gg.Reference{Ref: gg.Ptr("refs/heads/" + branchName)}, nil
		},
	}

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

	_, job, err := svc.NewJobBuilder(jobs.AgentActionFix, repo.GetDefaultBranch()).
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
