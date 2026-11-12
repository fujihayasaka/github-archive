package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
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
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// testServerOptions allows customizing the test server setup.
type testServerOptions struct {
	// githubClient allows overriding the default github.NoopClient.
	// If nil, a default NoopClient is used.
	githubClient *github.NoopClient
	// spokesClient allows overriding the default spokes client.
	// If nil, a default spokestest.Client is used.
	spokesClient *spokestest.Client
	// featureFlags allows overriding the default feature flags.
	// If nil, an empty map is used (all flags disabled).
	featureFlags map[string]bool
	// limiterAPI allows overriding the default NoopLimiterAPI.
	// If nil, a default NoopLimiterAPI is used.
	limiterAPI *githubtwirp.NoopLimiterAPI
	// billingCanProceed controls the billing mock's CanProceedWithUsage response.
	// Defaults to true if not explicitly set.
	billingCanProceed *bool
	// appProvider allows overriding the default agenticapp.Provider.
	// If nil, a default test provider is used.
	appProvider *agenticapp.Provider
}

// testServerOption is a functional option for configuring setupTestServer.
type testServerOption func(*testServerOptions)

// withGitHubClient sets a custom GitHub client for testing.
func withGitHubClient(gh *github.NoopClient) testServerOption {
	return func(opts *testServerOptions) {
		opts.githubClient = gh
	}
}

// withSpokesClient sets a custom spokes client for testing.
func withSpokesClient(spokes *spokestest.Client) testServerOption {
	return func(opts *testServerOptions) {
		opts.spokesClient = spokes
	}
}

// withFeatureFlags sets custom feature flags for testing.
func withFeatureFlags(flags map[string]bool) testServerOption {
	return func(opts *testServerOptions) {
		opts.featureFlags = flags
	}
}

// withLimiterAPI sets a custom limiter API for testing.
func withLimiterAPI(limiter *githubtwirp.NoopLimiterAPI) testServerOption {
	return func(opts *testServerOptions) {
		opts.limiterAPI = limiter
	}
}

// withBillingCanProceed sets whether the billing mock allows usage.
func withBillingCanProceed(canProceed bool) testServerOption {
	return func(opts *testServerOptions) {
		opts.billingCanProceed = &canProceed
	}
}

// withAppProvider sets a custom agenticapp.Provider for testing.
func withAppProvider(provider *agenticapp.Provider) testServerOption {
	return func(opts *testServerOptions) {
		opts.appProvider = provider
	}
}

func setupTestServer(t *testing.T, opts ...testServerOption) (*Server, *memory.Store, *aqueduct.MemoryClient, *githubtwirp.NoopClient) {
	t.Helper()

	options := &testServerOptions{}
	for _, opt := range opts {
		opt(options)
	}

	// Set up billing mock
	billingCanProceed := true
	if options.billingCanProceed != nil {
		billingCanProceed = *options.billingCanProceed
	}
	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: billingCanProceed,
	}, nil)

	limiterAPI := options.limiterAPI
	if limiterAPI == nil {
		limiterAPI = &githubtwirp.NoopLimiterAPI{}
	}

	mockGhTwirp := &githubtwirp.NoopClient{
		MockIsAgentEnabled: func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
			return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
		},
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: true,
			},
			MockIsBypassActor: func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
				return &sweagentdTwirp.IsBypassActorResponse{IsBypassActor: false}, nil
			},
		},
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						Id:                  123,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI:    limiterAPI,
		NoopBillingClient: mockBillingClient,
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(options.featureFlags)

	gh := options.githubClient
	if gh == nil {
		gh = &github.NoopClient{}
	}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}

	spokes := options.spokesClient
	if spokes == nil {
		spokes = spokestest.NewClient(t)
	}

	agapp := options.appProvider
	if agapp == nil {
		agapp = agenticapptest.NewTestProvider(t)
	}
	jobStore := memory.NewStore()
	countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokes, agapp, nil)

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agapp, nil, nil, nil, nil)

	return server, jobStore, aq, mockGhTwirp
}

