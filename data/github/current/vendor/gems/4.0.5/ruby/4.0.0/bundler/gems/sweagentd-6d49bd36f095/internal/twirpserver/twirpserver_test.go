package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
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
	"github.com/github/sweagentd/internal/jobservice"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestCreateJob(t *testing.T) {
	// Shared defaults for subtests
	obsv := observability.NewNoopExporters()
	defaultGH := &github.NoopClient{}
	defaultGHF := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return defaultGH
		},
		GitHubAppLogin: "copilot",
		GitHubBotLogin: "copilot-bot",
	}
	defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), githubtwirp.NewNoopClient(), featureflags.NewNoopClient(nil))

	// Success case: job is created and queued
	t.Run("success", func(t *testing.T) {
		// Use a non-zero app ID to ensure the test catches missing WithAgentID calls
		expectedAppID := int64(31337)
		appProvider := agenticapptest.NewTestProviderWithID(t, expectedAppID)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capturedBypassActorID := int64(0)

		// Set up billing mock
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockIsBypassActor: func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
					capturedBypassActorID = int64(req.ActorId)
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

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, int64(req.ActorId), job.ActorID)
		require.Equal(t, int64(req.RepoId), job.RepoID)
		require.Equal(t, int64(req.OwnerId), job.OwnerID)
		require.Equal(t, "Fix the bug", job.ProblemStatement.Content)
		require.Equal(t, jobs.JobStatusQueued, job.Status)
		// Validate that the agent ID is set correctly
		require.Equal(t, expectedAppID, job.AgentID, "job.AgentID should be set to the app ID")
		// Validate that the agent ID was passed to IsBypassActor
		require.Equal(t, expectedAppID, capturedBypassActorID, "IsBypassActor should be called with the app ID")

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	// Test that bot actors are rejected with InvalidArgument
	t.Run("rejects bot actor with InvalidArgument", func(t *testing.T) {
		appProvider := agenticapptest.NewTestProvider(t)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentRejectBotActors: true,
		})
		mockGhTwirp := &githubtwirp.NoopClient{
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
		}

		botGHF := &github.NoopClientFactory{
			MockGetUserByID: func(ctx context.Context, id uint64) (*gg.User, error) {
				return &gg.User{
					ID:    gg.Ptr(int64(id)),
					Login: gg.Ptr("my-app[bot]"),
					Type:  gg.Ptr("Bot"),
				}, nil
			},
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), botGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, botGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)

		var twirpErr twirp.Error
		require.ErrorAs(t, err, &twirpErr)
		require.Equal(t, twirp.InvalidArgument, twirpErr.Code())
		require.Contains(t, twirpErr.Msg(), "bot actors are not allowed")

		// Verify no job was queued
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)
	})

	// Test that tenant context is correctly added from IsAgentEnabled response
	t.Run("success_adds_tenant_context", func(t *testing.T) {
		expectedTenantSlug := "test-org-slug"
		expectedTenantID := "tenant-123"
		appProvider := agenticapptest.NewTestProvider(t)

		ffClient := featureflags.NewNoopClient(map[string]bool{})

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

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
		}

		// Use a context with requestctx initialized (simulating what ServerHooks does)
		ctx := requestctx.NewContext(t.Context())

		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		// Validate that tenant context was correctly added
		require.Equal(t, expectedTenantSlug, capturedTenantSlug, "TenantSlug should be added to context")
		require.Equal(t, expectedTenantID, capturedTenantID, "TenantID should be added to context")
	})

	// Test that Event fields are properly set in the created job
	t.Run("success_with_event_fields", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			EventUrl:         "https://github.com/owner/repo/issues/123",
			EventIdentifiers: []string{"123", "456"},
			EventContent:     "User requested a fix via API",
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify Event fields are set correctly
		require.Equal(t, jobs.EventTypeAPICallReceived, job.EventType)
		require.Equal(t, "https://github.com/owner/repo/issues/123", job.EventURL)
		require.Equal(t, []string{"123", "456"}, job.EventIdentifiers)
		require.Equal(t, "User requested a fix via API", job.EventContent)
	})

	// Test that Event fields handle empty values correctly
	t.Run("success_with_empty_event_fields", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			// Event fields are intentionally empty/nil
			EventUrl:         "",
			EventIdentifiers: nil,
			EventContent:     "",
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify Event fields handle empty values correctly
		require.Equal(t, jobs.EventTypeAPICallReceived, job.EventType) // EventType should still be set to API call
		require.Equal(t, "", job.EventURL)                             // Empty string should be preserved
		require.Nil(t, job.EventIdentifiers)                           // Nil slice should be preserved
		require.Equal(t, "", job.EventContent)                         // Empty string should be preserved
	})

	// Test that older clients (without event fields) work correctly for CreateJob
	t.Run("success_with_omitted_event_fields_legacy_client", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		// Simulate older client that doesn't send event fields at all
		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			// Note: EventUrl, EventIdentifiers, EventContent fields are completely omitted
			// to simulate an older client that hasn't updated to the new proto
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify that job creation succeeds and Event fields get default values
		require.Equal(t, jobs.EventTypeAPICallReceived, job.EventType) // EventType should still be set to API call
		require.Equal(t, "", job.EventURL)                             // Should default to empty string
		require.Nil(t, job.EventIdentifiers)                           // Should default to nil
		require.Equal(t, "", job.EventContent)                         // Should default to empty string
	})

	// Test that additional_repositories are fetched and stored when feature flag is enabled
	t.Run("success_with_additional_repositories", func(t *testing.T) {
		appProvider := agenticapptest.NewTestProvider(t)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMultiRepoRead: true,
		})

		// Set up billing mock
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)

		mockGhTwirp := &githubtwirp.NoopClient{
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
			NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
			NoopBillingClient: mockBillingClient,
		}

		ghClient := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return ghClient
			},
			GitHubAppLogin: "copilot",
			GitHubBotLogin: "copilot-bot",
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with multi-repo",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
			AdditionalRepositories: []*jobs_pb.CreateJobRepositoryRef{
				{RepoId: 1001, OwnerId: 2001},
				{RepoId: 1002, OwnerId: 2002},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		// The NoopClient returns a repository with a default owner ID of 1 for all
		// GetRepositoryByID calls, so we just verify additional repos are populated.
		require.Len(t, job.AdditionalRepositories, 2)
	})

	// Test that additional_repositories are NOT fetched when feature flag is disabled
	t.Run("additional_repositories_skipped_without_feature_flag", func(t *testing.T) {
		appProvider := agenticapptest.NewTestProvider(t)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			// CopilotSWEAgentMultiRepoRead NOT set
		})

		// Set up billing mock
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)

		mockGhTwirp := &githubtwirp.NoopClient{
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
			NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
			NoopBillingClient: mockBillingClient,
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with multi-repo",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
			AdditionalRepositories: []*jobs_pb.CreateJobRepositoryRef{
				{RepoId: 1001, OwnerId: 2001},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.Empty(t, job.AdditionalRepositories, "additional repositories should not be set when feature flag is disabled")
	})

	// Test that CreateJob returns an error when fetching an additional repository fails
	t.Run("additional_repositories_fetch_error", func(t *testing.T) {
		appProvider := agenticapptest.NewTestProvider(t)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMultiRepoRead: true,
		})

		// Set up billing mock
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)

		mockGhTwirp := &githubtwirp.NoopClient{
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
			NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
			NoopBillingClient: mockBillingClient,
		}

		// NewClientFromRepo succeeds for the primary repo but returns an
		// error-returning client for additional repos so GetRepositoryByID fails.
		errorClient := &errorReturningGetRepositoryByIDClient{
			NoopClient: &github.NoopClient{},
		}
		callCount := 0
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoID, repoOwnerID int64) (github.ClientInterface, error) {
				callCount++
				if callCount > 1 {
					// Additional repo calls get the error-returning client
					return errorClient, nil
				}
				// Primary repo call gets a normal client
				return &github.NoopClient{}, nil
			},
			GitHubAppLogin: "copilot",
			GitHubBotLogin: "copilot-bot",
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with multi-repo",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
			AdditionalRepositories: []*jobs_pb.CreateJobRepositoryRef{
				{RepoId: 1001, OwnerId: 2001},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)
		require.Contains(t, err.Error(), "failed to get additional repo by ID")
	})

	// Test that CreateJob returns an error when creating a client for an additional repository fails
	t.Run("additional_repositories_client_creation_error", func(t *testing.T) {
		appProvider := agenticapptest.NewTestProvider(t)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMultiRepoRead: true,
		})

		// Set up billing mock
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)

		mockGhTwirp := &githubtwirp.NoopClient{
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
			NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
			NoopBillingClient: mockBillingClient,
		}

		// NewClientFromRepo succeeds for the primary repo but fails for additional repos
		callCount := 0
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoID, repoOwnerID int64) (github.ClientInterface, error) {
				callCount++
				if callCount > 1 {
					return nil, errors.New("installation not found")
				}
				return &github.NoopClient{}, nil
			},
			GitHubAppLogin: "copilot",
			GitHubBotLogin: "copilot-bot",
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with multi-repo",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
			AdditionalRepositories: []*jobs_pb.CreateJobRepositoryRef{
				{RepoId: 1001, OwnerId: 2001},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)
		require.Contains(t, err.Error(), "failed to create additional repo gh client")
	})

	// Test that CreateJob returns an error when too many additional repositories are provided
	t.Run("additional_repositories_exceeds_maximum", func(t *testing.T) {
		appProvider := agenticapptest.NewTestProvider(t)
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMultiRepoRead: true,
		})

		// Set up billing mock
		mockBillingClient := billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Maybe().Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: true,
		}, nil)

		mockGhTwirp := &githubtwirp.NoopClient{
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
			NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
			NoopBillingClient: mockBillingClient,
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		// Create maxAdditionalRepositories + 1 additional repos to exceed the limit
		additionalRepos := make([]*jobs_pb.CreateJobRepositoryRef, maxAdditionalRepositories+1)
		for i := range additionalRepos {
			additionalRepos[i] = &jobs_pb.CreateJobRepositoryRef{
				RepoId:  uint64(1001 + i),
				OwnerId: uint64(2001 + i),
			}
		}

		req := &jobs_pb.CreateJobRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			ProblemStatement:       "Fix the bug with multi-repo",
			Features:               &jobs_pb.Features{PullRequest: &jobs_pb.PullRequestFeature{}},
			AdditionalRepositories: additionalRepos,
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr), "expected twirp error")
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), fmt.Sprintf("more than maximum of %d additional repositories provided", maxAdditionalRepositories))
	})

	// CCA not enabled case
	t.Run("cca_not_enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: false,
				},
			},
		}

		obsv := observability.NewNoopExporters()

		ghf := &github.NoopClientFactory{}
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)

		// Check that it's a Twirp Aborted error
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.Aborted, twerr.Code())
		require.Contains(t, twerr.Msg(), "user or repo does not have CCA enabled")
	})

	// Validation cases (table-driven)
	t.Run("validates_fields", func(t *testing.T) {
		tests := []struct {
			name              string
			req               *jobs_pb.CreateJobRequest
			expectedErrorCode twirp.ErrorCode
			expectedErrorMsg  string
		}{
			{
				name: "missing actor_id",
				req: &jobs_pb.CreateJobRequest{
					ActorId:          0, // Missing
					RepoId:           456,
					OwnerId:          789,
					ProblemStatement: "Fix the bug",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "actor_id",
			},
			{
				name: "missing owner_id",
				req: &jobs_pb.CreateJobRequest{
					ActorId:          123,
					RepoId:           456,
					OwnerId:          0, // Missing
					ProblemStatement: "Fix the bug",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "owner_id",
			},
			{
				name: "missing repo_id",
				req: &jobs_pb.CreateJobRequest{
					ActorId:          123,
					RepoId:           0, // Missing
					OwnerId:          789,
					ProblemStatement: "Fix the bug",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "repo_id",
			},
			{
				name: "empty problem_statement",
				req: &jobs_pb.CreateJobRequest{
					ActorId:          123,
					RepoId:           456,
					OwnerId:          789,
					ProblemStatement: "", // Empty
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "problem_statement",
			},
			{
				name: "whitespace only problem_statement",
				req: &jobs_pb.CreateJobRequest{
					ActorId:          123,
					RepoId:           456,
					OwnerId:          789,
					ProblemStatement: "   \t\n  ", // Whitespace only
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "problem_statement",
			},
		}

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				server := &Server{obsv: obsv}
				resp, err := server.CreateJob(context.Background(), tt.req)
				require.Nil(t, resp)
				require.Error(t, err)
				// Check that it's the expected Twirp error
				var twerr twirp.Error
				require.True(t, errors.As(err, &twerr), "Expected twirp.Error, got %T", err)
				require.Equal(t, tt.expectedErrorCode, twerr.Code())
				require.Contains(t, twerr.Msg(), tt.expectedErrorMsg)
			})
		}
	})

	// Rules violation case: job creation blocked due to repo rules
	t.Run("rules_violation", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		gh := &github.NoopClient{
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				// Return no repository rules to keep test simple
				return nil, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				// Return branch protection rule that blocks creations to trigger rules violation
				return &[]github.GQLBranchProtectionRule{{ID: "12345", Pattern: "copilot/*", BlocksCreations: true}}, nil
			},
		}
		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return gh
			},
		}
		spokes := spokestest.NewClient(t)
		spokes.MockCheckForExistingRefs = func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
			return make([]bool, len(refs)), nil
		}
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		resp, err := server.CreateJob(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)

		// Check that it's a Twirp FailedPrecondition error with the expected message
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.FailedPrecondition, twerr.Code())
		require.Contains(t, twerr.Msg(), "job cannot be created due to repository rules violation")

		// Verify that the jobExecutor.QueueJob was NOT called since job creation was blocked
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)
	})
}

