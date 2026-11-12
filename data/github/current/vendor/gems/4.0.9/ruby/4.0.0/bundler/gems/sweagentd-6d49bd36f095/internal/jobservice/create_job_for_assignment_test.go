package jobservice

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobsCustomAgent "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

type retryTrackingClientFactory struct {
	*github.NoopClientFactory

	invalidateCalls int
}

func (cf *retryTrackingClientFactory) InvalidateTokenForRepo(_ sweagentd.AgenticApp, _, _ int64) {
	cf.invalidateCalls++
}

func TestGetMostRecentJob(t *testing.T) {
	t.Run("returns nil for empty list", func(t *testing.T) {
		result := GetMostRecentJob(nil)
		require.Nil(t, result)
	})

	t.Run("returns nil for empty slice", func(t *testing.T) {
		result := GetMostRecentJob([]*jobs.Job{})
		require.Nil(t, result)
	})

	t.Run("returns the only job in a single-element list", func(t *testing.T) {
		job := &jobs.Job{ID: "job-1", CreatedAt: 100}
		result := GetMostRecentJob([]*jobs.Job{job})
		require.Equal(t, job, result)
	})

	t.Run("returns most recent job from multiple jobs", func(t *testing.T) {
		oldest := &jobs.Job{ID: "oldest", CreatedAt: 100}
		middle := &jobs.Job{ID: "middle", CreatedAt: 200}
		newest := &jobs.Job{ID: "newest", CreatedAt: 300}

		result := GetMostRecentJob([]*jobs.Job{oldest, newest, middle})
		require.Equal(t, newest, result)
	})

	t.Run("returns first job when all have same timestamp", func(t *testing.T) {
		job1 := &jobs.Job{ID: "job-1", CreatedAt: 100}
		job2 := &jobs.Job{ID: "job-2", CreatedAt: 100}
		job3 := &jobs.Job{ID: "job-3", CreatedAt: 100}

		result := GetMostRecentJob([]*jobs.Job{job1, job2, job3})
		require.Equal(t, job1, result)
	})
}

func TestInheritedWorkflowsAccess(t *testing.T) {
	const targetAgent int64 = 42
	const otherAgent int64 = 99
	trueVal := true
	falseVal := false

	t.Run("returns nil for nil list", func(t *testing.T) {
		require.Nil(t, jobs.InheritedWorkflowsAccess(nil, targetAgent))
	})

	t.Run("returns nil for empty slice", func(t *testing.T) {
		require.Nil(t, jobs.InheritedWorkflowsAccess([]*jobs.Job{}, targetAgent))
	})

	t.Run("returns nil when no same-agent job has a checked value", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "job-1", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: nil},
			{ID: "job-2", CreatedAt: 200, AgentID: targetAgent, CanWriteWorkflows: nil},
		}
		require.Nil(t, jobs.InheritedWorkflowsAccess(jobsList, targetAgent))
	})

	t.Run("returns value from single matching job", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "job-1", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("ignores jobs from other agents", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "job-1", CreatedAt: 500, AgentID: otherAgent, CanWriteWorkflows: &falseVal},
			{ID: "job-2", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("returns most recent non-nil value from same agent", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "oldest", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
			{ID: "newest", CreatedAt: 300, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
			{ID: "middle", CreatedAt: 200, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("falls back to older non-nil value when newest is nil (stuck-nil mitigation)", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "older", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
			{ID: "newest", CreatedAt: 500, AgentID: targetAgent, CanWriteWorkflows: nil},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.False(t, *result)
	})

	t.Run("skips nil entries in slice", func(t *testing.T) {
		jobsList := []*jobs.Job{
			nil,
			{ID: "job-1", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
			nil,
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})
}

func TestResolveBranchConfig(t *testing.T) {
	defaultBranch := "main"
	repo := &gg.Repository{
		DefaultBranch: &defaultBranch,
	}

	t.Run("uses branch base ref when both name and base ref provided", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				Name:    "feature/my-branch",
				BaseRef: "develop",
			},
		}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "develop", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
		require.Empty(t, config.InheritedBranch)
		require.NotNil(t, config.Features.Branch)
	})

	t.Run("uses branch base ref when name is empty", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				BaseRef: "develop",
			},
		}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "develop", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
	})

	t.Run("uses pull request base ref when only PR features provided", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{
				BaseRef: "release/v1",
			},
		}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "release/v1", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
	})

	t.Run("falls back to default branch when features have no refs", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{
			PullRequest: &jobs.PullRequestFeature{},
		}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "main", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
	})

	t.Run("inherits branch from previous job with original base commit", func(t *testing.T) {
		latestJob := &jobs.Job{
			BranchName: "copilot/fix-bug-123",
			BaseCommit: "develop",
		}
		features := jobs.EnvironmentFeatures{}
		config := ResolveBranchConfig(repo, latestJob, features, false)
		require.Equal(t, "develop", config.BaseRef, "should use the original base commit for PR targeting")
		require.Equal(t, "copilot/fix-bug-123", config.InheritedBranch)
		require.False(t, config.NeedsNewBranch)
	})

	t.Run("inherits branch falls back to default branch when base commit empty", func(t *testing.T) {
		latestJob := &jobs.Job{
			BranchName: "copilot/fix-bug-123",
		}
		features := jobs.EnvironmentFeatures{}
		config := ResolveBranchConfig(repo, latestJob, features, false)
		require.Equal(t, "main", config.BaseRef, "should fall back to default branch when BaseCommit is empty")
		require.Equal(t, "copilot/fix-bug-123", config.InheritedBranch)
		require.False(t, config.NeedsNewBranch)
	})

	t.Run("creates new branch when no features and no previous job", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "main", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
		require.Empty(t, config.InheritedBranch)
		require.NotNil(t, config.Features.Branch)
		require.Equal(t, "main", config.Features.Branch.BaseRef)
	})

	t.Run("creates new branch when previous job has no branch", func(t *testing.T) {
		latestJob := &jobs.Job{
			BranchName: "",
		}
		features := jobs.EnvironmentFeatures{}
		config := ResolveBranchConfig(repo, latestJob, features, false)
		require.Equal(t, "main", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
		require.NotNil(t, config.Features.Branch)
	})

	t.Run("explicit features take priority over previous job branch", func(t *testing.T) {
		latestJob := &jobs.Job{
			BranchName: "copilot/old-branch",
		}
		features := jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				Name:    "feature/new-branch",
				BaseRef: "develop",
			},
		}
		config := ResolveBranchConfig(repo, latestJob, features, false)
		require.Equal(t, "develop", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
		require.Empty(t, config.InheritedBranch)
	})

	t.Run("uses PR base ref when branch name set but no branch base ref", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				Name: "copilot/my-feature",
			},
			PullRequest: &jobs.PullRequestFeature{
				BaseRef: "release/v2",
			},
		}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "release/v2", config.BaseRef, "should use PullRequest.BaseRef, not Branch.Name")
		require.True(t, config.NeedsNewBranch)
	})

	t.Run("branchless enabled with no features returns no branch", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{}
		config := ResolveBranchConfig(repo, nil, features, true)
		require.Equal(t, "main", config.BaseRef)
		require.False(t, config.NeedsNewBranch)
		require.Nil(t, config.Features.Branch)
		require.Nil(t, config.Features.PullRequest)
	})

	t.Run("branchless disabled with no features creates branch", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "main", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
		require.NotNil(t, config.Features.Branch)
	})

	t.Run("branchless enabled with explicit branch still creates branch", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{Name: "my-branch"},
		}
		config := ResolveBranchConfig(repo, nil, features, true)
		require.Equal(t, "main", config.BaseRef)
		require.True(t, config.NeedsNewBranch)
		require.NotNil(t, config.Features.Branch)
	})

	t.Run("branch base ref takes priority over branch name for base ref", func(t *testing.T) {
		features := jobs.EnvironmentFeatures{
			Branch: &jobs.BranchFeature{
				Name:    "copilot/improve-drink-categories-ui",
				BaseRef: "main",
			},
		}
		config := ResolveBranchConfig(repo, nil, features, false)
		require.Equal(t, "main", config.BaseRef, "BaseRef should take priority over Name to avoid base==head")
		require.True(t, config.NeedsNewBranch)
	})
}