func TestCreateJobForAssignment(t *testing.T) {
	t.Run("creates job for existing assignment", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "789-456-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug in existing assignment",
			AssignmentId:     "789-456-test-uuid",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)
		require.NotEmpty(t, resp.SessionId)

		// Verify that a job was queued for execution
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)

		// Verify that the job was created in the store with the correct assignment ID
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, req.AssignmentId, job.AssignmentID)
		require.Equal(t, req.ProblemStatement, job.ProblemStatement.Content)
	})

	// Test that tenant context is correctly added from IsAgentEnabled response
	t.Run("success_adds_tenant_context", func(t *testing.T) {
		expectedTenantSlug := "test-org-slug"
		expectedTenantID := "tenant-789"

		// Set up billing mock
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)

		// Capture the context after tenant context is added
		var capturedTenantSlug, capturedTenantID string
		mockGhTwirp := &githubtwirp.NoopClient{
			MockIsAgentEnabled: func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
				return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
					TenantSlug:     expectedTenantSlug,
					TenantId:       expectedTenantID,
				}, nil
			},
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				MockIsBypassActor: func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
					// Capture tenant context from the request context at this point
					capturedTenantSlug = requestctx.TenantSlug(ctx)
					capturedTenantID = requestctx.TenantID(ctx)
					return &sweagentdTwirp.IsBypassActorResponse{IsBypassActor: false}, nil
				},
			},
			NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
				MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{
							Id:                  123,
							AnalyticsTrackingId: "test-tracking-id",
						},
					}, nil
				},
			},
			NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
			NoopBillingClient: mockBillingClient,
		}

		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return gh
			},
		}

		agapp := agenticapptest.NewTestProvider(t)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), agapp, nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agapp, nil, nil, nil, nil)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "tenant-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			AssignmentId:     "tenant-test-uuid",
		}

		// Use a context with requestctx initialized (simulating what ServerHooks does)
		ctx := requestctx.NewContext(t.Context())

		resp, err := server.CreateJobForAssignment(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		// Validate that tenant context was correctly added
		require.Equal(t, expectedTenantSlug, capturedTenantSlug, "TenantSlug should be added to context")
		require.Equal(t, expectedTenantID, capturedTenantID, "TenantID should be added to context")
	})

	t.Run("validates assignment exists for invalid format", func(t *testing.T) {
		server, _, _, _ := setupTestServer(t)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			AssignmentId:     "invalid-format", // Invalid format
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)

		// Check that it's a proper twirp NotFound error about assignment not found
		var twirpErr twirp.Error
		require.ErrorAs(t, err, &twirpErr)
		require.Equal(t, twirp.NotFound, twirpErr.Code())
		require.Contains(t, twirpErr.Msg(), "assignment not found")
	})

	t.Run("validates assignment exists", func(t *testing.T) {
		server, _, _, _ := setupTestServer(t)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			AssignmentId:     "nonexistent-assignment", // Assignment doesn't exist
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)

		// Check that it's a proper twirp NotFound error about assignment not found
		var twirpErr twirp.Error
		require.ErrorAs(t, err, &twirpErr)
		require.Equal(t, twirp.NotFound, twirpErr.Code())
		require.Contains(t, twirpErr.Msg(), "assignment not found")
	})

	t.Run("rejects bot actor with InvalidArgument", func(t *testing.T) {
		botGH := &github.NoopClient{
			MockGetUserByID: func(ctx context.Context, id uint64) (*gg.User, error) {
				return &gg.User{
					ID:    gg.Ptr(int64(id)),
					Login: gg.Ptr("my-app[bot]"),
					Type:  gg.Ptr("Bot"),
				}, nil
			},
		}
		server, jobStore, aq, _ := setupTestServer(t, withGitHubClient(botGH), withFeatureFlags(map[string]bool{
			featureflags.CopilotSWEAgentRejectBotActors: true,
		}))

		assignment := &jobs.Assignment{
			ID:          "bot-actor-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			AssignmentId:     "bot-actor-test-uuid",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)

		var twirpErr twirp.Error
		require.ErrorAs(t, err, &twirpErr)
		require.Equal(t, twirp.InvalidArgument, twirpErr.Code())
		require.Contains(t, twirpErr.Msg(), "bot actors are not allowed")

		// Verify no job was queued
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)
	})

	t.Run("inherits model from previous job when model not specified", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "model-inherit-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		// Create a previous job with a specific model
		previousJob := &jobs.Job{
			ID:           "previous-job-id",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = jobStore.CreateJob(t.Context(), previousJob)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with inherited model",
			AssignmentId:     "model-inherit-test-uuid",
			// Model is intentionally not set
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the new job inherited the model from the previous job
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.Equal(t, "sweagent-capi:gpt-4o", job.Model, "new job should inherit model from previous job")

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("uses requested model over previous job model", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "model-override-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		// Create a previous job with a specific model
		previousJob := &jobs.Job{
			ID:           "previous-job-override-id",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = jobStore.CreateJob(t.Context(), previousJob)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with custom model",
			AssignmentId:     "model-override-test-uuid",
			Model:            "claude-sonnet", // Explicitly request a different model
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the new job uses the requested model, not the inherited one
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		// Requested model "claude-sonnet" is restricted for this plan, so DetermineModel
		// falls back to auto rather than reusing the previous job's model.
		require.Equal(t, "auto", job.Model, "new job should use auto when requested model is unavailable")

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("validates required fields", func(t *testing.T) {
		server, _, _, _ := setupTestServer(t)

		testCases := []struct {
			name          string
			req           *jobs_pb.CreateJobForAssignmentRequest
			expectedError string
		}{
			{
				name: "missing actor_id",
				req: &jobs_pb.CreateJobForAssignmentRequest{
					RepoId:           456,
					OwnerId:          789,
					ProblemStatement: "Fix the bug",
					AssignmentId:     "test-assignment",
				},
				expectedError: "actor_id",
			},
			{
				name: "missing owner_id",
				req: &jobs_pb.CreateJobForAssignmentRequest{
					ActorId:          123,
					RepoId:           456,
					ProblemStatement: "Fix the bug",
					AssignmentId:     "test-assignment",
				},
				expectedError: "owner_id",
			},
			{
				name: "missing repo_id",
				req: &jobs_pb.CreateJobForAssignmentRequest{
					ActorId:          123,
					OwnerId:          789,
					ProblemStatement: "Fix the bug",
					AssignmentId:     "test-assignment",
				},
				expectedError: "repo_id",
			},
			{
				name: "missing problem_statement",
				req: &jobs_pb.CreateJobForAssignmentRequest{
					ActorId:      123,
					RepoId:       456,
					OwnerId:      789,
					AssignmentId: "test-assignment",
				},
				expectedError: "problem_statement",
			},
			{
				name: "empty problem_statement",
				req: &jobs_pb.CreateJobForAssignmentRequest{
					ActorId:          123,
					RepoId:           456,
					OwnerId:          789,
					ProblemStatement: "   ",
					AssignmentId:     "test-assignment",
				},
				expectedError: "problem_statement",
			},
			{
				name: "missing assignment_id",
				req: &jobs_pb.CreateJobForAssignmentRequest{
					ActorId:          123,
					RepoId:           456,
					OwnerId:          789,
					ProblemStatement: "Fix the bug",
				},
				expectedError: "assignment_id",
			},
			{
				name: "empty assignment_id",
				req: &jobs_pb.CreateJobForAssignmentRequest{
					ActorId:          123,
					RepoId:           456,
					OwnerId:          789,
					ProblemStatement: "Fix the bug",
					AssignmentId:     "   ",
				},
				expectedError: "assignment_id",
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				resp, err := server.CreateJobForAssignment(t.Context(), tc.req)
				require.Error(t, err)
				require.Nil(t, resp)
				require.Contains(t, err.Error(), tc.expectedError)
			})
		}
	})

	t.Run("creates job with features", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "features-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with features",
			AssignmentId:     "features-test-uuid",
			Features: &jobs_pb.Features{
				Branch: &jobs_pb.BranchFeature{
					Name:    "feature/my-branch",
					BaseRef: "develop",
				},
			},
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)
		require.NotEmpty(t, resp.SessionId)

		// Verify the job has the correct features
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job.Features.Branch)
		require.Equal(t, "feature/my-branch", job.Features.Branch.Name)
		require.Equal(t, "develop", job.Features.Branch.BaseRef)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with event fields", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "event-fields-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with event fields",
			AssignmentId:     "event-fields-test-uuid",
			EventUrl:         "https://github.com/test-owner/test-repo/issues/1",
			EventIdentifiers: []string{"issue:1", "comment:123"},
			EventContent:     "This is the event content",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with event fields
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, req.EventUrl, job.EventURL)
		require.Equal(t, req.EventIdentifiers, job.EventIdentifiers)
		require.Equal(t, req.EventContent, job.EventContent)
		require.Equal(t, jobs.EventTypeAPICallReceived, job.EventType)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with branch when features is nil and no previous job", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "nil-features-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug without features",
			AssignmentId:     "nil-features-test-uuid",
			Features:         nil, // Explicitly nil
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)
		require.NotEmpty(t, resp.SessionId)

		// Verify the job was created with a branch (since there's no previous job to inherit from)
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		// Branch features should be set so a branch gets created
		require.NotNil(t, job.Features.Branch, "branch features should be set when no previous job to inherit from")
		require.Nil(t, job.Features.PullRequest)
		// Job should have a branch name
		require.NotEmpty(t, job.BranchName, "job should have a branch name")

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("inherits branch info from previous job when features is nil (follow-up session)", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "branch-inherit-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		// Create a previous job that has branch info (simulating initial task that created a branch)
		previousJob := &jobs.Job{
			ID:           "previous-job-with-branch",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			BranchName:   "copilot/fix-bug-123",
			BaseCommit:   "abc123def456", // This is the original base (e.g., main)
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = jobStore.CreateJob(t.Context(), previousJob)
		require.NoError(t, err)

		// Create a follow-up job with nil Features (this is what copilot-api sends for follow-up sessions)
		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Continue working on the bug",
			AssignmentId:     "branch-inherit-test-uuid",
			Features:         nil, // Explicitly nil - this is the follow-up session case
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		// Verify that the new job inherited the branch info from the previous job
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// The follow-up job should reuse the existing branch
		require.Equal(t, "copilot/fix-bug-123", job.BranchName,
			"follow-up job should inherit BranchName from previous job when Features is nil")
		// BaseCommit should be the original base (e.g., main) so PRs target the correct branch
		require.Equal(t, "abc123def456", job.BaseCommit,
			"follow-up job should retain the original base commit for PR targeting")

		// Features should still be nil/empty since we're reusing existing branch
		require.Nil(t, job.Features.Branch)
		require.Nil(t, job.Features.PullRequest)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates branch when previous job has no branch name", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "no-branch-previous-job-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		// Create a previous job that has NO branch info (edge case that can occur)
		previousJob := &jobs.Job{
			ID:           "previous-job-no-branch",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			BranchName:   "", // No branch name
			BaseCommit:   "",
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = jobStore.CreateJob(t.Context(), previousJob)
		require.NoError(t, err)

		// Create a follow-up job with nil Features
		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Continue working on the assignment",
			AssignmentId:     "no-branch-previous-job-uuid",
			Features:         nil, // Explicitly nil
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		// Verify that the new job has a branch created since the previous job had no branch
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Job should have a branch name even though previous job didn't have one
		require.NotEmpty(t, job.BranchName, "job should have a branch name when previous job has no branch")
		// Branch features should be set so a branch gets created
		require.NotNil(t, job.Features.Branch, "branch features should be set when previous job has no branch")

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("rejects duplicate job when assignment already has a running job", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t,
			withFeatureFlags(map[string]bool{
				featureflags.CopilotSWEAgentDedupJobCreation: true,
			}),
		)

		assignment := &jobs.Assignment{
			ID:          "dedup-running-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		runningJob := &jobs.Job{
			ID:           "already-running-job",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			BranchName:   "copilot/in-progress-fix",
			Status:       jobs.JobStatusRunning,
			CreatedAt:    time.Now().Add(-time.Minute).Unix(),
		}
		_, err = jobStore.CreateJob(t.Context(), runningJob)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "This should be rejected",
			AssignmentId:     "dedup-running-test-uuid",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)

		var twirpErr twirp.Error
		require.ErrorAs(t, err, &twirpErr)
		require.Equal(t, twirp.Aborted, twirpErr.Code())
		require.Equal(t, jobservice.ErrJobAlreadyInProgress.Error(), twirpErr.Msg())

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0, "no job should be queued")
	})

	t.Run("rejects duplicate job when assignment already has a queued job", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t,
			withFeatureFlags(map[string]bool{
				featureflags.CopilotSWEAgentDedupJobCreation: true,
			}),
		)

		assignment := &jobs.Assignment{
			ID:          "dedup-queued-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		queuedJob := &jobs.Job{
			ID:           "already-queued-job",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			BranchName:   "copilot/queued-fix",
			Status:       jobs.JobStatusQueued,
			CreatedAt:    time.Now().Add(-time.Minute).Unix(),
		}
		_, err = jobStore.CreateJob(t.Context(), queuedJob)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "This should also be rejected",
			AssignmentId:     "dedup-queued-test-uuid",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)

		var twirpErr twirp.Error
		require.ErrorAs(t, err, &twirpErr)
		require.Equal(t, twirp.Aborted, twirpErr.Code())
		require.Equal(t, jobservice.ErrJobAlreadyInProgress.Error(), twirpErr.Msg())

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0, "no job should be queued")
	})

	t.Run("allows new job when previous jobs are all completed", func(t *testing.T) {
		server, jobStore, aq, _ := setupTestServer(t,
			withFeatureFlags(map[string]bool{
				featureflags.CopilotSWEAgentDedupJobCreation: true,
			}),
		)

		assignment := &jobs.Assignment{
			ID:          "dedup-completed-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		completedJob := &jobs.Job{
			ID:           "completed-job",
			OwnerID:      789,
			RepoID:       456,
			AssignmentID: assignment.ID,
			Model:        "sweagent-capi:gpt-4o",
			BranchName:   "copilot/done-fix",
			Status:       jobs.JobStatusCompleted,
			CreatedAt:    time.Now().Add(-time.Hour).Unix(),
		}
		_, err = jobStore.CreateJob(t.Context(), completedJob)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "New work after previous job completed",
			AssignmentId:     "dedup-completed-test-uuid",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("returns error when quota is insufficient", func(t *testing.T) {
		server, jobStore, _, _ := setupTestServer(t,
			withLimiterAPI(&githubtwirp.NoopLimiterAPI{
				MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
					return &copilotLimitersTwirp.GetQuotaRemainingResponse{
						QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
							{
								Entitlement:      1000,
								Remaining:        0,
								QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
								PercentRemaining: 0.0,
								OveragePermitted: false,
							},
						},
					}, nil
				},
			}),
			withBillingCanProceed(false),
		)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "quota-insufficient-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			AssignmentId:     "quota-insufficient-test-uuid",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr), "expected twirp error")
		require.Equal(t, twirp.FailedPrecondition, twerr.Code())
		require.Contains(t, twerr.Msg(), "insufficient premium quota to create job")
	})

	t.Run("returns error when quota check fails", func(t *testing.T) {
		server, jobStore, _, _ := setupTestServer(t,
			withLimiterAPI(&githubtwirp.NoopLimiterAPI{
				MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
					return nil, errors.New("limiter service unavailable")
				},
			}),
		)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "quota-error-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			AssignmentId:     "quota-error-test-uuid",
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)
		require.Contains(t, err.Error(), "failed to check quota")
	})

	t.Run("skips quota check when agent is quota exempt", func(t *testing.T) {
		// When the exemption flag is enabled and a non-zero agent ID is present,
		// the exemption should win and the job should succeed even though the
		// limiter returns zero remaining quota.
		exemptAgentID := int64(99999)

		billingCanProceed := false
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: billingCanProceed,
		}, nil)

		mockGhTwirp := &githubtwirp.NoopClient{
			MockIsAgentEnabled: func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
				return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
			},
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockIsBypassActor: func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
					return &sweagentdTwirp.IsBypassActorResponse{IsBypassActor: false}, nil
				},
			},
			NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
				MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{
							Id:                  123,
							AnalyticsTrackingId: "test-tracking-id",
						},
					}, nil
				},
			},
			NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
				MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
					t.Fatal("quota check should not be called for exempt agent")
					return nil, nil
				},
			},
			NoopBillingClient: mockBillingClient,
		}

		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface { return gh },
		}

		thirdPartyApp := agenticapptest.NewTestApp(exemptAgentID).WithQuotaExempt()
		appProvider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, thirdPartyApp)

		spokes := spokestest.NewClient(t)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokes, appProvider, nil)
		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		assignment := &jobs.Assignment{
			ID:          "quota-exempt-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Work from exempt integration",
			AssignmentId:     "quota-exempt-test-uuid",
			AgentId:          uint64(exemptAgentID),
		}

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	// Rules violation case: job creation blocked due to repo rules
	t.Run("rules_violation", func(t *testing.T) {
		gh := &github.NoopClient{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				return nil, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				// Return multiple branch protection rules to test concatenation
				return &[]github.GQLBranchProtectionRule{
					{ID: "12345", Pattern: "copilot/*", BlocksCreations: true},
					{ID: "67890", Pattern: "copilot/*", RequiresApprovingReviews: true},
				}, nil
			},
		}
		spokes := spokestest.NewClient(t)
		spokes.MockCheckForExistingRefs = func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
			return make([]bool, len(refs)), nil
		}

		server, jobStore, aq, _ := setupTestServer(t,
			withGitHubClient(gh),
			withSpokesClient(spokes),
		)

		// Create an existing assignment first
		assignment := &jobs.Assignment{
			ID:          "rules-violation-test-uuid",
			OwnerID:     789,
			RepoID:      456,
			OwnerNodeID: "owner-node-id",
			RepoNodeID:  "repo-node-id",
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)

		req := &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			AssignmentId:     "rules-violation-test-uuid",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		resp, err := server.CreateJobForAssignment(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)

		// Check that it's a Twirp FailedPrecondition error with the expected message
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.FailedPrecondition, twerr.Code())
		require.Contains(t, twerr.Msg(), "job cannot be created due to repository rules violation")
		// Verify multiple rules are concatenated in the error message
		require.Contains(t, twerr.Msg(), "Branch creation is blocked")
		require.Contains(t, twerr.Msg(), "Changes must be made through a pull request")
	})
}