func TestGetJobBySessionID_Found(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: true,
			},
		},
	}

	// Create server
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-1234",
		SessionID: "test-session-id",
		OwnerID:   789,
		RepoID:    456,
		ActorID:   1,
		ComputeID: "test-compute-id",
		Status:    jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

	req := &jobs_pb.GetJobBySessionIDRequest{
		RepoId:    456,
		OwnerId:   789,
		SessionId: "test-session-id",
	}

	// Execute
	resp, err := server.GetJobBySessionID(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)

	job := resp.Job
	require.NotEmpty(t, job.Id)
	require.Equal(t, job.SessionId, testJob.SessionID)
	require.Equal(t, job.ActorId, testJob.ActorID)
	require.Equal(t, job.RepoId, testJob.RepoID)
	require.Equal(t, job.OwnerId, testJob.OwnerID)
}

func TestGetJobBySessionID_NotFound(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: true,
			},
		},
	}

	// Create server
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

	req := &jobs_pb.GetJobBySessionIDRequest{
		RepoId:    456,
		OwnerId:   789,
		SessionId: "non-existent-session-id",
	}

	// Execute
	resp, err := server.GetJobBySessionID(ctx, req)
	require.Error(t, err)
	require.Nil(t, resp)

	// Check that it's a Twirp NotFound error
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.NotFound, twerr.Code())
	require.Contains(t, twerr.Msg(), "no job found for session ID")
}