func TestHydrateRequirements(t *testing.T) {
	ctx := context.Background()

	t.Run("fetches user and repo when repo is nil", func(t *testing.T) {
		gh := &github.NoopClient{}
		user, repo, owner, err := hydrateRequirements(ctx, gh, 100, 200, 300, nil)
		require.NoError(t, err)
		require.NotNil(t, user)
		require.NotNil(t, repo)
		require.NotNil(t, owner)
		require.Equal(t, int64(100), user.GetID())
		require.Equal(t, int64(200), repo.GetID())
		require.Equal(t, int64(300), owner.GetID())
	})

	t.Run("uses pre-fetched repo when provided", func(t *testing.T) {
		preRepo := &gg.Repository{
			ID:   gg.Ptr(int64(999)),
			Name: gg.Ptr("pre-fetched-repo"),
		}
		gh := &github.NoopClient{}
		user, repo, owner, err := hydrateRequirements(ctx, gh, 100, 200, 300, preRepo)
		require.NoError(t, err)
		require.Equal(t, int64(999), repo.GetID())
		require.Equal(t, "pre-fetched-repo", repo.GetName())
		// Should NOT have called GetRepositoryByID
		require.False(t, gh.HasMethodCall("GetRepositoryByID"))
		require.NotNil(t, user)
		require.NotNil(t, owner)
	})

	t.Run("returns same user as owner when IDs match", func(t *testing.T) {
		gh := &github.NoopClient{}
		user, _, owner, err := hydrateRequirements(ctx, gh, 100, 200, 100, nil)
		require.NoError(t, err)
		require.Equal(t, user, owner, "user and owner should be the same object when IDs match")
	})

	t.Run("fetches separate owner when IDs differ", func(t *testing.T) {
		gh := &github.NoopClient{}
		user, _, owner, err := hydrateRequirements(ctx, gh, 100, 200, 300, nil)
		require.NoError(t, err)
		require.NotEqual(t, user.GetID(), owner.GetID())
	})
}