func TestCreateJobForAssignment_CCRBranchlessAndBranchDefaults(t *testing.T) {
	const ccrAppID = int64(946600)

	ccrProvider := func(t *testing.T) *agenticapp.Provider {
		t.Helper()
		ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
		return agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)
	}

	createAssignment := func(t *testing.T, jobStore *memory.Store, ownerID, repoID int64) string {
		t.Helper()
		id := fmt.Sprintf("%d-%d-branchless-test", ownerID, repoID)
		assignment := &jobs.Assignment{
			ID:      id,
			OwnerID: ownerID,
			RepoID:  repoID,
		}
		_, err := jobStore.UpsertAssignment(t.Context(), assignment)
		require.NoError(t, err)
		return id
	}

	t.Run("CCR jobs always go branchless", func(t *testing.T) {
		server, jobStore, _, _ := setupTestServer(t,
			withAppProvider(ccrProvider(t)),
		)
		assignmentID := createAssignment(t, jobStore, 3, 2)

		resp, err := server.CreateJobForAssignment(t.Context(), &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          1,
			RepoId:           2,
			OwnerId:          3,
			AgentId:          uint64(ccrAppID),
			AssignmentId:     assignmentID,
			ProblemStatement: "Code review by Copilot",
			Features:         &jobs_pb.Features{},
		})
		require.NoError(t, err)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), 3, 2, resp.JobId)
		require.NoError(t, err)
		require.Nil(t, job.Features.Branch, "Branch should not be set for CCR job")
		require.Nil(t, job.Features.PullRequest, "PullRequest should not be set for CCR job")
		require.Empty(t, job.BranchName, "BranchName should be empty for CCR job")
	})

	t.Run("non-CCR empty features creates branch", func(t *testing.T) {
		server, jobStore, _, _ := setupTestServer(t)
		assignmentID := createAssignment(t, jobStore, 3, 2)

		resp, err := server.CreateJobForAssignment(t.Context(), &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          1,
			RepoId:           2,
			OwnerId:          3,
			AssignmentId:     assignmentID,
			ProblemStatement: "fix the bug",
			Features:         &jobs_pb.Features{},
		})
		require.NoError(t, err)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), 3, 2, resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job.Features.Branch, "Branch should be set for non-CCR job")
	})

	t.Run("nil features creates branch", func(t *testing.T) {
		server, jobStore, _, _ := setupTestServer(t)
		assignmentID := createAssignment(t, jobStore, 3, 2)

		resp, err := server.CreateJobForAssignment(t.Context(), &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          1,
			RepoId:           2,
			OwnerId:          3,
			AssignmentId:     assignmentID,
			ProblemStatement: "fix the bug",
		})
		require.NoError(t, err)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), 3, 2, resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job.Features.Branch, "Branch should be set when features are nil")
	})

	t.Run("explicit branch features creates branch", func(t *testing.T) {
		server, jobStore, _, _ := setupTestServer(t)
		assignmentID := createAssignment(t, jobStore, 3, 2)

		resp, err := server.CreateJobForAssignment(t.Context(), &jobs_pb.CreateJobForAssignmentRequest{
			ActorId:          1,
			RepoId:           2,
			OwnerId:          3,
			AssignmentId:     assignmentID,
			ProblemStatement: "fix the bug",
			Features: &jobs_pb.Features{
				Branch: &jobs_pb.BranchFeature{
					Name: "my-branch",
				},
			},
		})
		require.NoError(t, err)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), 3, 2, resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job.Features.Branch, "Branch should be set when explicitly provided")
	})
}