// MockGitHubClientWithRules simulates a GitHub client that returns rule violations
type MockGitHubClientWithRules struct {
	github.NoopClient
}

func TestCreateJob_CustomAgents(t *testing.T) {
	t.Run("creates job with default Copilot custom agent when on disallow list", func(t *testing.T) {
		ctx := context.Background()
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		// Create server with custom agent feature flag disabled
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{featureflags.CopilotSWEAgentCustomAgentsDisallow: true})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			CustomAgent:      "custom-agent", // This should be ignored when FF is disabled
		}

		// Ensure no jobs in Aqueduct queue before creation
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with default Copilot custom agent (even when feature flag disabled)
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, "", job.CustomAgent.Name) // Returns Copilot agent when FF disabled which has empty name
		assert.Equal(t, "test-owner", job.CustomAgent.RepoOwner)
		assert.Equal(t, "test-repo", job.CustomAgent.RepoName)

		// Ensure one job in Aqueduct queue after creation
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with named custom agent when specified", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
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
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
					return &repositoriesTwirp.FindRepositoriesByNameResponse{
						Repositories: []*repositoriesTwirp.RepositoryListItem{
							{
								Id:         456,
								OwnerId:    789,
								Name:       "test-repo",
								OwnerLogin: "test-owner",
							},
						},
					}, nil
				},
			},
		}

		// Create server with custom agent feature flag enabled
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		// Mock spokes to return a test custom agent configuration
		agents := map[string]string{
			"test-agent": `---
name: Test Agent
description: A test custom agent
tools: test-tool,another-tool
---

This is a test agent for testing purposes.`,
		}
		spokes := customagenttest.MakeSpokes(t, agents)

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		customAgentSvc := customagent.NewService(obsv, spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			CustomAgent:      "test-agent",
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with the named custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, "test-agent", job.CustomAgent.Name)
		assert.Equal(t, "Test Agent", job.CustomAgent.DisplayName)
		assert.Equal(t, "A test custom agent", job.CustomAgent.Description)
		assert.Contains(t, job.CustomAgent.Tools, "test-tool")
		assert.Contains(t, job.CustomAgent.Tools, "another-tool")

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with custom agent including MCP servers when attributes specified", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
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
		}

		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentAsAPI: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			CustomAgentAttributes: &jobs_pb.CustomAgentAttributes{
				DisplayName: "MCP Test Agent",
				Description: "A custom agent with MCP servers",
				Prompt:      "You are a custom test agent with MCP servers",
				Tools:       []string{"custom-tool"},
				McpServers: map[string]*jobs_pb.MCPServer{
					"github-mcp-server": {
						Tools:   []string{"*"},
						Type:    "http",
						Url:     "https://api.githubcopilot.com/mcp",
						Headers: map[string]string{"X-MCP-Toolsets": "context,issues"},
					},
				},
			},
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with the custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, agentconfig.ScopeJob, job.CustomAgent.Scope)
		assert.Equal(t, "MCP Test Agent", job.CustomAgent.DisplayName)
		assert.Equal(t, "A custom agent with MCP servers", job.CustomAgent.Description)

		// Verify MCP servers are stored
		require.Len(t, job.CustomAgent.MCPServers, 1)
		assert.Equal(t, "github-mcp-server", job.CustomAgent.MCPServers[0].Name)
		assert.Equal(t, "http", job.CustomAgent.MCPServers[0].Type)
		assert.Equal(t, "https://api.githubcopilot.com/mcp", job.CustomAgent.MCPServers[0].URL)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with custom agent including local MCP server when attributes specified", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
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
		}

		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentAsAPI: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with local MCP server",
			CustomAgentAttributes: &jobs_pb.CustomAgentAttributes{
				DisplayName: "Local MCP Test Agent",
				Description: "A custom agent with local MCP server",
				Prompt:      "You are a custom test agent with local MCP server",
				Tools:       []string{"custom-tool"},
				McpServers: map[string]*jobs_pb.MCPServer{
					"local-mcp-server": {
						Tools:   []string{"local_tool"},
						Type:    "local",
						Command: "/usr/bin/mcp-server",
						Args:    []string{"--port", "8080"},
						Env:     map[string]string{"MCP_DEBUG": "true"},
					},
				},
			},
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with the custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, agentconfig.ScopeJob, job.CustomAgent.Scope)
		assert.Equal(t, "Local MCP Test Agent", job.CustomAgent.DisplayName)
		assert.Equal(t, "A custom agent with local MCP server", job.CustomAgent.Description)

		// Verify local MCP server is stored
		require.Len(t, job.CustomAgent.MCPServers, 1)
		assert.Equal(t, "local-mcp-server", job.CustomAgent.MCPServers[0].Name)
		assert.Equal(t, "local", job.CustomAgent.MCPServers[0].Type)
		assert.Equal(t, "/usr/bin/mcp-server", job.CustomAgent.MCPServers[0].Command)
		assert.Equal(t, []string{"--port", "8080"}, job.CustomAgent.MCPServers[0].Args)
		assert.Equal(t, map[string]string{"MCP_DEBUG": "true"}, job.CustomAgent.MCPServers[0].Env)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with custom agent skipping MCP servers with unknown type", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
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
		}

		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentAsAPI: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with unknown MCP server type",
			CustomAgentAttributes: &jobs_pb.CustomAgentAttributes{
				DisplayName: "Unknown Type MCP Test Agent",
				Description: "A custom agent with unknown MCP server type",
				Tools:       []string{"custom-tool"},
				McpServers: map[string]*jobs_pb.MCPServer{
					"valid-server": {
						Tools: []string{"*"},
						Type:  "http",
						Url:   "https://api.example.com/mcp",
					},
					"unknown-type-server": {
						Tools:   []string{"tool1"},
						Type:    "websocket", // Unknown type - should be skipped
						Url:     "ws://example.com/mcp",
						Command: "/usr/bin/mcp",
					},
				},
			},
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with the custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Only the valid server should be stored; the unknown type server should be skipped
		require.Len(t, job.CustomAgent.MCPServers, 1)
		assert.Equal(t, "valid-server", job.CustomAgent.MCPServers[0].Name)
		assert.Equal(t, "http", job.CustomAgent.MCPServers[0].Type)
		assert.Equal(t, "https://api.example.com/mcp", job.CustomAgent.MCPServers[0].URL)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with custom agent skipping MCP servers with missing required fields", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
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
		}

		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentAsAPI: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug with invalid MCP servers",
			CustomAgentAttributes: &jobs_pb.CustomAgentAttributes{
				DisplayName: "Invalid MCP Test Agent",
				Description: "A custom agent with invalid MCP servers",
				Tools:       []string{"custom-tool", "referenced-server/some-tool"},
				McpServers: map[string]*jobs_pb.MCPServer{
					"valid-server": {
						Tools: []string{"*"},
						Type:  "http",
						Url:   "https://api.example.com/mcp",
					},
					"referenced-server": {
						Type: "http",
						Url:  "https://referenced.example.com/mcp",
						// Missing tools but referenced in Tools - should default to ["*"]
					},
					"unreferenced-server": {
						Type: "http",
						Url:  "https://unreferenced.example.com/mcp",
						// Missing tools and NOT referenced in Tools - should be skipped
					},
					"missing-command": {
						Tools: []string{"*"},
						Type:  "local",
						// Missing command - should be skipped
					},
					"missing-url": {
						Tools: []string{"*"},
						Type:  "http",
						// Missing url - should be skipped
					},
				},
			},
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with the custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// valid-server and referenced-server should be stored
		// unreferenced-server, missing-command, and missing-url should be skipped
		require.Len(t, job.CustomAgent.MCPServers, 2)

		// Find servers by name since map iteration order is not guaranteed
		serversByName := make(map[string]jobsCustomAgent.MCPServer)
		for _, s := range job.CustomAgent.MCPServers {
			serversByName[s.Name] = s
		}

		assert.Contains(t, serversByName, "valid-server")
		assert.Equal(t, "http", serversByName["valid-server"].Type)
		assert.Equal(t, "https://api.example.com/mcp", serversByName["valid-server"].URL)

		assert.Contains(t, serversByName, "referenced-server")
		assert.Equal(t, "http", serversByName["referenced-server"].Type)
		assert.Equal(t, "https://referenced.example.com/mcp", serversByName["referenced-server"].URL)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with custom agent when attributes specified and verifies FromDB reconstruction", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
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
		}

		// Create server with both custom agent feature flags enabled
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentAsAPI: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			CustomAgentAttributes: &jobs_pb.CustomAgentAttributes{
				DisplayName: "Custom Test Agent",
				Description: "A custom agent for testing",
				Prompt:      "You are a custom test agent",
				Tools:       []string{"custom-tool", "test-tool"},
			},
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with the custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify the stored DB record has the job scope
		assert.Equal(t, agentconfig.ScopeJob, job.CustomAgent.Scope)
		assert.Equal(t, "Custom Test Agent", job.CustomAgent.DisplayName)
		assert.Equal(t, "A custom agent for testing", job.CustomAgent.Description)
		assert.Equal(t, []string{"custom-tool", "test-tool"}, job.CustomAgent.Tools)

		// Verify that Service.FromDB can reconstruct the ad-hoc agent from the stored DB record
		reconstructedAgent, err := caSvc.FromDB(ctx, job.CustomAgent)
		require.NoError(t, err)
		require.NotNil(t, reconstructedAgent)

		// Verify the reconstructed agent has the correct properties
		assert.Equal(t, job.CustomAgent.Name, reconstructedAgent.Name())
		assert.Equal(t, "Custom Test Agent", reconstructedAgent.DisplayName())
		assert.Equal(t, "A custom agent for testing", reconstructedAgent.Description())
		assert.Equal(t, []string{"custom-tool", "test-tool"}, reconstructedAgent.Tools())
		assert.Equal(t, "You are a custom test agent", reconstructedAgent.Prompt())

		// Verify it's a PrivilegedAgent type (job-scoped agents are PrivilegedAgent)
		_, isPrivileged := reconstructedAgent.(*customagent.PrivilegedAgent)
		assert.True(t, isPrivileged, "expected PrivilegedAgent type, got %T", reconstructedAgent)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with default Copilot custom agent when no custom agent specified", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
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
		}

		// Create server with custom agent feature flag enabled
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			// No custom agent or custom_agent_attributes specified
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		// Execute
		resp, err := server.CreateJob(ctx, req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify that the job was created with the default Copilot custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, "", job.CustomAgent.Name)
		assert.Equal(t, "", job.CustomAgent.DisplayName)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("returns error when custom agent loading fails", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
					return nil, errors.New("unexpected error accessing repositories")
				},
			},
		}

		// Create server with custom agent feature flag enabled
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		// Create a GitHub client that will fail when accessing repository
		gh := &github.NoopClient{
			MockGetRepository: func(ctx context.Context, owner, repo string) (*gg.Repository, error) {
				return nil, errors.New("repository access failed")
			},
		}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		// Create a custom agent service that will fail when accessing spokes
		// Use an empty map so no agents are available
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		// Don't set up any QueueJob expectations since the job creation should fail before reaching that point

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			CustomAgent:      "failing-agent",
		}

		// Execute
		_, err := server.CreateJob(ctx, req)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to get custom agent")
	})

	t.Run("returns NotFound error when custom agent not found", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				MockFindRepositoriesByName: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
					return &repositoriesTwirp.FindRepositoriesByNameResponse{
						Repositories: []*repositoriesTwirp.RepositoryListItem{
							{
								Id:         456,
								Name:       "test-repo",
								OwnerId:    789,
								OwnerLogin: "test-owner",
							},
						},
					}, nil
				},
			},
		}

		// Create server with custom agent feature flag enabled
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		// Create a GitHub client that will fail when accessing repository
		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		// Create a custom agent service that will fail when accessing spokes
		// Use an empty map so no agents are available
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		// Don't set up any QueueJob expectations since the job creation should fail before reaching that point

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			CustomAgent:      "does-not-exist",
		}

		// Execute
		_, err := server.CreateJob(ctx, req)
		require.Error(t, err)
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.NotFound, twerr.Code())
		assert.Contains(t, err.Error(), "specified custom agent not found")
	})

	t.Run("custom agent with version parses correctly", func(t *testing.T) {
		ctx := context.Background()
		testSHA := "abc123def456abc123def456abc123def456abc1"

		// Custom agent configuration
		agentConfig := `---
name: My Test Agent
description: A test custom agent
---

You are a helpful assistant`

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockCreatePullRequest: func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
					return &sweagentdTwirp.CreatePullRequestResponse{
						PullRequest: &sweagentdTwirp.PullRequest{
							Id:           123,
							GithubNumber: 1234,
						},
					}, nil
				},
				MockAuthorizeCustomAgentRepoForUser: func(ctx context.Context, req *sweagentdTwirp.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse, error) {
					return &sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse{
						CanAccess: true,
					}, nil
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
			NoopRepositoriesAPI: &githubtwirp.NoopRepositoriesAPI{
				MockFindRepositories: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
					return &repositoriesTwirp.FindRepositoriesResponse{
						Repositories: []*repositoriesTwirp.RepositoryListItem{
							{
								Id:         456,
								OwnerId:    789,
								OwnerLogin: "test-owner",
								Name:       "test-repo",
							},
						},
					}, nil
				},
			},
		}

		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)

		t.Run("when version is specified", func(t *testing.T) {
			// Create spokes client with custom agent config at a specific version (SHA)
			spokes := spokestest.NewClient(t,
				spokestest.WithCommitSHAAndBlob(".github/agents/my-agent.md", testSHA, []byte(agentConfig)),
			)

			customAgentSvc := customagent.NewService(obsv, spokes, mockGhTwirp, ffClient)
			jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
			server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

			req := &jobs_pb.CreateJobRequest{
				ActorId:          123,
				RepoId:           456,
				OwnerId:          789,
				ProblemStatement: "Fix the bug",
				CustomAgent:      fmt.Sprintf("my-agent@%s", testSHA),
			}

			require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

			// Execute
			resp, err := server.CreateJob(ctx, req)
			require.NoError(t, err)
			require.NotNil(t, resp)

			// Verify that the job was created with the custom agent and correct version
			job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
			require.NoError(t, err)
			require.NotNil(t, job)
			assert.Equal(t, "my-agent", job.CustomAgent.Name, "Agent name should be parsed without version")
			assert.Equal(t, testSHA, job.CustomAgent.Version, "Version (SHA) should be extracted and stored")
			assert.Equal(t, "My Test Agent", job.CustomAgent.DisplayName)
			assert.Equal(t, "A test custom agent", job.CustomAgent.Description)

			require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
		})

		t.Run("when no version is specified", func(t *testing.T) {
			defaultSHA := "sha-0123456789101112131415161718192021222324252627" // Default commit SHA from spokestest

			// Create spokes client with custom agent config at default location
			spokes := spokestest.NewClient(t,
				spokestest.WithRepoBlob(uint64(456), ".github/agents/my-agent.md", []byte(agentConfig)),
			)

			customAgentSvc := customagent.NewService(obsv, spokes, mockGhTwirp, ffClient)

			req := &jobs_pb.CreateJobRequest{
				ActorId:          123,
				RepoId:           456,
				OwnerId:          789,
				ProblemStatement: "Fix the bug",
				CustomAgent:      "my-agent",
			}

			// Clear queue from previous test and create new server with updated aqueduct
			aq = aqueduct.NewMemoryClient(obsv)
			jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
			server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

			require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

			// Execute
			resp, err := server.CreateJob(ctx, req)
			require.NoError(t, err)
			require.NotNil(t, resp)

			// Verify that the job was created with the custom agent and default SHA as version
			job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
			require.NoError(t, err)
			require.NotNil(t, job)
			assert.Equal(t, "my-agent", job.CustomAgent.Name, "Agent name should be the full custom agent string when no version is specified")
			assert.Equal(t, defaultSHA, job.CustomAgent.Version, "Version should be set to the commit SHA of the config file from ReadBlob")
			assert.Equal(t, "My Test Agent", job.CustomAgent.DisplayName)
			assert.Equal(t, "A test custom agent", job.CustomAgent.Description)

			require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
		})
	})
}