func TestAddTenantContext(t *testing.T) {
	t.Run("adds tenant slug and ID to context", func(t *testing.T) {
		ctx := requestctx.NewContext(context.Background())
		err := addTenantContext(ctx, "test-slug", "test-id")
		require.NoError(t, err)
		require.Equal(t, "test-slug", requestctx.TenantSlug(ctx))
		require.Equal(t, "test-id", requestctx.TenantID(ctx))
	})

	t.Run("skips empty tenant slug", func(t *testing.T) {
		ctx := requestctx.NewContext(context.Background())
		err := addTenantContext(ctx, "", "test-id")
		require.NoError(t, err)
		require.Empty(t, requestctx.TenantSlug(ctx))
		require.Equal(t, "test-id", requestctx.TenantID(ctx))
	})

	t.Run("skips empty tenant ID", func(t *testing.T) {
		ctx := requestctx.NewContext(context.Background())
		err := addTenantContext(ctx, "test-slug", "")
		require.NoError(t, err)
		require.Equal(t, "test-slug", requestctx.TenantSlug(ctx))
		require.Empty(t, requestctx.TenantID(ctx))
	})

	t.Run("skips both when empty", func(t *testing.T) {
		ctx := requestctx.NewContext(context.Background())
		err := addTenantContext(ctx, "", "")
		require.NoError(t, err)
		require.Empty(t, requestctx.TenantSlug(ctx))
		require.Empty(t, requestctx.TenantID(ctx))
	})
}