func TestMapJobServiceError(t *testing.T) {
	t.Run("maps CAPIError 429 to twirp ResourceExhausted", func(t *testing.T) {
		capiErr := &joberrors.CAPIError{
			Response: &http.Response{StatusCode: http.StatusTooManyRequests},
			Message:  "unexpected status code from /models endpoint",
		}
		wrapped := fmt.Errorf("failed to build job: failed to determine model for job: listing models: %w", capiErr)

		result := mapJobServiceError(wrapped)

		var twirpErr twirp.Error
		require.ErrorAs(t, result, &twirpErr)
		require.Equal(t, twirp.ResourceExhausted, twirpErr.Code())
		require.Equal(t, "rate limited by upstream service, please retry later", twirpErr.Msg())
	})

	t.Run("does not map CAPIError with non-429 status to ResourceExhausted", func(t *testing.T) {
		capiErr := &joberrors.CAPIError{
			Response: &http.Response{StatusCode: http.StatusInternalServerError},
			Message:  "unexpected status code from /models endpoint",
		}
		wrapped := fmt.Errorf("failed to build job: %w", capiErr)

		result := mapJobServiceError(wrapped)

		var twirpErr twirp.Error
		require.False(t, errors.As(result, &twirpErr), "non-429 CAPIError should not be mapped to a twirp error")
	})

	t.Run("maps ErrActorExceededMaxQueuedJobs to twirp ResourceExhausted", func(t *testing.T) {
		wrapped := fmt.Errorf("failed to queue job: %w", jobLimiter.ErrActorExceededMaxQueuedJobs)

		result := mapJobServiceError(wrapped)

		var twirpErr twirp.Error
		require.ErrorAs(t, result, &twirpErr)
		require.Equal(t, twirp.ResourceExhausted, twirpErr.Code())
		require.Equal(t, "actor has exceeded the maximum number of queued jobs", twirpErr.Msg())
	})

	t.Run("maps ErrNoModelAvailable to twirp FailedPrecondition", func(t *testing.T) {
		wrapped := fmt.Errorf("failed to build job: %w", jobservice.ErrNoModelAvailable)

		result := mapJobServiceError(wrapped)

		var twirpErr twirp.Error
		require.ErrorAs(t, result, &twirpErr)
		require.Equal(t, twirp.FailedPrecondition, twirpErr.Code())
		require.Equal(t, "no models available", twirpErr.Msg())
	})

	t.Run("does not map unrelated errors to ResourceExhausted", func(t *testing.T) {
		err := errors.New("some other error")

		result := mapJobServiceError(err)

		var twirpErr twirp.Error
		require.False(t, errors.As(result, &twirpErr), "unrelated errors should not be mapped to a twirp error")
	})

	t.Run("maps ErrJobAlreadyInProgress to twirp Aborted", func(t *testing.T) {
		wrapped := fmt.Errorf("failed to create job: %w", jobservice.ErrJobAlreadyInProgress)

		result := mapJobServiceError(wrapped)

		var twirpErr twirp.Error
		require.ErrorAs(t, result, &twirpErr)
		require.Equal(t, twirp.Aborted, twirpErr.Code())
		require.Equal(t, jobservice.ErrJobAlreadyInProgress.Error(), twirpErr.Msg())
	})
}