func TestCreateJob_Features(t *testing.T) {
	// Shared defaults for subtests
	obsv := observability.NewNoopExporters()
	defaultGH := &github.NoopClient{}
	defaultGHF := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return defaultGH
		},
	}

	t.Run("uses branch base_ref from features when provided", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			Features: &jobs_pb.Features{
				Branch: &jobs_pb.BranchFeature{
					BaseRef: "feature-branch",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "feature-branch", job.BaseCommit) // Should use the provided base branch

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("uses pull_request base_ref from features when provided", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{
					BaseRef: "develop",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "develop", job.BaseCommit) // Should use the PR base ref

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("falls back to default branch when no features provided", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "main", job.BaseCommit) // Should use the repository's default branch

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("uses task action when no pull request feature", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Do the thing",
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.Equal(t, jobs.AgentActionTask, job.Action)
	})

	t.Run("uses fix action when pull request feature present", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.Equal(t, jobs.AgentActionFix, job.Action)
	})

	t.Run("links existing PR when HeadRef provided", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		mockGHF := &github.NoopClientFactory{
			MockPullRequestList: []*gg.PullRequest{
				{
					ID:     gg.Ptr(int64(9999)),
					Number: gg.Ptr(42),
					Title:  gg.Ptr("My existing PR"),
					Base:   &gg.PullRequestBranch{Ref: gg.Ptr("main")},
				},
			},
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), mockGHF, mockGhTwirp, aq, limiter, exp, caSvc, "GitHub", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, mockGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)
		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix CI failures",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{
					HeadRef: "feature/my-branch",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.Equal(t, int64(9999), job.PullRequestID, "job should be linked to existing PR ID")
		require.Equal(t, 42, job.PullRequestNumber, "job should have existing PR number")
	})

	t.Run("falls back to creating a new PR when HeadRef provided but no matching PR exists", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "GitHub", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix CI failures",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{
					HeadRef: "feature/my-branch",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.Equal(t, int64(123), job.PullRequestID, "job should fall back to creating a new PR")
		require.Equal(t, 789, job.PullRequestNumber, "job should fall back to creating a new PR")
	})

	t.Run("does not link PR when HeadRef equals default branch", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		mockGHF := &github.NoopClientFactory{
			MockPullRequestList: []*gg.PullRequest{
				{
					ID:     gg.Ptr(int64(9999)),
					Number: gg.Ptr(42),
					Title:  gg.Ptr("PR on main"),
				},
			},
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), mockGHF, mockGhTwirp, aq, limiter, exp, caSvc, "GitHub", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, mockGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix something on main",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{
					HeadRef: "main",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), "matches the repository default branch")
	})

	t.Run("normalizes refs/heads/ prefix before default branch check", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		mockGHF := &github.NoopClientFactory{
			MockPullRequestList: []*gg.PullRequest{
				{
					ID:     gg.Ptr(int64(9999)),
					Number: gg.Ptr(42),
					Title:  gg.Ptr("PR on main"),
				},
			},
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), mockGHF, mockGhTwirp, aq, limiter, exp, caSvc, "GitHub", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, mockGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix something on main via qualified ref",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{
					HeadRef: "refs/heads/main",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.InvalidArgument, twerr.Code())
		require.Contains(t, twerr.Msg(), "matches the repository default branch")
	})
	t.Run("allows HeadRef equal to default branch for branchless agents", func(t *testing.T) {
		const ccrAppID = int64(946600)
		ffClient := featureflags.NewNoopClient(nil)
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		mockGHF := &github.NoopClientFactory{
			MockPullRequestList: []*gg.PullRequest{
				{
					ID:     gg.Ptr(int64(9999)),
					Number: gg.Ptr(42),
					Title:  gg.Ptr("PR on main"),
				},
			},
		}

		ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
		appProvider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), mockGHF, mockGhTwirp, aq, limiter, exp, caSvc, "GitHub", "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, mockGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			AgentId:          ccrAppID,
			ProblemStatement: "Review the PR opened against main",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{
					HeadRef: "main",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)
	})
	t.Run("allows HeadRef equal to default branch when skip flag is enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSkipDefaultBranchHeadRefCheck: true,
		})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		}

		mockGHF := &github.NoopClientFactory{
			MockPullRequestList: []*gg.PullRequest{
				{
					ID:     gg.Ptr(int64(9999)),
					Number: gg.Ptr(42),
					Title:  gg.Ptr("PR on main"),
				},
			},
		}

		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), mockGHF, mockGhTwirp, aq, limiter, exp, caSvc, "GitHub", "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, mockGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Skip default branch check via feature flag",
			Features: &jobs_pb.Features{
				PullRequest: &jobs_pb.PullRequestFeature{
					HeadRef: "main",
				},
			},
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)
	})
}

