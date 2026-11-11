package twirpserver

import (
	"context"
	"errors"
	"testing"
	"time"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestCreateCommand_Success(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, &billingProto.CanProceedWithUsageRequest{
		UsageKey: &billingProto.UsageKey{
			Sku:      "coding_agent_premium_request",
			Product:  "copilot",
			Quantity: 1,
			EntityDetail: &billingProto.EntityDetail{
				CustomerId: "123",
				OwnerId:    1,
				RepoId:     2,
				ActorId:    42,
			},
		},
		TrustTier: 0,
	}).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)

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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
		NoopBillingClient: mockBillingClient,
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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute
	resp, err := server.CreateCommand(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.NotEmpty(t, resp.ExternalId)

	// Verify that the command was created in the store
	cmds, err := jobStore.GetCommands(ctx, testJob.AssignmentID, testJob.ID)
	require.NoError(t, err)
	require.Len(t, cmds, 1)
	cmd := cmds[0]
	require.Equal(t, req.JobId, cmd.JobID)
	require.Equal(t, req.ExternalId, cmd.ExternalID)
	require.Equal(t, req.ActorId, cmd.ActorID)
	require.Equal(t, req.Content, cmd.Content)
	require.Equal(t, command.TypeUserMessage, cmd.Type)
	require.Equal(t, command.StatusPending, cmd.Status)
	require.Equal(t, req.Timestamp, cmd.CreatedAt)
}

func TestCreateCommand_JobNotFound(t *testing.T) {
	ctx := t.Context()

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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{},
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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      "non-existent-job-id",
		OwnerId:    1,
		RepoId:     2,
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute
	resp, err := server.CreateCommand(ctx, req)
	require.Error(t, err)
	require.Nil(t, resp)

	// Check that it's a Twirp NotFound error
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.NotFound, twerr.Code())
	require.Contains(t, twerr.Msg(), "no job found for ID")
}

func TestCreateCommand_JobActorIdMismatch(t *testing.T) {
	ctx := t.Context()

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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{},
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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-id",
		SessionID: "session-id",
		ActorID:   123,
		OwnerID:   1,
		RepoID:    2,
		Status:    jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42, // Mismatched ActorID
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute
	resp, err := server.CreateCommand(ctx, req)
	require.Error(t, err)
	require.Nil(t, resp)

	// Check that it's a Twirp NotFound error
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.NotFound, twerr.Code())
}

func TestCreateCommand_TerminalJob(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, &billingProto.CanProceedWithUsageRequest{
		UsageKey: &billingProto.UsageKey{
			Sku:      "coding_agent_premium_request",
			Product:  "copilot",
			Quantity: 1,
			EntityDetail: &billingProto.EntityDetail{
				CustomerId: "123",
				OwnerId:    1,
				RepoId:     2,
				ActorId:    42,
			},
		},
		TrustTier: 0,
	}).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)
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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
		NoopBillingClient: mockBillingClient,
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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-id",
		SessionID: "session-id",
		ActorID:   42,
		OwnerID:   1,
		RepoID:    2,
		Status:    jobs.JobStatusCompleted,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute
	resp, err := server.CreateCommand(ctx, req)
	require.Error(t, err)
	require.Nil(t, resp)

	// Check that it returns a Failed Precondition error when trying to add command to terminal job
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "Expected twirp.Error, got %T", err)
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "cannot create command for job in terminal state")
}

func TestCreateCommand_InsufficientQuota(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, &billingProto.CanProceedWithUsageRequest{
		UsageKey: &billingProto.UsageKey{
			Sku:      "coding_agent_premium_request",
			Product:  "copilot",
			Quantity: 1,
			EntityDetail: &billingProto.EntityDetail{
				CustomerId: "123",
				OwnerId:    1,
				RepoId:     2,
				ActorId:    42,
			},
		},
		TrustTier: 0,
	}).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: false,
	}, nil)
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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				// Return zero remaining quota and no overage permitted
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        0,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 0.0,
							OveragePermitted: false,
							QuotaRemaining:   0.0,
						},
					},
				}, nil
			},
		},
		NoopBillingClient: mockBillingClient,
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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute
	resp, err := server.CreateCommand(ctx, req)
	require.Error(t, err)
	require.Nil(t, resp)

	// Check that it returns a FailedPrecondition error when quota is insufficient
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "Expected twirp.Error, got %T", err)
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "insufficient premium quota")

	// Verify that the command was NOT created in the store
	cmds, err := jobStore.GetCommands(ctx, testJob.AssignmentID, testJob.ID)
	require.NoError(t, err)
	require.Len(t, cmds, 0, "Command should not be created when quota is insufficient")
}