func TestCreateJobForAssignment(t *testing.T) {
	obsv := observability.NewNoopExporters()

	var setupServiceWithDeps func(t *testing.T, ffFlags map[string]bool, expClient experiments.Client, opts ...func(*githubtwirp.NoopClient)) (*Service, *memory.Store, *aqueduct.MemoryClient)

	setupService := func(t *testing.T, opts ...func(*githubtwirp.NoopClient)) (*Service, *memory.Store, *aqueduct.MemoryClient) {
		return setupServiceWithDeps(t, nil, nil, opts...)
	}

	setupServiceWithFlags := func(t *testing.T, ffFlags map[string]bool, opts ...func(*githubtwirp.NoopClient)) (*Service, *memory.Store, *aqueduct.MemoryClient) {
		return setupServiceWithDeps(t, ffFlags, nil, opts...)
	}

	setupServiceWithExperiments := func(t *testing.T, expClient experiments.Client, opts ...func(*githubtwirp.NoopClient)) (*Service, *memory.Store, *aqueduct.MemoryClient) {
		return setupServiceWithDeps(t, nil, expClient, opts...)
	}

	setupServiceWithDeps = func(t *testing.T, ffFlags map[string]bool, expClient experiments.Client, opts ...func(*githubtwirp.NoopClient)) (*Service, *memory.Store, *aqueduct.MemoryClient) {
		t.Helper()

		ffClient := featureflags.NewNoopClient(ffFlags)
		capiClient, store, noopTwirp, _, defaultExp, queue, limiter := commonServiceDependencies(obsv)
		if expClient == nil {
			expClient = defaultExp
		}

		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}
		for _, opt := range opts {
			opt(noopTwirp)
		}

		ghf := &github.NoopClientFactory{}
		spokes := spokestest.NewClient(t)
		agapp := agenticapptest.NewTestProvider(t)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopTwirp, ffClient)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, expClient, caSvc, "test_name", "test@example.com", spokes, agapp, nil)
		return service, store, aq
	}

	t.Run("creates job for existing assignment", func(t *testing.T) {
		service, store, aq := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "test-assignment-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "test-assignment-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.NoError(t, err)
		require.NotNil(t, result)
		require.NotEmpty(t, result.Job.ID)
		require.NotEmpty(t, result.SessionID)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)

		job, err := store.GetJob(ctx, 789, 456, result.Job.ID)
		require.NoError(t, err)
		require.Equal(t, "test-assignment-uuid", job.AssignmentID)
		require.Equal(t, "Fix the bug", job.ProblemStatement.Content)
	})

	t.Run("propagates 401 without per-site retry since ClientFactory handles retries", func(t *testing.T) {
		service, store, _ := setupServiceWithFlags(t, map[string]bool{
			featureflags.CopilotSWEAgentClientTokenRefreshOn401: true,
		})
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "retry-on-401-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		baseFactory := &github.NoopClientFactory{}
		trackingFactory := &retryTrackingClientFactory{NoopClientFactory: baseFactory}
		newClientCalls := 0
		baseFactory.MockNewClientFromRepo = func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
			newClientCalls++
			// Always return a client that fails with 401 — the factory-level
			// retry wrapper is not present in this NoopClientFactory so we
			// expect the error to propagate directly.
			return &github.NoopClient{
				MockGetUserByID: func(context.Context, uint64) (*gg.User, error) {
					resp := &gg.Response{Response: &http.Response{StatusCode: http.StatusUnauthorized}}
					return nil, github.NewGitHubAPIError(resp, "bad credentials", errors.New("bad credentials"))
				},
			}, nil
		}
		service.ghf = trackingFactory

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "retry-on-401-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.Error(t, err)
		require.Nil(t, result)
		// Only one client is created — no per-site retry
		require.Equal(t, 1, newClientCalls)
		// No invalidation at this layer; that's handled by the ClientFactory wrapper
		require.Equal(t, 0, trackingFactory.invalidateCalls)
	})

	t.Run("retries hydration on 401 when token-refresh transport flag is disabled", func(t *testing.T) {
		service, store, aq := setupServiceWithFlags(t, map[string]bool{
			featureflags.CopilotSWEAgentClientTokenRefreshOn401: false,
		})
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "retry-on-401-flag-off-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		baseFactory := &github.NoopClientFactory{}
		trackingFactory := &retryTrackingClientFactory{NoopClientFactory: baseFactory}
		newClientCalls := 0
		baseFactory.MockNewClientFromRepo = func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
			newClientCalls++
			if newClientCalls == 1 {
				return &github.NoopClient{
					MockGetUserByID: func(context.Context, uint64) (*gg.User, error) {
						resp := &gg.Response{Response: &http.Response{StatusCode: http.StatusUnauthorized}}
						return nil, github.NewGitHubAPIError(resp, "bad credentials", errors.New("bad credentials"))
					},
				}, nil
			}
			return &github.NoopClient{}, nil
		}
		service.ghf = trackingFactory

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "retry-on-401-flag-off-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, 2, newClientCalls)
		require.Equal(t, 1, trackingFactory.invalidateCalls)
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("does not invalidate or retry on non-401 hydration errors", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "no-retry-non-401-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		baseFactory := &github.NoopClientFactory{}
		trackingFactory := &retryTrackingClientFactory{NoopClientFactory: baseFactory}
		newClientCalls := 0
		baseFactory.MockNewClientFromRepo = func(_ context.Context, _, _ int64) (github.ClientInterface, error) {
			newClientCalls++
			resp := &gg.Response{Response: &http.Response{StatusCode: http.StatusForbidden}}
			return &github.NoopClient{
				MockGetUserByID: func(context.Context, uint64) (*gg.User, error) {
					return nil, github.NewGitHubAPIError(resp, "forbidden", errors.New("forbidden"))
				},
			}, nil
		}
		service.ghf = trackingFactory

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "no-retry-non-401-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.Error(t, err)
		require.Nil(t, result)
		require.Equal(t, 1, newClientCalls)
		require.Equal(t, 0, trackingFactory.invalidateCalls)
	})

	t.Run("returns error when agent not enabled", func(t *testing.T) {
		service, store, _ := setupService(t, func(nc *githubtwirp.NoopClient) {
			nc.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
				return false, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: false}, nil
			}
		})
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "disabled-agent-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "disabled-agent-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.Error(t, err)
		require.Nil(t, result)
		require.ErrorIs(t, err, ErrAgentNotEnabled)
	})

	t.Run("enablement-exempt agent bypasses disallow gate", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		capiClient, store, noopTwirp, _, exp, queue, limiter := commonServiceDependencies(obsv)

		// Monolith says agent is NOT enabled (copilot_swe_agent_disallow is set).
		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return false, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: false}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}

		ghf := &github.NoopClientFactory{}
		spokes := spokestest.NewClient(t)
		exemptApp := agenticapptest.NewTestApp(88888).WithEnablementExempt().WithGlobalApp()
		agapp := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, exemptApp)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopTwirp, ffClient)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agapp, nil)

		ctx := requestctx.NewContext(context.Background())
		assignment := &jobs.Assignment{
			ID:      "exempt-enablement-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AgentID:          88888,
			AssignmentID:     "exempt-enablement-uuid",
			ProblemStatement: "Review the code",
		})
		require.NoError(t, err)
		require.NotNil(t, result)
		require.NotEmpty(t, result.Job.ID)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("returns error when actor is a bot", func(t *testing.T) {
		ghf := &github.NoopClientFactory{
			MockGetUserByID: func(ctx context.Context, id uint64) (*gg.User, error) {
				return &gg.User{
					ID:    gg.Ptr(int64(id)),
					Login: gg.Ptr("my-app[bot]"),
					Type:  gg.Ptr("Bot"),
				}, nil
			},
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentRejectBotActors: true,
		})
		capiClient, store, noopTwirp, _, exp, queue, limiter := commonServiceDependencies(obsv)
		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}

		spokes := spokestest.NewClient(t)
		agapp := agenticapptest.NewTestProvider(t)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopTwirp, ffClient)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agapp, nil)

		ctx := requestctx.NewContext(context.Background())
		assignment := &jobs.Assignment{
			ID:      "bot-actor-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "bot-actor-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.Error(t, err)
		require.Nil(t, result)
		require.ErrorIs(t, err, ErrBotActorNotAllowed)

		// Verify no job was queued
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)
	})

	t.Run("skips quota check when agent is quota exempt", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: true,
		})
		capiClient, store, noopTwirp, _, exp, queue, limiter := commonServiceDependencies(obsv)

		// IsAgentEnabled is still called for config — returns enabled.
		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}

		ghf := &github.NoopClientFactory{}
		spokes := spokestest.NewClient(t)
		thirdPartyApp := agenticapptest.NewTestApp(99999).WithQuotaExempt()
		agapp := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, thirdPartyApp)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopTwirp, ffClient)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agapp, nil)

		ctx := requestctx.NewContext(context.Background())
		assignment := &jobs.Assignment{
			ID:      "exempt-agent-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "exempt-agent-uuid",
			AgentID:          99999,
			ProblemStatement: "Fix the bug",
		})
		require.NoError(t, err)
		require.NotNil(t, result)
	})

	t.Run("returns error when assignment does not exist", func(t *testing.T) {
		service, _, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "nonexistent-assignment",
			ProblemStatement: "Fix the bug",
		})
		require.Error(t, err)
		require.Nil(t, result)
		require.Contains(t, err.Error(), "failed to get assignment")
	})

	t.Run("inherits CanWriteWorkflows from previous job", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "workflows-inherit-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		falseVal := false
		previousJob := &jobs.Job{
			ID:                "workflows-inherit-prev",
			OwnerID:           789,
			RepoID:            456,
			AssignmentID:      assignment.ID,
			Status:            jobs.JobStatusCompleted,
			CreatedAt:         time.Now().Add(-time.Hour).Unix(),
			CanWriteWorkflows: &falseVal,
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "workflows-inherit-uuid",
			ProblemStatement: "Follow-up fix",
		})
		require.NoError(t, err)
		require.NotNil(t, result.Job.CanWriteWorkflows, "should inherit from prior job")
		require.False(t, *result.Job.CanWriteWorkflows)
	})

	t.Run("does not set CanWriteWorkflows when no prior job has a checked value", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "workflows-noinherit-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "workflows-noinherit-prev",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "workflows-noinherit-uuid",
			ProblemStatement: "Follow-up fix",
		})
		require.NoError(t, err)
		require.Nil(t, result.Job.CanWriteWorkflows)
	})

	t.Run("inherits older non-nil CanWriteWorkflows over newer nil (stuck-nil mitigation)", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "workflows-stuck-nil-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		trueVal := true
		olderJob := &jobs.Job{
			ID:                "workflows-stuck-nil-older",
			OwnerID:           789,
			RepoID:            456,
			AssignmentID:      assignment.ID,
			Status:            jobs.JobStatusCompleted,
			CreatedAt:         time.Now().Add(-2 * time.Hour).Unix(),
			CanWriteWorkflows: &trueVal,
		}
		_, err = store.CreateJob(ctx, olderJob)
		require.NoError(t, err)

		newerNilJob := &jobs.Job{
			ID:           "workflows-stuck-nil-newer",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = store.CreateJob(ctx, newerNilJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "workflows-stuck-nil-uuid",
			ProblemStatement: "Follow-up fix",
		})
		require.NoError(t, err)
		require.NotNil(t, result.Job.CanWriteWorkflows, "should fall back to older non-nil value")
		require.True(t, *result.Job.CanWriteWorkflows)
	})

	t.Run("does not inherit CanWriteWorkflows from prior job belonging to a different agent", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "workflows-other-agent-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		falseVal := false
		otherAgentJob := &jobs.Job{
			ID:                "workflows-other-agent-prev",
			OwnerID:           789,
			RepoID:            456,
			AssignmentID:      assignment.ID,
			Status:            jobs.JobStatusCompleted,
			CreatedAt:         time.Now().Add(-time.Hour).Unix(),
			AgentID:           999_999, // different from test app ID (0)
			CanWriteWorkflows: &falseVal,
		}
		_, err = store.CreateJob(ctx, otherAgentJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "workflows-other-agent-uuid",
			ProblemStatement: "Follow-up fix",
		})
		require.NoError(t, err)
		require.Nil(t, result.Job.CanWriteWorkflows,
			"must not adopt another agent's workflow-scope decision")
	})

	t.Run("inherits model from previous job when model not specified", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "model-inherit-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-job",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "model-inherit-uuid",
			ProblemStatement: "Follow-up fix",
		})
		require.NoError(t, err)
		require.Equal(t, "sweagent-capi:gpt-4o", result.Job.Model)
	})

	t.Run("inherits event type from latest job on resume when not specified", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "resume-event-type-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:               "previous-interval-job",
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     assignment.ID,
			EventType:        jobs.EventTypeIntervalTriggered,
			ProblemStatement: jobs.ProblemStatement{Content: "say hello"},
			Status:           jobs.JobStatusCompleted,
			CreatedAt:        time.Now().Add(-time.Hour).Unix(),
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:         123,
			OwnerID:         789,
			RepoID:          456,
			AssignmentID:    "resume-event-type-uuid",
			ResumeSessionID: "session-to-resume",
		})
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypeIntervalTriggered, result.Job.EventType)
	})

	t.Run("does not inherit event type from latest job when not resuming", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "no-resume-event-type-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-interval-job-no-resume",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			EventType:    jobs.EventTypeIntervalTriggered,
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "no-resume-event-type-uuid",
			ProblemStatement: "Follow-up fix",
		})
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypeAPICallReceived, result.Job.EventType)
	})

	t.Run("uses requested model over previous job model", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "model-override-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-job-override",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "model-override-uuid",
			Model:            "claude-sonnet",
			ProblemStatement: "Fix with specific model",
		})
		require.NoError(t, err)
		// Requested model "claude-sonnet" is restricted for this plan, so DetermineModel
		// falls back to auto rather than reusing the previous job's model.
		require.Equal(t, capi.AutoMode, result.Job.Model)
	})

	t.Run("inherits branch from previous job when no features", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "branch-inherit-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-job-with-branch",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			BranchName:   "copilot/fix-bug-123",
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "branch-inherit-uuid",
			ProblemStatement: "Continue working",
		})
		require.NoError(t, err)
		require.Equal(t, "copilot/fix-bug-123", result.Job.BranchName)
		require.Equal(t, "main", result.Job.BaseCommit, "should use default branch as base when previous job has no BaseCommit")
		require.Nil(t, result.Job.Features.Branch)
		require.Nil(t, result.Job.Features.PullRequest)
	})

	t.Run("creates branch when no features and no previous job", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "new-branch-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "new-branch-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.NoError(t, err)
		require.NotNil(t, result.Job.Features.Branch)
		require.NotEmpty(t, result.Job.BranchName)
	})

	t.Run("creates job with explicit features", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "features-test-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:      123,
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: "features-test-uuid",
			Features: jobs.EnvironmentFeatures{
				Branch: &jobs.BranchFeature{
					Name:    "feature/my-branch",
					BaseRef: "develop",
				},
			},
			HasFeatures:      true,
			ProblemStatement: "Fix with features",
		})
		require.NoError(t, err)
		require.NotNil(t, result.Job.Features.Branch)
		require.Equal(t, "feature/my-branch", result.Job.Features.Branch.Name)
		require.Equal(t, "develop", result.Job.Features.Branch.BaseRef)
	})

	t.Run("CCR jobs always go branchless", func(t *testing.T) {
		const ccrAppID = int64(946600)

		ffClient := featureflags.NewNoopClient(nil)
		capiClient, store, noopTwirp, _, exp, queue, limiter := commonServiceDependencies(obsv)

		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}

		ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
		agapp := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

		ghf := &github.NoopClientFactory{}
		spokes := spokestest.NewClient(t)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), noopTwirp, ffClient)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agapp, nil)

		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "ccr-branchless-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "ccr-branchless-uuid",
			AgentID:          ccrAppID,
			HasFeatures:      true,
			Features:         jobs.EnvironmentFeatures{},
			ProblemStatement: "Code review by Copilot",
		})
		require.NoError(t, err)
		require.Nil(t, result.Job.Features.Branch)
		require.Nil(t, result.Job.Features.PullRequest)
		require.Empty(t, result.Job.BranchName)
	})

	t.Run("creates job with event fields", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "event-fields-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "event-fields-uuid",
			ProblemStatement: "Fix with events",
			EventType:        string(jobs.EventTypeIssueAssignment),
			EventURL:         "https://github.com/test-owner/test-repo/issues/1",
			EventIdentifiers: []string{"issue:1"},
			EventContent:     "Event content",
		})
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypeIssueAssignment, result.Job.EventType)
		require.Equal(t, "https://github.com/test-owner/test-repo/issues/1", result.Job.EventURL)
		require.Equal(t, []string{"issue:1"}, result.Job.EventIdentifiers)
		require.Equal(t, "Event content", result.Job.EventContent)
	})

	t.Run("defaults event type to api_call_received", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "default-event-type-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "default-event-type-uuid",
			ProblemStatement: "Fix the bug",
		})
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypeAPICallReceived, result.Job.EventType)
	})

	t.Run("sets PR placeholders when creating new pull request", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "pr-placeholder-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:      123,
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: "pr-placeholder-uuid",
			Features: jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{},
			},
			HasFeatures:      true,
			ProblemStatement: "Fix the bug",
		})
		require.NoError(t, err)
		require.NotNil(t, result.Job.Features.PullRequest)
		assert.Equal(t, "[WIP] Copilot Request", result.Job.Features.PullRequest.TitlePlaceholder)
		assert.Contains(t, result.Job.Features.PullRequest.BodyPlaceholder, PRBodyPrefix)
		assert.Contains(t, result.Job.Features.PullRequest.BodyPlaceholder, "Fix the bug")
	})

	t.Run("assigns experiments using the created PR ID", func(t *testing.T) {
		mockClient := &experiments.MockClient{
			MockAssignment: &experiments.Assignment{
				Variation: "enabled",
				Context:   "assignment-context",
			},
			MockOK: true,
		}
		service, store, _ := setupServiceWithExperiments(t, mockClient)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "experiment-pr-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:      123,
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: "experiment-pr-uuid",
			Features: jobs.EnvironmentFeatures{
				PullRequest: &jobs.PullRequestFeature{},
			},
			HasFeatures:      true,
			ProblemStatement: "Fix with experiment assignment",
		})
		require.NoError(t, err)
		require.NotZero(t, result.Job.PullRequestID)
		require.NotNil(t, result.Job.Experiments)
		require.Equal(t, "assignment-context", result.Job.Experiments.AssignmentContext)
		require.Equal(t, "enabled", result.Job.Experiments.Variations[experiments.ModelCompareExperiment])

		randomizationUnit := mockClient.GetFeatureAssignmentRandomizationUnit(experiments.ModelCompareExperiment)
		require.NotNil(t, randomizationUnit)
		assert.Equal(t, experiments.GitHubPullRequestIDHeader, randomizationUnit.Header)
		assert.Equal(t, strconv.FormatInt(result.Job.PullRequestID, 10), randomizationUnit.Value)
	})

	t.Run("tenant context is added from enablement check", func(t *testing.T) {
		var capturedTenantSlug, capturedTenantID string

		service, store, _ := setupService(t, func(nc *githubtwirp.NoopClient) {
			nc.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
				return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
					TenantSlug:     "org-slug",
					TenantId:       "tenant-123",
				}, nil
			}
			nc.NoopSweagentdAPI.MockIsBypassActor = func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
				capturedTenantSlug = requestctx.TenantSlug(ctx)
				capturedTenantID = requestctx.TenantID(ctx)
				return &sweagentdTwirp.IsBypassActorResponse{IsBypassActor: false}, nil
			}
		})
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "tenant-ctx-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "tenant-ctx-uuid",
			ProblemStatement: "Fix with tenant",
		})
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, "org-slug", capturedTenantSlug)
		require.Equal(t, "tenant-123", capturedTenantID)
	})

	t.Run("tenant context is not added from enablement check when headers-only flag enabled", func(t *testing.T) {
		var capturedTenantSlug, capturedTenantID string

		service, store, _ := setupServiceWithFlags(t, map[string]bool{
			featureflags.CopilotSWEAgentTwirpProximaHookHeadersOnly: true,
		}, func(nc *githubtwirp.NoopClient) {
			nc.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
				return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
					TenantSlug:     "org-slug",
					TenantId:       "tenant-123",
				}, nil
			}
			nc.NoopSweagentdAPI.MockIsBypassActor = func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
				capturedTenantSlug = requestctx.TenantSlug(ctx)
				capturedTenantID = requestctx.TenantID(ctx)
				return &sweagentdTwirp.IsBypassActorResponse{IsBypassActor: false}, nil
			}
		})
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "tenant-ctx-headers-only-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "tenant-ctx-headers-only-uuid",
			ProblemStatement: "Fix with tenant",
		})
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Empty(t, capturedTenantSlug)
		require.Empty(t, capturedTenantID)
	})

	t.Run("inherits custom agent from previous job when not specified", func(t *testing.T) {
		// Reproduces github/sweagentd#12007: follow-up tasks in the Agents tab silently fall
		// back to the default Copilot agent when the request omits the custom agent name.
		ffClient := featureflags.NewNoopClient(nil)
		capiClient, store, noopTwirp, _, exp, queue, limiter := commonServiceDependencies(obsv)

		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}
		// Treat the test repo as a regular repo (not the enterprise agents source) so the
		// custom agent lookup uses the .github/agents directory.
		noopTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("no enterprise agents repo")
		}

		// Set up a custom agent named "named-agent" in the repo so it can be re-resolved
		// (after the fix) when inherited on follow-ups via FromDB.
		const inheritRepoID = uint64(1)
		agentContents := map[string]string{
			"named-agent": `---
name: Named Test Agent
description: A named test agent configuration
tools: named-tool
---

You are a named agent.`,
		}
		caSpokes := customagenttest.MakeSpokesWithRepoAndCommitSHA(t, agentContents, "", inheritRepoID)
		caSvc := customagent.NewService(obsv, caSpokes, noopTwirp, ffClient)

		ghf := &github.NoopClientFactory{}
		spokes := spokestest.NewClient(t)
		agapp := agenticapptest.NewTestProvider(t)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agapp, nil)

		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "custom-agent-inherit-uuid",
			OwnerID: 789,
			RepoID:  int64(inheritRepoID),
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-job-with-custom-agent",
			OwnerID:      789,
			RepoID:       int64(inheritRepoID),
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        "named-agent",
				RepoOwner:   "test-owner",
				RepoOwnerID: 1,
				RepoName:    "test-repo",
				RepoID:      int64(inheritRepoID),
				DisplayName: "Named Test Agent",
				Description: "A named test agent configuration",
				Tools:       []string{"named-tool"},
				Scope:       "repository",
			},
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		// Follow-up call without specifying the custom agent — simulates what the monolith
		// sends today (it persists branch/model but not custom agent across follow-ups).
		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           int64(inheritRepoID),
			AssignmentID:     assignment.ID,
			ProblemStatement: "Continue working",
		})
		require.NoError(t, err)
		require.NotNil(t, result)

		job, err := store.GetJob(ctx, 789, int64(inheritRepoID), result.Job.ID)
		require.NoError(t, err)

		require.Equal(t, "named-agent", job.CustomAgent.Name,
			"follow-up job should inherit the custom agent from the previous job")
		require.False(t, job.CustomAgent.IsCopilot(),
			"follow-up job should not silently fall back to default Copilot agent")
	})

	t.Run("does not inherit custom agent from previous job when custom agents are disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentsDisallow: true,
		})
		capiClient, store, noopTwirp, _, exp, queue, limiter := commonServiceDependencies(obsv)

		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}
		noopTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("no enterprise agents repo")
		}

		const inheritRepoID = uint64(1)
		agentContents := map[string]string{
			"named-agent": `---
name: Named Test Agent
description: A named test agent configuration
tools: named-tool
---

You are a named agent.`,
		}
		caSpokes := customagenttest.MakeSpokesWithRepoAndCommitSHA(t, agentContents, "", inheritRepoID)
		caSvc := customagent.NewService(obsv, caSpokes, noopTwirp, ffClient)

		ghf := &github.NoopClientFactory{}
		spokes := spokestest.NewClient(t)
		agapp := agenticapptest.NewTestProvider(t)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agapp, nil)

		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "custom-agent-disabled-inherit-uuid",
			OwnerID: 789,
			RepoID:  int64(inheritRepoID),
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-job-custom-agent-disabled",
			OwnerID:      789,
			RepoID:       int64(inheritRepoID),
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        "named-agent",
				RepoOwner:   "test-owner",
				RepoOwnerID: 1,
				RepoName:    "test-repo",
				RepoID:      int64(inheritRepoID),
				DisplayName: "Named Test Agent",
				Description: "A named test agent configuration",
				Tools:       []string{"named-tool"},
				Scope:       agentconfig.ScopeRepository,
			},
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           int64(inheritRepoID),
			AssignmentID:     assignment.ID,
			ProblemStatement: "Continue working",
		})
		require.NoError(t, err)
		require.NotNil(t, result)

		job, err := store.GetJob(ctx, 789, int64(inheritRepoID), result.Job.ID)
		require.NoError(t, err)
		require.True(t, job.CustomAgent.IsCopilot(),
			"follow-up job should fall back to default Copilot agent when custom agents are disabled")
	})

	t.Run("follow-up inheritance enforces user-invocable policy", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		capiClient, store, noopTwirp, _, exp, queue, limiter := commonServiceDependencies(obsv)

		noopTwirp.MockIsAgentEnabled = func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		}
		noopTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:                  req.Id,
					AnalyticsTrackingId: "test-tracking-id",
				},
			}, nil
		}
		noopTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
			return nil, twirp.NotFoundError("no enterprise agents repo")
		}

		const inheritRepoID = uint64(1)
		agentContents := map[string]string{
			"event-only-agent": `---
name: Event Only Agent
description: An agent that can only be triggered by events
user-invocable: false
---

You are an event-only agent.`,
		}
		caSpokes := customagenttest.MakeSpokesWithRepoAndCommitSHA(t, agentContents, "", inheritRepoID)
		caSvc := customagent.NewService(obsv, caSpokes, noopTwirp, ffClient)

		ghf := &github.NoopClientFactory{}
		spokes := spokestest.NewClient(t)
		agapp := agenticapptest.NewTestProvider(t)

		aq := queue.(*aqueduct.MemoryClient)
		service := New(obsv, ffClient, store, capiClient, ghf, noopTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agapp, nil)

		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "custom-agent-user-invocable-inherit-uuid",
			OwnerID: 789,
			RepoID:  int64(inheritRepoID),
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-job-event-only-agent",
			OwnerID:      789,
			RepoID:       int64(inheritRepoID),
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
			CustomAgent: jobsCustomAgent.DBRecord{
				Name:        "event-only-agent",
				RepoOwner:   "test-owner",
				RepoOwnerID: 1,
				RepoName:    "test-repo",
				RepoID:      int64(inheritRepoID),
				DisplayName: "Event Only Agent",
				Description: "An agent that can only be triggered by events",
				Tools:       []string{"*"},
				Scope:       agentconfig.ScopeRepository,
			},
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           int64(inheritRepoID),
			AssignmentID:     assignment.ID,
			ProblemStatement: "Continue working",
		})
		require.Error(t, err)
		require.Nil(t, result)
		require.ErrorIs(t, err, ErrAgentNotUserInvocable)
	})

	t.Run("does not inherit when previous job has default Copilot agent", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "no-inherit-copilot-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		previousJob := &jobs.Job{
			ID:           "previous-job-copilot",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
			// Default Copilot agent (empty Name).
		}
		_, err = store.CreateJob(ctx, previousJob)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     assignment.ID,
			ProblemStatement: "Continue with default agent",
		})
		require.NoError(t, err)
		require.NotNil(t, result)

		job, err := store.GetJob(ctx, 789, 456, result.Job.ID)
		require.NoError(t, err)

		require.True(t, job.CustomAgent.IsCopilot(),
			"follow-up job should remain on default Copilot agent")
	})

	t.Run("does not inherit when assignment has no previous job", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "no-previous-job-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     assignment.ID,
			ProblemStatement: "First job in assignment",
		})
		require.NoError(t, err)
		require.NotNil(t, result)

		job, err := store.GetJob(ctx, 789, 456, result.Job.ID)
		require.NoError(t, err)

		require.True(t, job.CustomAgent.IsCopilot(),
			"first job in assignment should default to Copilot when no custom agent specified")
	})

	t.Run("trims whitespace from problem statement", func(t *testing.T) {
		service, store, _ := setupService(t)
		ctx := requestctx.NewContext(context.Background())

		assignment := &jobs.Assignment{
			ID:      "trim-ps-uuid",
			OwnerID: 789,
			RepoID:  456,
		}
		_, err := store.UpsertAssignment(ctx, assignment)
		require.NoError(t, err)

		result, err := service.CreateJobForAssignment(ctx, &CreateJobForAssignmentParams{
			ActorID:          123,
			OwnerID:          789,
			RepoID:           456,
			AssignmentID:     "trim-ps-uuid",
			ProblemStatement: "  Fix the bug  ",
		})
		require.NoError(t, err)
		require.Equal(t, "Fix the bug", result.Job.ProblemStatement.Content)
	})
}