func TestGetBaseCommitFromRequest(t *testing.T) {
	tests := []struct {
		name           string
		baseBranchName string
		defaultBranch  string
		expected       string
	}{
		{
			name:           "uses base_branch_name when provided",
			baseBranchName: "feature-branch",
			defaultBranch:  "main",
			expected:       "feature-branch",
		},
		{
			name:           "falls back to default when empty",
			baseBranchName: "",
			defaultBranch:  "main",
			expected:       "main",
		},
		{
			name:           "falls back to default when whitespace only",
			baseBranchName: "   \t\n  ",
			defaultBranch:  "develop",
			expected:       "develop",
		},
		{
			name:           "handles different default branch",
			baseBranchName: "my-feature",
			defaultBranch:  "develop",
			expected:       "my-feature",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := getBaseCommitFromRequest(tt.baseBranchName, tt.defaultBranch)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestListJobsForPullRequest(t *testing.T) {
	const (
		originalPRID int64 = 12345
		stackedPRID  int64 = 67890
	)

	tests := []struct {
		name                string
		featureFlags        map[string]bool
		assignment          *jobs.Assignment
		job                 *jobs.Job
		lookupPullRequestID int64
		expectFound         bool
		expectedJobID       string
	}{
		{
			name:         "finds assignment by PR ID",
			featureFlags: map[string]bool{},
			assignment: &jobs.Assignment{
				ID:            "test-assignment-id",
				OwnerID:       789,
				RepoID:        456,
				PullRequestID: originalPRID,
			},
			job: &jobs.Job{
				ID:           "job-1234",
				AssignmentID: "test-assignment-id",
				OwnerID:      789,
				RepoID:       456,
			},
			lookupPullRequestID: originalPRID,
			expectFound:         true,
			expectedJobID:       "job-1234",
		},
		{
			name:         "does not find assignment when PR ID does not match",
			featureFlags: map[string]bool{},
			assignment: &jobs.Assignment{
				ID:            "test-assignment-id",
				OwnerID:       789,
				RepoID:        456,
				PullRequestID: stackedPRID,
			},
			job: &jobs.Job{
				ID:           "job-5678",
				AssignmentID: "test-assignment-id",
				OwnerID:      789,
				RepoID:       456,
			},
			lookupPullRequestID: originalPRID,
			expectFound:         false,
		},
		{
			name:         "finds assignment by stacked PR ID",
			featureFlags: map[string]bool{},
			assignment: &jobs.Assignment{
				ID:            "test-assignment-stacked",
				OwnerID:       789,
				RepoID:        456,
				PullRequestID: stackedPRID,
			},
			job: &jobs.Job{
				ID:           "job-stacked",
				AssignmentID: "test-assignment-stacked",
				OwnerID:      789,
				RepoID:       456,
			},
			lookupPullRequestID: stackedPRID,
			expectFound:         true,
			expectedJobID:       "job-stacked",
		},
		{
			name:                "returns not found when no assignment exists",
			featureFlags:        map[string]bool{},
			assignment:          nil,
			job:                 nil,
			lookupPullRequestID: 99999,
			expectFound:         false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := t.Context()
			jobStore := memory.NewStore()
			ffClient := featureflags.NewNoopClient(tt.featureFlags)

			if tt.assignment != nil {
				_, err := jobStore.CreateAssignment(ctx, tt.assignment)
				require.NoError(t, err)
			}
			if tt.job != nil {
				_, err := jobStore.CreateJob(ctx, tt.job)
				require.NoError(t, err)
			}

			server := NewServer(observability.NewNoopExporters(), nil, nil, jobStore, nil, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

			resp, err := server.ListJobsForPullRequest(ctx, &jobs_pb.ListJobsForPullRequestRequest{
				OwnerId:       789,
				RepoId:        456,
				PullRequestId: tt.lookupPullRequestID,
			})

			if tt.expectFound {
				require.NoError(t, err)
				require.Len(t, resp.Jobs, 1)
				assert.Equal(t, tt.expectedJobID, resp.Jobs[0].Id)
			} else {
				require.Nil(t, resp)
				var twerr twirp.Error
				require.True(t, errors.As(err, &twerr))
				assert.Equal(t, twirp.NotFound, twerr.Code())
			}
		})
	}

	t.Run("returns multiple jobs for the same assignment", func(t *testing.T) {
		ctx := t.Context()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		assignment := &jobs.Assignment{
			ID:            "test-assignment-multi",
			OwnerID:       789,
			RepoID:        456,
			PullRequestID: originalPRID,
		}
		_, err := jobStore.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		job1 := &jobs.Job{
			ID:           "job-first",
			AssignmentID: assignment.ID,
			OwnerID:      789,
			RepoID:       456,
		}
		job2 := &jobs.Job{
			ID:           "job-second",
			AssignmentID: assignment.ID,
			OwnerID:      789,
			RepoID:       456,
		}
		_, err = jobStore.CreateJob(ctx, job1)
		require.NoError(t, err)
		_, err = jobStore.CreateJob(ctx, job2)
		require.NoError(t, err)

		server := NewServer(observability.NewNoopExporters(), nil, nil, jobStore, nil, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		resp, err := server.ListJobsForPullRequest(ctx, &jobs_pb.ListJobsForPullRequestRequest{
			OwnerId:       789,
			RepoId:        456,
			PullRequestId: originalPRID,
		})
		require.NoError(t, err)
		require.Len(t, resp.Jobs, 2)

		returnedIDs := []string{resp.Jobs[0].Id, resp.Jobs[1].Id}
		assert.Contains(t, returnedIDs, "job-first")
		assert.Contains(t, returnedIDs, "job-second")
	})
}

func TestListJobsForPullRequestByNumber(t *testing.T) {
	const prNumber = 4242

	t.Run("returns jobs across multiple assignments with automation fields", func(t *testing.T) {
		ctx := t.Context()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		automationJob := &jobs.Job{
			ID:                "job-automation",
			AssignmentID:      "assignment-old",
			OwnerID:           789,
			RepoID:            456,
			PullRequestNumber: prNumber,
			IsTriggered:       true,
			AutomationID:      "automation-123",
		}
		manualJob := &jobs.Job{
			ID:                "job-manual",
			AssignmentID:      "assignment-new",
			OwnerID:           789,
			RepoID:            456,
			PullRequestNumber: prNumber,
		}
		_, err := jobStore.CreateJob(ctx, automationJob)
		require.NoError(t, err)
		_, err = jobStore.CreateJob(ctx, manualJob)
		require.NoError(t, err)

		server := NewServer(observability.NewNoopExporters(), nil, nil, jobStore, nil, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		resp, err := server.ListJobsForPullRequestByNumber(ctx, &jobs_pb.ListJobsForPullRequestByNumberRequest{
			OwnerId:           789,
			RepoId:            456,
			PullRequestNumber: prNumber,
		})
		require.NoError(t, err)
		require.Len(t, resp.Jobs, 2)

		byID := map[string]*jobs_pb.Job{}
		for _, j := range resp.Jobs {
			byID[j.Id] = j
		}
		require.Contains(t, byID, "job-automation")
		require.Contains(t, byID, "job-manual")
		assert.True(t, byID["job-automation"].IsTriggered)
		assert.Equal(t, "automation-123", byID["job-automation"].AutomationId)
		assert.False(t, byID["job-manual"].IsTriggered)
		assert.Empty(t, byID["job-manual"].AutomationId)
	})

	t.Run("returns empty list when no jobs match", func(t *testing.T) {
		ctx := t.Context()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		server := NewServer(observability.NewNoopExporters(), nil, nil, jobStore, nil, ffClient, agenticapptest.NewTestProvider(t), nil, nil, nil, nil)

		resp, err := server.ListJobsForPullRequestByNumber(ctx, &jobs_pb.ListJobsForPullRequestByNumberRequest{
			OwnerId:           789,
			RepoId:            456,
			PullRequestNumber: prNumber,
		})
		require.NoError(t, err)
		require.Empty(t, resp.Jobs)
	})
}

func TestReqFeaturesToJobFeatures_CopilotSetupSteps(t *testing.T) {
	t.Run("nil features returns empty", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(nil)
		require.Nil(t, result.CopilotSetupSteps)
	})

	t.Run("nil CopilotSetupSteps returns nil", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(&jobs_pb.Features{})
		require.Nil(t, result.CopilotSetupSteps)
	})

	t.Run("empty CopilotSetupSteps maps with defaults", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(&jobs_pb.Features{
			CopilotSetupSteps: &jobs_pb.CopilotSetupStepsFeature{},
		})
		require.NotNil(t, result.CopilotSetupSteps)
		require.False(t, result.CopilotSetupSteps.Skip)
	})

	t.Run("skip is mapped", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(&jobs_pb.Features{
			CopilotSetupSteps: &jobs_pb.CopilotSetupStepsFeature{
				Skip: true,
			},
		})
		require.NotNil(t, result.CopilotSetupSteps)
		require.True(t, result.CopilotSetupSteps.Skip)
	})

	t.Run("exclude is mapped", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(&jobs_pb.Features{
			CopilotSetupSteps: &jobs_pb.CopilotSetupStepsFeature{
				Exclude: []string{"steps", "runs-on"},
			},
		})
		require.NotNil(t, result.CopilotSetupSteps)
		require.False(t, result.CopilotSetupSteps.Skip)
		require.Equal(t, []string{"steps", "runs-on"}, result.CopilotSetupSteps.Exclude)
	})

	t.Run("skip and exclude are both mapped", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(&jobs_pb.Features{
			CopilotSetupSteps: &jobs_pb.CopilotSetupStepsFeature{
				Skip:    true,
				Exclude: []string{"permissions"},
			},
		})
		require.NotNil(t, result.CopilotSetupSteps)
		require.True(t, result.CopilotSetupSteps.Skip)
		require.Equal(t, []string{"permissions"}, result.CopilotSetupSteps.Exclude)
	})

	t.Run("only is mapped", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(&jobs_pb.Features{
			CopilotSetupSteps: &jobs_pb.CopilotSetupStepsFeature{
				Only: []string{"runs-on", "container"},
			},
		})
		require.NotNil(t, result.CopilotSetupSteps)
		require.False(t, result.CopilotSetupSteps.Skip)
		require.Equal(t, []string{"runs-on", "container"}, result.CopilotSetupSteps.Only)
	})

	t.Run("skip and only are both mapped", func(t *testing.T) {
		result := reqFeaturesToJobFeatures(&jobs_pb.Features{
			CopilotSetupSteps: &jobs_pb.CopilotSetupStepsFeature{
				Skip: true,
				Only: []string{"runs-on"},
			},
		})
		require.NotNil(t, result.CopilotSetupSteps)
		require.True(t, result.CopilotSetupSteps.Skip)
		require.Equal(t, []string{"runs-on"}, result.CopilotSetupSteps.Only)
	})
}

// errorReturningGetRepositoryByIDClient is a GitHub client that always returns
// an error from GetRepositoryByID.
type errorReturningGetRepositoryByIDClient struct {
	*github.NoopClient
}

//nolint:revive // Method name must match interface
func (c *errorReturningGetRepositoryByIDClient) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	return nil, fmt.Errorf("repository not found")
}