func TestCreateCommand_SufficientQuotaWithOverage(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, &billingProto.CanProceedWithUsageRequest{
		UsageKey: &billingProto.UsageKey{
			Sku:      "coding_agent_premium_request",
			Product:  "copilot",
			Quantity: 1,
			EntityDetail: &billingProto.EntityDetail{
				CustomerId: "123",
				OwnerId:    1,
				RepoId:     2,
				ActorId:    42,
			},
		},
		TrustTier: 0,
	}).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)
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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				// Return zero remaining quota but with overage permitted
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        0,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 0.0,
							OveragePermitted: true,
							QuotaRemaining:   0.0,
						},
					},
				}, nil
			},
		},
		NoopBillingClient: mockBillingClient,
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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute - should succeed because overage is permitted
	resp, err := server.CreateCommand(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.NotEmpty(t, resp.ExternalId)

	// Verify that the command was created in the store
	cmds, err := jobStore.GetCommands(ctx, testJob.AssignmentID, testJob.ID)
	require.NoError(t, err)
	require.Len(t, cmds, 1, "Command should be created when overage is permitted")
}

func TestCreateCommand_CustomerSelectionRequired_FeatureFlagEnabled(t *testing.T) {
	ctx := t.Context()

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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				// Return quota details with sufficient quota
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        100,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 10.0,
							OveragePermitted: false,
							QuotaRemaining:   100.0,
						},
					},
				}, nil
			},
			MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
				// Return empty CustomerIds with multi-SKU access type to trigger customer selection required
				return &copilotLimitersTwirp.GetConsumptiveUserResponse{
					CustomerIds: []int64{},
					AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
				}, nil
			},
		},
	}

	// Create server with feature flag enabled
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentSelectCustomerError: true,
	})

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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute - should fail with FailedPrecondition when feature flag is enabled
	resp, err := server.CreateCommand(ctx, req)
	require.Error(t, err)
	require.Nil(t, resp)

	// Check that it returns a FailedPrecondition error
	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr), "Expected twirp.Error, got %T", err)
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "customer selection required")

	// Verify that the command was NOT created in the store
	cmds, err := jobStore.GetCommands(ctx, testJob.AssignmentID, testJob.ID)
	require.NoError(t, err)
	require.Len(t, cmds, 0, "Command should not be created when customer selection is required and feature flag is enabled")
}

func TestCreateCommand_CustomerSelectionRequired_FeatureFlagDisabled(t *testing.T) {
	ctx := t.Context()

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
						Id:                  req.Id,
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				// Return quota details with sufficient quota
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							Entitlement:      1000,
							Remaining:        100,
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							PercentRemaining: 10.0,
							OveragePermitted: false,
							QuotaRemaining:   100.0,
						},
					},
				}, nil
			},
			MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
				// Return empty CustomerIds with multi-SKU access type to trigger customer selection required
				return &copilotLimitersTwirp.GetConsumptiveUserResponse{
					CustomerIds: []int64{},
					AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
				}, nil
			},
		},
	}

	// Create server with feature flag disabled
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentSelectCustomerError: false,
	})

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
	appProvider := agenticapptest.NewTestProvider(t)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, appProvider, nil, nil, nil, nil)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute - should succeed when feature flag is disabled (fallthrough case)
	resp, err := server.CreateCommand(ctx, req)
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.NotEmpty(t, resp.ExternalId)

	// Verify that the command was created in the store
	cmds, err := jobStore.GetCommands(ctx, testJob.AssignmentID, testJob.ID)
	require.NoError(t, err)
	require.Len(t, cmds, 1, "Command should be created when customer selection is required but feature flag is disabled")
}

func TestCreateCommand_AgentNotEnabled_NonExempt(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: false,
			},
		},
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{},
		NoopLimiterAPI:    &githubtwirp.NoopLimiterAPI{},
	}

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghf := &github.NoopClientFactory{}
	jobStore := memory.NewStore()
	countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	jobSvc := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobSvc, ffClient, appProvider, nil, nil, nil, nil)

	resp, err := server.CreateCommand(ctx, &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "ext-1",
		Content:    "test",
		Timestamp:  time.Now().Unix(),
	})
	require.Nil(t, resp)
	require.Error(t, err)

	var twerr twirp.Error
	require.True(t, errors.As(err, &twerr))
	require.Equal(t, twirp.Aborted, twerr.Code())
	require.Contains(t, twerr.Msg(), "user or repo does not have CCA enabled")
}

func TestCreateCommand_AgentNotEnabled_ExemptGlobalApp(t *testing.T) {
	ctx := t.Context()

	mockBillingClient := billingMocks.NewMockClientInterface(t)
	mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.Anything).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: true,
	}, nil)

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsAgentEnabled: false,
			},
		},
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						Id:                  req.Id,
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
	jobStore := memory.NewStore()
	countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker, nil)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)

	exemptApp := agenticapptest.NewTestApp(88888).WithEnablementExempt().WithGlobalApp()
	appProvider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, exemptApp)
	jobSvc := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test_name", "test@example.com", spokestest.NewClient(t), appProvider, nil)

	// Create a job belonging to the exempt agent
	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		AgentID:      88888,
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobSvc, ffClient, appProvider, nil, nil, nil, nil)

	resp, err := server.CreateCommand(ctx, &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    testJob.OwnerID,
		RepoId:     testJob.RepoID,
		ActorId:    42,
		ExternalId: "ext-1",
		Content:    "test command",
		Timestamp:  time.Now().Unix(),
	})
	require.NoError(t, err)
	require.NotNil(t, resp)
	require.NotEmpty(t, resp.ExternalId)
}
