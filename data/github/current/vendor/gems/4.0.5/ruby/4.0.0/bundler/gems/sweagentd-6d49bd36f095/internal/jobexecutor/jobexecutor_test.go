package jobexecutor

import (
	"context"
	_ "embed"
	"errors"
	"path/filepath"
	"testing"
	"time"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	sweagentv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	sweagentEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0/entities"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	jobCustomAgent "github.com/github/sweagentd/internal/jobs/customagent"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/encoding/protojson"
)

func TestGetQuotaStatus_EmitsPremiumQuotaExceededMetric(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
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
				ActorId:    3,
			},
		},
		TrustTier: 0,
	}).Return(&billingProto.CanProceedWithUsageResponse{
		CanProceed: false,
	}, nil)

	ghTwirp := &githubtwirp.NoopClient{
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							Remaining:        0,
							Entitlement:      10,
							OveragePermitted: false,
						},
					},
				}, nil
			},
		},
		NoopBillingClient: mockBillingClient,
	}

	// Capture metric via MockStatter
	var recordedKey string
	var recordedTags stats.Tags
	var recordedValue int64
	mockStatter := &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, value int64) {
			recordedKey = key
			recordedTags = tags
			recordedValue = value
		},
	}
	obsv := observability.NewNoopExporters()
	obsv.Statter = mockStatter

	executor := &AgentJobExecutor{
		ffClient: ffClient,
		ghTwirp:  ghTwirp,
		obsv:     obsv,
	}

	hasQuota, quota, tokenBasedBilling, err := executor.GetQuotaStatus(context.Background(), 1, 2, 3)
	require.NoError(t, err)
	assert.False(t, hasQuota)
	assert.Equal(t, int32(10), quota)
	assert.False(t, tokenBasedBilling)
	assert.Equal(t, "events.premium_quota_exceeded", recordedKey)
	assert.Equal(t, int64(1), recordedValue)
	assert.Len(t, recordedTags, 0)
}

func TestGetQuotaStatus_ChecksBillingPlatform(t *testing.T) {
	type cpwuResp struct {
		canProceed bool
		err        error
	}
	tests := []struct {
		name           string
		cpwu           cpwuResp
		expectedHas    bool
		expectedQuota  int32
		expectErr      bool
		limiterQuota   int32
		limiterTotal   int32
		limiterOverage bool
	}{
		{
			name:           "CPWU allows, returns true",
			cpwu:           cpwuResp{canProceed: true, err: nil},
			expectedHas:    true,
			expectedQuota:  10,
			expectErr:      false,
			limiterQuota:   0,
			limiterTotal:   10,
			limiterOverage: false,
		},
		{
			name:           "CPWU denies, returns false",
			cpwu:           cpwuResp{canProceed: false, err: nil},
			expectedHas:    false,
			expectedQuota:  0,
			expectErr:      false,
			limiterQuota:   0,
			limiterTotal:   0,
			limiterOverage: false,
		},
		{
			name:           "CPWU errors, returns true even if out of quota",
			cpwu:           cpwuResp{canProceed: false, err: errors.New("cpwu error")},
			expectedHas:    true,
			expectedQuota:  0,
			expectErr:      false,
			limiterQuota:   0,
			limiterTotal:   0,
			limiterOverage: false,
		},
		{
			name:           "CPWU allows, nonzero quota",
			cpwu:           cpwuResp{canProceed: true, err: nil},
			expectedHas:    true,
			expectedQuota:  5,
			expectErr:      false,
			limiterQuota:   5,
			limiterTotal:   5,
			limiterOverage: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockBillingClient := billingMocks.NewMockClientInterface(t)
			mockBillingClient.On("CanProceedWithUsage", mock.Anything, &billingProto.CanProceedWithUsageRequest{
				UsageKey: &billingProto.UsageKey{
					Sku:      "coding_agent_premium_request",
					Product:  "copilot",
					Quantity: 1,
					EntityDetail: &billingProto.EntityDetail{
						CustomerId: "123",
						OwnerId:    123,
						RepoId:     456,
						ActorId:    789,
					},
				},
				TrustTier: 0,
			}).Return(&billingProto.CanProceedWithUsageResponse{
				CanProceed: tt.cpwu.canProceed,
			}, tt.cpwu.err)

			ghTwirp := &githubtwirp.NoopClient{
				NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
					MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
						return &copilotUsersTwirp.GetCopilotUserResponse{
							UserDetails: &copilotUsersTwirp.CopilotUserDetails{
								AnalyticsTrackingId: "test-tracking-id",
							},
						}, nil
					},
				},
				NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
					MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
						return &copilotLimitersTwirp.GetQuotaRemainingResponse{
							QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
								{
									QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
									Remaining:        tt.limiterQuota,
									Entitlement:      tt.limiterTotal,
									OveragePermitted: tt.limiterOverage,
								},
							},
						}, nil
					},
				},
				NoopBillingClient: mockBillingClient,
			}
			obsv := observability.NewNoopExporters()

			executor := &AgentJobExecutor{
				ffClient: featureflags.NewNoopClient(map[string]bool{}),
				ghTwirp:  ghTwirp,
				obsv:     obsv,
			}
			hasQuota, quota, _, err := executor.GetQuotaStatus(context.Background(), int64(123), int64(456), int64(789))
			if tt.expectErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}
			assert.Equal(t, tt.expectedHas, hasQuota)
			assert.Equal(t, tt.expectedQuota, quota)
		})
	}
}

func TestGetQuotaStatus_ReturnsErrorWhenCustomerIdIsMinusOne(t *testing.T) {
	ghTwirp := &githubtwirp.NoopClient{
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							Remaining:        0,
							Entitlement:      10,
							OveragePermitted: false,
						},
					},
				}, nil
			},
			MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
				// Return empty CustomerIds array with MultiSKU to simulate customerId = -1
				return &copilotLimitersTwirp.GetConsumptiveUserResponse{
					CustomerIds: []int64{},
					AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
				}, nil
			},
		},
	}

	obsv := observability.NewNoopExporters()
	executor := &AgentJobExecutor{
		ffClient: featureflags.NewNoopClient(map[string]bool{}),
		ghTwirp:  ghTwirp,
		obsv:     obsv,
	}

	hasQuota, quota, _, err := executor.GetQuotaStatus(context.Background(), int64(123), int64(456), int64(789))

	require.Error(t, err)
	assert.Contains(t, err.Error(), "customer selection required")
	assert.False(t, hasQuota)
	assert.Equal(t, int32(0), quota)
}

func TestCheckQuota_CustomerSelectionRequired_WithFeatureFlag(t *testing.T) {
	tests := []struct {
		name                    string
		selectCustomerFFEnabled bool
		expectError             bool
		expectJobFinalized      bool
	}{
		{
			name:                    "feature flag enabled - should finalize job and return error",
			selectCustomerFFEnabled: true,
			expectError:             true,
			expectJobFinalized:      true,
		},
		{
			name:                    "feature flag disabled - should log and continue",
			selectCustomerFFEnabled: false,
			expectError:             false,
			expectJobFinalized:      false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()

			ffClient := featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentSelectCustomerError: tt.selectCustomerFFEnabled,
			})

			// Mock GitHub Twirp client to return customer selection required error
			ghTwirp := &githubtwirp.NoopClient{
				NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
					MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
						return &copilotUsersTwirp.GetCopilotUserResponse{
							UserDetails: &copilotUsersTwirp.CopilotUserDetails{
								AnalyticsTrackingId: "test-tracking-id",
							},
						}, nil
					},
				},
				NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
					MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
						return &copilotLimitersTwirp.GetQuotaRemainingResponse{
							QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
								{
									QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
									Remaining:        5,
									Entitlement:      10,
									OveragePermitted: false,
								},
							},
						}, nil
					},
					MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
						// Return empty CustomerIds array to simulate customer not selected
						return &copilotLimitersTwirp.GetConsumptiveUserResponse{
							CustomerIds: []int64{},
							AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
						}, nil
					},
				},
			}

			ghFactory := &github.NoopClientFactory{}
			ghFactory.MockPullRequest = &gg.PullRequest{
				State:  gg.Ptr("open"),
				Number: gg.Ptr(123),
			}

			jobStore := memory.NewStore()
			assignment := &jobs.Assignment{
				ID:      "test-assignment",
				OwnerID: 123,
				RepoID:  456,
			}
			jobStore.CreateAssignment(ctx, assignment)

			job := &jobs.Job{
				ID:                "test-job",
				OwnerID:           123,
				RepoID:            456,
				ActorID:           789,
				ActorLogin:        "testuser",
				PullRequestNumber: 123,
				Status:            jobs.JobStatusQueued,
				AssignmentID:      "test-assignment",
			}
			jobStore.CreateJob(ctx, job)

			capiClient := capi.NewNoopClient()
			je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

			gh := ghFactory.NewClient("test-token")

			repoOwner := "testOwner"
			repoName := "testRepo"
			repo := &gg.Repository{
				Owner: &gg.User{
					Login: &repoOwner,
				},
				Name: &repoName,
			}

			// Call checkQuota directly through the private method via the test executor
			err := je.checkQuota(ctx, gh, job, repo)

			if tt.expectError {
				// When feature flag is enabled, should return error
				require.ErrorIs(t, err, githubtwirp.ErrCustomerSelectionRequired)
			} else {
				// When feature flag is disabled, should NOT return error (continue execution)
				require.NoError(t, err)
			}

			if tt.expectJobFinalized {
				// Verify the job was finalized
				updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
				require.NoError(t, err)
				assert.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
			}
		})
	}
}

func TestCancelJob(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, false, nil)
	capiClient := capi.NewNoopClient()

	testJob := &jobs.Job{
		ID:        "job-1234",
		OwnerID:   1,
		RepoID:    2,
		ComputeID: "test-compute-id",
		ActorID:   3,
		Status:    jobs.JobStatusRunning,
	}

	sessionClient := capiClient.NewSessionClient(testJob.ActorID, "test-token", capi.SessionClientConfig{})
	// Create a session for the job
	sessionResp, err := sessionClient.CreateSession(ctx, capi.SessionCreate{
		OwnerID:          uint64(testJob.OwnerID),
		RepoID:           uint64(testJob.RepoID),
		ResourceID:       123,
		ResourceType:     capi.ResourceTypePullRequest,
		AgentTaskID:      uuid.NewString(),
		EventType:        string(jobs.EventTypePullRequestReview),
		EventURL:         "https://example.com",
		EventIdentifiers: []string{"123"},
		EventContent:     "@copilot please help i only know how to vibe code",
		State:            capi.SessionStateInProgress,
		Name:             "Test Session",
	})
	require.NoError(t, err)
	testJob.SessionID = sessionResp.ID

	_, err = jobStore.CreateJob(ctx, testJob)
	require.NoError(t, err)

	repoOwner := "oregon"
	repoName := "trail"

	t.Run("using valid Job", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		gh := &github.NoopClient{}
		err := je.CancelJob(ctx, gh, testJob, repoOwner, repoName)
		require.NoError(t, err)
		assert.Equal(t, 1, len(je.TerminateAgentCalls()))
		terminateCallOpts := je.TerminateAgentCalls()[0]
		assert.Equal(t, testJob.RepoID, terminateCallOpts.RepoID)
		assert.Equal(t, testJob.OwnerID, terminateCallOpts.OwnerID)
		assert.Equal(t, testJob.ComputeID, terminateCallOpts.ComputeID)
	})
	t.Run("fails on terminal job", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		testJobNonTerminal := *testJob
		testJobNonTerminal.Status = jobs.JobStatusCompleted
		err := je.CancelJob(ctx, &github.NoopClient{}, &testJobNonTerminal, repoOwner, repoName)
		require.Error(t, err)
	})
	t.Run("finalizes non-executed job", func(t *testing.T) {
		testJobNonExecuted := *testJob
		testJobNonExecuted.Status = jobs.JobStatusQueued
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		err = je.CancelJob(ctx, &github.NoopClient{}, &testJobNonExecuted, repoOwner, repoName)
		require.NoError(t, err)
	})
	t.Run("errors on invalid status", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		testJobBadStatus := *testJob
		testJobBadStatus.Status = "fail me yo"
		err := je.CancelJob(ctx, &github.NoopClient{}, &testJobBadStatus, repoOwner, repoName)
		require.Error(t, err)
	})
	t.Run("errors if terminate fails", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		je.Launcher.TerminateAgentError = errors.New("you died of dysentery")
		err := je.CancelJob(ctx, &github.NoopClient{}, testJob, repoOwner, repoName)
		require.Error(t, err)
	})
	t.Run("finalizes sandbox job immediately after cancel", func(t *testing.T) {
		sandboxJob := &jobs.Job{
			ID:        "job-sandbox-cancel",
			OwnerID:   1,
			RepoID:    2,
			ComputeID: "sb-123",
			ActorID:   3,
			Status:    jobs.JobStatusRunning,
			Launcher:  launcher.TypeSandbox,
			SessionID: sessionResp.ID,
		}
		_, err := jobStore.CreateJob(ctx, sandboxJob)
		require.NoError(t, err)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		err = je.CancelJob(ctx, &github.NoopClient{}, sandboxJob, repoOwner, repoName)
		require.NoError(t, err)
		assert.Equal(t, 1, len(je.TerminateAgentCalls()), "TerminateAgent should be called")
		assert.Equal(t, "sb-123", je.TerminateAgentCalls()[0].ComputeID)
		assert.Equal(t, jobs.JobStatusCancelled, sandboxJob.Status, "sandbox job should be finalized as cancelled immediately")
	})
	t.Run("finalizes job directly when workflow already completed (409)", func(t *testing.T) {
		runningJob := &jobs.Job{
			ID:        "job-409",
			OwnerID:   1,
			RepoID:    2,
			ComputeID: "test-compute-id",
			ActorID:   3,
			Status:    jobs.JobStatusRunning,
			SessionID: sessionResp.ID,
		}
		_, err := jobStore.CreateJob(ctx, runningJob)
		require.NoError(t, err)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		je.Launcher.TerminateAgentError = github.ErrWorkflowRunAlreadyCompleted
		err = je.CancelJob(ctx, &github.NoopClient{}, runningJob, repoOwner, repoName)
		require.NoError(t, err)
		assert.Equal(t, jobs.JobStatusCancelled, runningJob.Status, "job should be finalized as cancelled")
	})
}

func TestAgentJobExecutor_ProcessJob(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	assignment := &jobs.Assignment{
		ID:      "assign-1",
		OwnerID: 1,
		RepoID:  2,
	}

	baseJob := &jobs.Job{
		ID:                "job-1",
		OwnerID:           1,
		RepoID:            2,
		ActorID:           3,
		ActorLogin:        "actor",
		Status:            jobs.JobStatusQueued,
		AssignmentID:      "assign-1",
		PullRequestID:     123,
		PullRequestNumber: 123,
	}
	agentJob := &aqueductJobs.AgentJob{
		RepositoryId:      baseJob.RepoID,
		OwnerId:           baseJob.OwnerID,
		AssignmentId:      baseJob.AssignmentID,
		JobId:             baseJob.ID,
		PullRequestId:     1,
		PullRequestNumber: int32(baseJob.PullRequestNumber),
	}

	t.Run("emits job started event when job gets processed", func(t *testing.T) {
		hydroFFClient := featureflags.NewNoopClient(nil)
		ghFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("open"),
			Number:    gg.Ptr(baseJob.PullRequestNumber),
			Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
		}

		messageChan := make(chan hydro.Message, 10) // Increased buffer to handle multiple events
		sink, err := hydro.NewMemorySink(messageChan)
		require.NoError(t, err)

		publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
		localObsv := observability.NewNoopExporters()
		obsvWithPublisher := localObsv.WithPublisher(publisher)

		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsvWithPublisher, hydroFFClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

		job := &jobs.Job{
			ID:                "job-1",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			ActorLogin:        "actor",
			Status:            jobs.JobStatusQueued,
			AssignmentID:      "assign-1",
			PullRequestID:     123,
			EventType:         jobs.EventTypePullRequestReview,
			EventIdentifiers:  []string{"123"},
			EventContent:      "@copilot please help i only know how to vibe code",
			Action:            jobs.AgentActionFixPRComment,
			PullRequestNumber: 123,
		}

		_, err = jobStore.CreateJob(context.Background(), job)
		require.NoError(t, err)

		err = je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)

		require.Len(t, je.LaunchAgentCalls(), 1)

		// Wait for and verify the job started event
		var jobStartedEvent sweagentv0.JobStarted
		select {
		case eventReceived := <-messageChan:
			err := protojson.Unmarshal(eventReceived.Value, &jobStartedEvent)
			require.NoError(t, err)
			require.Equal(t, int64(123), jobStartedEvent.Trigger.IdentifierId)
			require.Equal(t, int64(1), jobStartedEvent.Job.OwnerId)
			require.Equal(t, int64(2), jobStartedEvent.Job.RepositoryId)
			require.Equal(t, int64(123), jobStartedEvent.Job.PullRequestId)
			require.Equal(t, sweagentEntitiesv0.JobTrigger_PULL_REQUEST_REVIEW_SUBMIT, jobStartedEvent.Trigger.Type)
			require.Equal(t, sweagentEntitiesv0.ActionType_FIX_PR_COMMENT, jobStartedEvent.Action)
		case <-time.After(5 * time.Second):
			t.Fatal("timeout waiting for job started event")
		}

		// Drain any remaining events in the channel to prevent deadlocks
		select {
		case <-messageChan:
			// Consume any additional events without checking them
		default:
			// No more events
		}
	})

	t.Run("does not launch agent if job is not queued", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		job := *baseJob
		job.Status = jobs.JobStatusRunning
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 0)
	})

	t.Run("does not launch agent if user does not have push access", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		ghFactory.MockGetUserPermissionsForRepositoryByID = func(ctx context.Context, repoID int64, login string) (*github.RepositoryPermissions, error) {
			return &github.RepositoryPermissions{Push: false}, nil
		}

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 0)
	})

	t.Run("does not launch agent if user lacks read access to additional repository with multi-repo flag", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		multiRepoFFClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMultiRepoRead: true,
		})
		localGHFactory := &github.NoopClientFactory{}
		localGHFactory.MockGetUserPermissionsForRepositoryByID = func(ctx context.Context, repoID int64, login string) (*github.RepositoryPermissions, error) {
			if repoID == baseJob.RepoID {
				return &github.RepositoryPermissions{Push: true, Pull: true}, nil
			}
			// Actor lacks read access to the additional repo
			return &github.RepositoryPermissions{Push: false, Pull: false}, nil
		}
		localGHFactory.MockPullRequest = &gg.PullRequest{
			State:  gg.Ptr("open"),
			Number: gg.Ptr(baseJob.PullRequestNumber),
		}
		je := NewTestJobExecutor(obsv, multiRepoFFClient, jobStore, localGHFactory, ghTwirp, capiClient, nil, nil)

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		job.AdditionalRepositories = []jobs.RepositoryRef{
			{RepoID: 42, OwnerID: 10, RepoNodeID: "n42", OwnerNodeID: "o10"},
		}
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 0)
		updatedJob, getErr := jobStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, getErr)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
	})

	t.Run("launches agent when user has read access to additional repositories with multi-repo flag", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		multiRepoFFClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMultiRepoRead: true,
		})
		localGHFactory := &github.NoopClientFactory{}
		localGHFactory.MockGetUserPermissionsForRepositoryByID = func(ctx context.Context, repoID int64, login string) (*github.RepositoryPermissions, error) {
			if repoID == baseJob.RepoID {
				return &github.RepositoryPermissions{Push: true, Pull: true}, nil
			}
			// Actor has read access to additional repo
			return &github.RepositoryPermissions{Push: false, Pull: true}, nil
		}
		localGHFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("open"),
			Number:    gg.Ptr(baseJob.PullRequestNumber),
			Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
		}
		je := NewTestJobExecutor(obsv, multiRepoFFClient, jobStore, localGHFactory, ghTwirp, capiClient, nil, nil)

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		job.AdditionalRepositories = []jobs.RepositoryRef{
			{RepoID: 42, OwnerID: 10, RepoNodeID: "n42", OwnerNodeID: "o10"},
		}
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 1)
	})

	t.Run("skips additional repo permission check when multi-repo flag is disabled", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		disabledFFClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMultiRepoRead: false,
		})
		localGHFactory := &github.NoopClientFactory{}
		localGHFactory.MockGetUserPermissionsForRepositoryByID = func(ctx context.Context, repoID int64, login string) (*github.RepositoryPermissions, error) {
			if repoID == baseJob.RepoID {
				return &github.RepositoryPermissions{Push: true, Pull: true}, nil
			}
			// Would fail if checked, but flag is off
			return &github.RepositoryPermissions{Push: false, Pull: false}, nil
		}
		localGHFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("open"),
			Number:    gg.Ptr(baseJob.PullRequestNumber),
			Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
		}
		je := NewTestJobExecutor(obsv, disabledFFClient, jobStore, localGHFactory, ghTwirp, capiClient, nil, nil)

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		job.AdditionalRepositories = []jobs.RepositoryRef{
			{RepoID: 42, OwnerID: 10, RepoNodeID: "n42", OwnerNodeID: "o10"},
		}
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 1)
	})

	t.Run("does not launch agent when auth check flag enabled and authorization is required", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		gatedFFClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCheckAgenticAppAuth: true,
		})
		gatedGHTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, false, nil)
		var receivedUserID uint64
		gatedGHTwirp.NoopSweagentdAPI.MockIntegrationNeedsAuthorizationFromUser = func(ctx context.Context, req *sweagentdv1.IntegrationNeedsAuthorizationFromUserRequest) (*sweagentdv1.IntegrationNeedsAuthorizationFromUserResponse, error) {
			receivedUserID = req.GetUserId()
			return &sweagentdv1.IntegrationNeedsAuthorizationFromUserResponse{NeedsAuthorization: true}, nil
		}
		localGHFactory := &github.NoopClientFactory{}
		je := NewTestJobExecutor(obsv, gatedFFClient, jobStore, localGHFactory, gatedGHTwirp, capiClient, nil, nil)

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		job.AgentID = 1
		job.ActorID = 999
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 0)
		require.Equal(t, uint64(999), receivedUserID)
		updatedJob, getErr := jobStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, getErr)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
		require.Equal(t, joberrors.ErrAgenticAppUnauthorized.Code, updatedJob.Error.ResponseStatusCode)
	})

	t.Run("still launches agent when auth check flag disabled even if authorization would be required", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		ungatedGHTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
		ungatedGHTwirp.NoopSweagentdAPI.MockIntegrationNeedsAuthorizationFromUser = func(ctx context.Context, req *sweagentdv1.IntegrationNeedsAuthorizationFromUserRequest) (*sweagentdv1.IntegrationNeedsAuthorizationFromUserResponse, error) {
			return &sweagentdv1.IntegrationNeedsAuthorizationFromUserResponse{NeedsAuthorization: true}, nil
		}
		localGHFactory := &github.NoopClientFactory{}
		localGHFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("open"),
			Number:    gg.Ptr(baseJob.PullRequestNumber),
			Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
		}
		je := NewTestJobExecutor(obsv, ffClient, jobStore, localGHFactory, ungatedGHTwirp, capiClient, nil, nil)

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		job.AgentID = 1
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 1)
	})

	t.Run("skips user permission check for org-actor jobs", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		permCheckCalled := false
		ghFactory.MockGetUserPermissionsForRepositoryByID = func(ctx context.Context, repoID int64, login string) (*github.RepositoryPermissions, error) {
			permCheckCalled = true
			return &github.RepositoryPermissions{Push: false}, nil
		}

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		job.ActorType = jobs.ActorTypeOrg
		job.ActorLogin = "my-org"
		job.PullRequestID = 0
		job.PullRequestNumber = 0
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.False(t, permCheckCalled, "permission check should be skipped for org-actor jobs")
		require.Len(t, je.LaunchAgentCalls(), 1, "org-actor job should proceed without permission check")
	})

	t.Run("does not launch agent if there are other running jobs for assignment", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		runningJob := *baseJob
		runningJob.ID = "job-2"
		runningJob.Status = jobs.JobStatusRunning
		runningJob.ComputeID = "123"
		_, _ = jobStore.CreateJob(context.Background(), &runningJob)

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 0)
	})

	t.Run("does not launch agent if pull request is not open", func(t *testing.T) {
		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		ghFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("closed"),
			Number:    gg.Ptr(123),
			Assignees: []*gg.User{{Login: gg.Ptr("copilot[bot]")}},
		}

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		_, _ = jobStore.CreateJob(context.Background(), &job)
		err := je.ProcessJob(context.Background(), agentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 0)
	})

	t.Run("sets WasDelayed when RequeueCount is greater than zero", func(t *testing.T) {
		localGHFactory := &github.NoopClientFactory{}
		localGHFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("open"),
			Number:    gg.Ptr(baseJob.PullRequestNumber),
			Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
		}
		localGHTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)

		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsv, ffClient, jobStore, localGHFactory, localGHTwirp, capiClient, nil, nil)

		job := *baseJob
		job.Status = jobs.JobStatusQueued
		_, err := jobStore.CreateJob(context.Background(), &job)
		require.NoError(t, err)

		delayedAgentJob := &aqueductJobs.AgentJob{
			RepositoryId:      baseJob.RepoID,
			OwnerId:           baseJob.OwnerID,
			AssignmentId:      baseJob.AssignmentID,
			JobId:             baseJob.ID,
			PullRequestId:     1,
			PullRequestNumber: int32(baseJob.PullRequestNumber),
			RequeueCount:      3,
		}

		err = je.ProcessJob(context.Background(), delayedAgentJob)
		require.NoError(t, err)
		require.Len(t, je.LaunchAgentCalls(), 1)

		// Verify WasDelayed was persisted on the job
		updatedJob, err := jobStore.GetJob(context.Background(), baseJob.OwnerID, baseJob.RepoID, baseJob.ID)
		require.NoError(t, err)
		require.True(t, updatedJob.WasDelayed, "WasDelayed should be true when RequeueCount > 0")
	})

	t.Run("WasDelayed is false when RequeueCount is zero", func(t *testing.T) {
		localGHFactory := &github.NoopClientFactory{}
		localGHFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("open"),
			Number:    gg.Ptr(baseJob.PullRequestNumber),
			Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
		}
		localGHTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)

		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsv, ffClient, jobStore, localGHFactory, localGHTwirp, capiClient, nil, nil)

		job := *baseJob
		job.ID = "job-not-delayed"
		job.Status = jobs.JobStatusQueued
		_, err := jobStore.CreateJob(context.Background(), &job)
		require.NoError(t, err)

		nonDelayedAgentJob := &aqueductJobs.AgentJob{
			RepositoryId:      baseJob.RepoID,
			OwnerId:           baseJob.OwnerID,
			AssignmentId:      baseJob.AssignmentID,
			JobId:             "job-not-delayed",
			PullRequestId:     1,
			PullRequestNumber: int32(baseJob.PullRequestNumber),
			RequeueCount:      0,
		}

		err = je.ProcessJob(context.Background(), nonDelayedAgentJob)
		require.NoError(t, err)

		updatedJob, err := jobStore.GetJob(context.Background(), baseJob.OwnerID, baseJob.RepoID, "job-not-delayed")
		require.NoError(t, err)
		require.False(t, updatedJob.WasDelayed, "WasDelayed should be false when RequeueCount is 0")
	})
}

func TestAgentJobExecutor_ExecuteJob_SetsDefaultCustomAgent(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	jobStore := memory.NewStore()
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	job := &jobs.Job{
		ID:               "test-job",
		ActorID:          123,
		Status:           jobs.JobStatusPending,
		RepoID:           456,
		OwnerID:          789,
		ProblemStatement: jobs.ProblemStatement{Content: "test problem"},
		RunOptions:       jobs.RunOptions{},
		CustomAgent: jobCustomAgent.DBRecord{
			Name:        "",
			RepoOwnerID: 789,
			RepoID:      456,
			RepoOwner:   "test-owner",
			RepoName:    "test-repo",
		},
	}
	createdJob, err := jobStore.CreateJob(context.Background(), job)
	require.NoError(t, err)

	gh := &github.NoopClient{}
	app := agenticapptest.NewTestCopilot(t)

	repoOwner := "test-owner"
	repoName := "test-repo"
	repo := &gg.Repository{
		Owner: &gg.User{
			Login: &repoOwner,
		},
		Name: &repoName,
	}

	err = je.executeJob(context.Background(), gh, app, createdJob, repo, "nonce")
	require.NoError(t, err)

	expectedCustomAgent := customagent.Copilot(789, 456, repoOwner, repoName)

	require.Equal(t, expectedCustomAgent, createdJob.Args.CustomAgent)
}

type launchMetricBuilder struct {
	launcher launcher.AgentLauncher
}

func (b launchMetricBuilder) Build(context.Context, launcher.Type) (launcher.AgentLauncher, error) {
	return b.launcher, nil
}

func (b launchMetricBuilder) EnvironmentDefault() launcher.Type {
	return launcher.TypeSandbox
}

type launchMetricLauncher struct {
	obsv                 observability.Exporters
	launcherTypeAtLaunch *string
}

func (l launchMetricLauncher) LaunchAgent(ctx context.Context, _ *launcher.LaunchAgentOpts) (*launcher.LaunchResult, error) {
	if job, ok := requestctx.Job(ctx); ok && l.launcherTypeAtLaunch != nil {
		*l.launcherTypeAtLaunch = job.LauncherType
	}
	l.obsv.Increment(ctx, "launcher.test", stats.Tags{})
	return &launcher.LaunchResult{ComputeID: "sandbox-123"}, nil
}

func (l launchMetricLauncher) TerminateAgent(context.Context, launcher.TerminateAgentOpts) error {
	return nil
}

func (l launchMetricLauncher) LauncherType() launcher.Type {
	return launcher.TypeSandbox
}

type copyingJobsStore struct {
	db.JobsStore
}

func copyJob(job *jobs.Job) *jobs.Job {
	if job == nil {
		return nil
	}
	copied := *job
	return &copied
}

func (s copyingJobsStore) CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	created, err := s.JobsStore.CreateJob(ctx, copyJob(job))
	return copyJob(created), err
}

func (s copyingJobsStore) GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error) {
	job, err := s.JobsStore.GetJob(ctx, owner, repo, id)
	return copyJob(job), err
}

func (s copyingJobsStore) UpdateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	updated, err := s.JobsStore.UpdateJob(ctx, copyJob(job))
	return copyJob(updated), err
}

func (s copyingJobsStore) UpsertJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	upserted, err := s.JobsStore.UpsertJob(ctx, copyJob(job))
	return copyJob(upserted), err
}

func (s copyingJobsStore) PatchJob(ctx context.Context, job *jobs.Job, patch db.JobPatch, opts ...db.PatchJobOption) error {
	return s.JobsStore.PatchJob(ctx, copyJob(job), patch, opts...)
}

func TestLaunchAgentSetsLaunchWindowRequestContext(t *testing.T) {
	var launcherMetricTags stats.Tags
	var launcherTypeAtLaunch string
	obsv := observability.NewNoopExporters()
	obsv = obsv.WithTelemetryFunc(requestctx.ToTelemetry)
	obsv.Statter = &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, value int64) {
			if key != "launcher.test" {
				return
			}
			launcherMetricTags = tags
		},
	}

	jobStore := memory.NewStore()
	job := &jobs.Job{
		ID:           "job-launch-window",
		OwnerID:      1,
		RepoID:       2,
		ActorID:      3,
		AssignmentID: "assignment-launch-window",
		Status:       jobs.JobStatusQueued,
	}
	_, err := jobStore.CreateJob(context.Background(), job)
	require.NoError(t, err)

	ctx := requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
		ID:           job.ID,
		OwnerID:      job.OwnerID,
		RepoID:       job.RepoID,
		AssignmentID: job.AssignmentID,
	}))

	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, false, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)
	je := NewTestJobExecutor(obsv, featureflags.NewNoopClient(nil), jobStore, &github.NoopClientFactory{}, ghTwirp, capiClient, nil, nil)
	je.launchers = launchMetricBuilder{launcher: launchMetricLauncher{
		obsv:                 obsv,
		launcherTypeAtLaunch: &launcherTypeAtLaunch,
	}}

	_, err = je.launchAgent(ctx, &launcher.LaunchAgentOpts{}, job)
	require.NoError(t, err)
	require.Equal(t, "sandbox", launcherTypeAtLaunch)
	require.NotContains(t, launcherMetricTags, "launcher_type")
	ctxJob, ok := requestctx.Job(ctx)
	require.True(t, ok)
	require.Equal(t, "sandbox-123", ctxJob.ComputeID)
}

type launchArgPersistenceLauncher struct {
	t                                    *testing.T
	store                                db.JobsStore
	launcherType                         launcher.Type
	computeID                            string
	callBeforeAgentStart                 bool
	expectPersistedBeforeLaunch          bool
	expectPersistedAfterBeforeAgentStart bool
	expectedNonceHash                    string
}

func (l launchArgPersistenceLauncher) LaunchAgent(ctx context.Context, opts *launcher.LaunchAgentOpts) (*launcher.LaunchResult, error) {
	l.t.Helper()

	job, err := l.store.GetJob(ctx, opts.GitHubRepoOwnerID, opts.GitHubRepoID, opts.JobID)
	require.NoError(l.t, err)
	if l.expectPersistedBeforeLaunch {
		requireLaunchOptionsPersisted(l.t, opts, job, l.LauncherType())
	} else {
		requireLaunchOptionsNotPersisted(l.t, job)
	}
	if l.expectedNonceHash != "" {
		if l.expectPersistedBeforeLaunch {
			require.Equal(l.t, l.expectedNonceHash, job.NonceHash)
		} else {
			require.Empty(l.t, job.NonceHash)
		}
	}

	computeID := l.computeID
	if computeID == "" {
		computeID = "sandbox-args"
	}
	if l.callBeforeAgentStart {
		require.NotNil(l.t, opts.BeforeAgentStart)
		require.NoError(l.t, opts.BeforeAgentStart(ctx, &launcher.LaunchResult{
			ComputeID:        computeID,
			CustomSetupSteps: true,
			RunsOn:           "custom-runner",
		}))
		job, err = l.store.GetJob(ctx, opts.GitHubRepoOwnerID, opts.GitHubRepoID, opts.JobID)
		require.NoError(l.t, err)
		if l.expectPersistedAfterBeforeAgentStart {
			requireLaunchOptionsPersisted(l.t, opts, job, l.LauncherType())
		}
		if l.expectedNonceHash != "" {
			require.Equal(l.t, l.expectedNonceHash, job.NonceHash)
		}
		require.Equal(l.t, computeID, job.ComputeID)
		require.NotZero(l.t, job.LaunchedAt)
		require.Equal(l.t, jobs.JobStatusRunning, job.Status)
	} else {
		require.Nil(l.t, opts.BeforeAgentStart)
	}

	return &launcher.LaunchResult{ComputeID: computeID, CustomSetupSteps: true, RunsOn: "custom-runner"}, nil
}

func (l launchArgPersistenceLauncher) TerminateAgent(context.Context, launcher.TerminateAgentOpts) error {
	return nil
}

func (l launchArgPersistenceLauncher) LauncherType() launcher.Type {
	if l.launcherType != "" {
		return l.launcherType
	}
	return launcher.TypeSandbox
}

func requireLaunchOptionsPersisted(t *testing.T, opts *launcher.LaunchAgentOpts, job *jobs.Job, expectedLauncher launcher.Type) {
	t.Helper()

	require.Equal(t, opts.GitHubRepo, job.Args.GitHubRepo)
	require.Equal(t, opts.GitHubRepoOwner, job.Args.GitHubRepoOwner)
	require.Equal(t, opts.GitHubRepoName, job.Args.GitHubRepoName)
	require.Equal(t, opts.GitHubRepoID, job.Args.GitHubRepoID)
	require.Equal(t, opts.GitHubRepoOwnerID, job.Args.GitHubRepoOwnerID)
	require.Equal(t, opts.BranchName, job.Args.BranchName)
	require.Equal(t, expectedLauncher, job.Launcher)
}

func requireLaunchOptionsNotPersisted(t *testing.T, job *jobs.Job) {
	t.Helper()

	require.Empty(t, job.Args.GitHubRepo)
	require.Empty(t, job.Args.GitHubRepoOwner)
	require.Empty(t, job.Args.GitHubRepoName)
	require.Empty(t, job.Args.GitHubRepoID)
	require.Empty(t, job.Args.GitHubRepoOwnerID)
	require.Empty(t, job.Args.BranchName)
	require.Empty(t, job.Launcher)
}

func TestLaunchAgentPersistsCallbackVisibleArgs(t *testing.T) {
	testCases := []struct {
		name                                 string
		jobID                                string
		flagEnabled                          bool
		launcherType                         launcher.Type
		computeID                            string
		callBeforeAgentStart                 bool
		expectedPersistenceStrategy          string
		expectPersistedBeforeLaunch          bool
		expectPersistedAfterBeforeAgentStart bool
	}{
		{
			name:  "feature flag disabled",
			jobID: "job-launch-args-ff-disabled",
		},
		{
			name:                                 "feature flag enabled",
			jobID:                                "job-launch-args-ff-enabled",
			flagEnabled:                          true,
			callBeforeAgentStart:                 true,
			expectedPersistenceStrategy:          "pre_agent_update",
			expectPersistedAfterBeforeAgentStart: true,
		},
		{
			name:         "feature flag enabled non-sandbox",
			jobID:        "job-launch-args-ff-enabled-actions",
			flagEnabled:  true,
			launcherType: launcher.TypeActions,
			computeID:    "12345",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			obsv := observability.NewNoopExporters()
			var persistenceMetricTags []stats.Tags
			obsv.Statter = &observability.MockStatter{
				MockCounter: func(key string, tags stats.Tags, value int64) {
					if key != callbackFieldsPersistBeforeLaunchMetric {
						return
					}
					persistenceMetricTags = append(persistenceMetricTags, stats.Tags{
						"launcher_type": tags["launcher_type"],
						"result":        tags["result"],
						"strategy":      tags["strategy"],
					})
				},
			}
			jobStore := copyingJobsStore{JobsStore: memory.NewStore()}
			expectedLauncher := tc.launcherType
			if expectedLauncher == "" {
				expectedLauncher = launcher.TypeSandbox
			}
			job := &jobs.Job{
				ID:           tc.jobID,
				OwnerID:      1,
				RepoID:       2,
				ActorID:      3,
				AssignmentID: "assignment-launch-args",
				Status:       jobs.JobStatusQueued,
				// Keep this focused on launch persistence without requiring a CAPI session update.
				UseAsyncSessions: true,
			}
			_, err := jobStore.CreateJob(context.Background(), job)
			require.NoError(t, err)
			expectedNonceHash := ""
			if tc.flagEnabled {
				expectedNonceHash = jobs.HashNonce("launch-args-nonce")
				job.NonceHash = expectedNonceHash
			}

			ctx := requestctx.NewContext(context.Background())
			require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
				ID:           job.ID,
				OwnerID:      job.OwnerID,
				RepoID:       job.RepoID,
				AssignmentID: job.AssignmentID,
			}))

			flags := map[string]bool{}
			if tc.flagEnabled {
				flags[featureflags.CopilotSWEAgentSandboxPersistCallbackFieldsBeforeCLIExec] = true
			}
			ffClient := featureflags.NewNoopClient(flags)
			ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, false, nil)
			capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", ffClient)
			require.NoError(t, err)
			je := NewTestJobExecutor(obsv, ffClient, jobStore, &github.NoopClientFactory{}, ghTwirp, capiClient, nil, nil)
			je.launchers = launchMetricBuilder{launcher: launchArgPersistenceLauncher{
				t:                                    t,
				store:                                jobStore,
				launcherType:                         tc.launcherType,
				computeID:                            tc.computeID,
				callBeforeAgentStart:                 tc.callBeforeAgentStart,
				expectPersistedBeforeLaunch:          tc.expectPersistedBeforeLaunch,
				expectPersistedAfterBeforeAgentStart: tc.expectPersistedAfterBeforeAgentStart,
				expectedNonceHash:                    expectedNonceHash,
			}}

			launchOpts := &launcher.LaunchAgentOpts{
				JobID:             job.ID,
				GitHubRepo:        "owner/repo",
				GitHubRepoOwner:   "owner",
				GitHubRepoName:    "repo",
				GitHubRepoID:      job.RepoID,
				GitHubRepoOwnerID: job.OwnerID,
				BranchName:        "main",
			}
			launchedJob, err := je.launchAgent(ctx, launchOpts, job)
			require.NoError(t, err)
			requireLaunchOptionsPersisted(t, launchOpts, launchedJob, expectedLauncher)

			persistedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
			require.NoError(t, err)
			requireLaunchOptionsPersisted(t, launchOpts, persistedJob, expectedLauncher)
			if tc.expectPersistedAfterBeforeAgentStart {
				require.False(t, persistedJob.CustomSetupStepsUsed)
				require.Empty(t, persistedJob.RunsOn)
			} else {
				require.True(t, persistedJob.CustomSetupStepsUsed)
				require.Equal(t, "custom-runner", persistedJob.RunsOn)
			}
			if expectedNonceHash != "" {
				require.Equal(t, expectedNonceHash, persistedJob.NonceHash)
			}
			if tc.expectedPersistenceStrategy == "" {
				require.Empty(t, persistenceMetricTags)
			} else {
				require.Equal(t, []stats.Tags{{
					"launcher_type": string(expectedLauncher),
					"result":        "success",
					"strategy":      tc.expectedPersistenceStrategy,
				}}, persistenceMetricTags)
			}
		})
	}
}

type launchFailureAfterBeforeAgentStartLauncher struct {
	t *testing.T
}

func (l launchFailureAfterBeforeAgentStartLauncher) LaunchAgent(ctx context.Context, opts *launcher.LaunchAgentOpts) (*launcher.LaunchResult, error) {
	l.t.Helper()

	require.NotNil(l.t, opts.BeforeAgentStart)
	require.NoError(l.t, opts.BeforeAgentStart(ctx, &launcher.LaunchResult{ComputeID: "sandbox-start-failed"}))
	return nil, launcher.NonRetriableLaunchError(errors.New("cli start failed"))
}

func (l launchFailureAfterBeforeAgentStartLauncher) TerminateAgent(context.Context, launcher.TerminateAgentOpts) error {
	return nil
}

func (l launchFailureAfterBeforeAgentStartLauncher) LauncherType() launcher.Type {
	return launcher.TypeSandbox
}

func TestLaunchAgentFinalizesJobWhenAgentStartFailsAfterPreAgentUpdate(t *testing.T) {
	obsv := observability.NewNoopExporters()
	var launchFailureAfterPersistTags stats.Tags
	obsv.Statter = &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, value int64) {
			if key != launchFailedAfterCallbackFieldsMetric {
				return
			}
			launchFailureAfterPersistTags = stats.Tags{
				"launcher_type": tags["launcher_type"],
			}
		},
	}
	jobStore := copyingJobsStore{JobsStore: memory.NewStore()}
	job := &jobs.Job{
		ID:               "job-launch-start-failure",
		OwnerID:          1,
		RepoID:           2,
		ActorID:          3,
		AssignmentID:     "assignment-launch-start-failure",
		Status:           jobs.JobStatusQueued,
		NonceHash:        jobs.HashNonce("launch-start-failure-nonce"),
		UseAsyncSessions: true,
	}
	_, err := jobStore.CreateJob(context.Background(), job)
	require.NoError(t, err)

	ctx := requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
		ID:           job.ID,
		OwnerID:      job.OwnerID,
		RepoID:       job.RepoID,
		AssignmentID: job.AssignmentID,
	}))

	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentSandboxPersistCallbackFieldsBeforeCLIExec: true,
	})
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, false, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", ffClient)
	require.NoError(t, err)
	je := NewTestJobExecutor(obsv, ffClient, jobStore, &github.NoopClientFactory{}, ghTwirp, capiClient, nil, nil)
	je.launchers = launchMetricBuilder{launcher: launchFailureAfterBeforeAgentStartLauncher{t: t}}

	launchedJob, err := je.launchAgent(ctx, &launcher.LaunchAgentOpts{
		JobID:             job.ID,
		GitHubRepoID:      job.RepoID,
		GitHubRepoOwnerID: job.OwnerID,
	}, job)
	require.NoError(t, err)
	require.Nil(t, launchedJob)

	persistedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	require.NoError(t, err)
	require.Equal(t, jobs.JobStatusFailed, persistedJob.Status)
	require.Equal(t, "sandbox-start-failed", persistedJob.ComputeID)
	require.NotZero(t, persistedJob.LaunchedAt)
	require.NotZero(t, persistedJob.CompletedAt)
	require.Equal(t, stats.Tags{"launcher_type": string(launcher.TypeSandbox)}, launchFailureAfterPersistTags)
}

type missingNonceBeforeAgentStartLauncher struct {
	t *testing.T
}

func (l missingNonceBeforeAgentStartLauncher) LaunchAgent(ctx context.Context, opts *launcher.LaunchAgentOpts) (*launcher.LaunchResult, error) {
	l.t.Helper()

	require.NotNil(l.t, opts.BeforeAgentStart)
	err := opts.BeforeAgentStart(ctx, &launcher.LaunchResult{ComputeID: "sandbox-missing-nonce"})
	require.Error(l.t, err)
	require.ErrorContains(l.t, err, "missing nonce hash before sandbox agent start")
	return nil, err
}

func (l missingNonceBeforeAgentStartLauncher) TerminateAgent(context.Context, launcher.TerminateAgentOpts) error {
	return nil
}

func (l missingNonceBeforeAgentStartLauncher) LauncherType() launcher.Type {
	return launcher.TypeSandbox
}

func TestLaunchAgentFailsBeforeAgentStartWhenSandboxNonceMissing(t *testing.T) {
	obsv := observability.NewNoopExporters()
	var persistenceMetricTags stats.Tags
	obsv.Statter = &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, value int64) {
			if key != callbackFieldsPersistBeforeLaunchMetric {
				return
			}
			persistenceMetricTags = stats.Tags{
				"launcher_type": tags["launcher_type"],
				"result":        tags["result"],
				"strategy":      tags["strategy"],
			}
		},
	}
	jobStore := copyingJobsStore{JobsStore: memory.NewStore()}
	job := &jobs.Job{
		ID:               "job-launch-missing-nonce",
		OwnerID:          1,
		RepoID:           2,
		ActorID:          3,
		AssignmentID:     "assignment-launch-missing-nonce",
		Status:           jobs.JobStatusQueued,
		UseAsyncSessions: true,
	}
	_, err := jobStore.CreateJob(context.Background(), job)
	require.NoError(t, err)

	ctx := requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
		ID:           job.ID,
		OwnerID:      job.OwnerID,
		RepoID:       job.RepoID,
		AssignmentID: job.AssignmentID,
	}))

	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentSandboxPersistCallbackFieldsBeforeCLIExec: true,
	})
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, false, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", ffClient)
	require.NoError(t, err)
	je := NewTestJobExecutor(obsv, ffClient, jobStore, &github.NoopClientFactory{}, ghTwirp, capiClient, nil, nil)
	je.launchers = launchMetricBuilder{launcher: missingNonceBeforeAgentStartLauncher{t: t}}

	launchedJob, err := je.launchAgent(ctx, &launcher.LaunchAgentOpts{
		JobID:             job.ID,
		GitHubRepoID:      job.RepoID,
		GitHubRepoOwnerID: job.OwnerID,
	}, job)
	require.NoError(t, err)
	require.Nil(t, launchedJob)

	persistedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	require.NoError(t, err)
	require.Equal(t, jobs.JobStatusFailed, persistedJob.Status)
	require.Empty(t, persistedJob.ComputeID)
	require.Zero(t, persistedJob.LaunchedAt)
	require.Equal(t, stats.Tags{
		"launcher_type": string(launcher.TypeSandbox),
		"result":        "failure",
		"strategy":      "pre_agent_update",
	}, persistenceMetricTags)
}

func createMockGithubTwirpClientWithQuota(t *testing.T, remainingQuota, totalQuota int32, overagePermitted, mockBilling bool, err error) *githubtwirp.NoopClient {
	mockBillingClient := (*billingMocks.MockClientInterface)(nil)
	if mockBilling {
		mockBillingClient = billingMocks.NewMockClientInterface(t)
		mockBillingClient.On("CanProceedWithUsage", mock.Anything, mock.MatchedBy(func(req *billingProto.CanProceedWithUsageRequest) bool {
			return req.UsageKey != nil &&
				req.UsageKey.Sku == "coding_agent_premium_request" &&
				req.UsageKey.Product == "copilot" &&
				req.UsageKey.Quantity == 1 &&
				req.UsageKey.EntityDetail != nil &&
				req.UsageKey.EntityDetail.CustomerId == "123" &&
				req.TrustTier == 0
		})).Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: overagePermitted,
		}, nil)
	}

	return &githubtwirp.NoopClient{
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, err
			},
		},
		NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
			MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
				return &copilotLimitersTwirp.GetQuotaRemainingResponse{
					QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
						{
							QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
							Remaining:        remainingQuota,
							Entitlement:      totalQuota,
							OveragePermitted: overagePermitted,
						},
					},
				}, nil
			},
		},
		NoopSweagentdAPI:  &githubtwirp.NoopSweagentdAPI{},
		NoopBillingClient: mockBillingClient,
	}
}

func TestProcessJob_CustomAgentConfigError(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	assignment := &jobs.Assignment{
		ID:      "assign-1",
		OwnerID: 1,
		RepoID:  2,
	}

	configError := "invalid MCP server configuration: missing required field 'command'"
	job := &jobs.Job{
		ID:           "job-1",
		OwnerID:      1,
		RepoID:       2,
		ActorID:      3,
		ActorLogin:   "actor",
		Status:       jobs.JobStatusQueued,
		AssignmentID: "assign-1",
		CustomAgent: jobCustomAgent.DBRecord{
			Name:        "invalid-agent",
			Scope:       agentconfig.ScopeJob,
			ConfigError: configError,
		},
	}

	agentJob := &aqueductJobs.AgentJob{
		RepositoryId: job.RepoID,
		OwnerId:      job.OwnerID,
		AssignmentId: job.AssignmentID,
		JobId:        job.ID,
	}

	jobStore.CreateAssignment(ctx, assignment)
	_, err = jobStore.CreateJob(ctx, job)
	require.NoError(t, err)

	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	err = je.ProcessJob(ctx, agentJob)
	require.NoError(t, err)

	// Verify that the job was cancelled due to the config error
	updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	require.NoError(t, err)
	assert.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)

	// Verify that no agent was launched
	require.Len(t, je.LaunchAgentCalls(), 0)

	// Verify that the job can still be processed normally if there's no config error
	t.Run("processes job normally when no config error", func(t *testing.T) {
		jobWithoutError := &jobs.Job{
			ID:           "job-2",
			OwnerID:      1,
			RepoID:       2,
			ActorID:      3,
			ActorLogin:   "actor",
			Status:       jobs.JobStatusQueued,
			AssignmentID: "assign-1",
			CustomAgent: jobCustomAgent.DBRecord{
				Name:        "valid-agent",
				Scope:       agentconfig.ScopeJob,
				ConfigError: "", // No error
			},
			PullRequestID:     123,
			PullRequestNumber: 123,
			EventType:         jobs.EventTypePullRequestReview,
			EventIdentifiers:  []string{"123"},
			Action:            jobs.AgentActionFixPRComment,
		}

		agentJobNoError := &aqueductJobs.AgentJob{
			RepositoryId:      jobWithoutError.RepoID,
			OwnerId:           jobWithoutError.OwnerID,
			AssignmentId:      jobWithoutError.AssignmentID,
			JobId:             jobWithoutError.ID,
			PullRequestId:     123,
			PullRequestNumber: 123,
		}

		// Setup mock for open PR
		ghFactory.MockPullRequest = &gg.PullRequest{
			State:     gg.Ptr("open"),
			Number:    gg.Ptr(123),
			Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
		}

		_, err = jobStore.CreateJob(ctx, jobWithoutError)
		require.NoError(t, err)

		err = je.ProcessJob(ctx, agentJobNoError)
		require.NoError(t, err)

		// Verify that the agent was launched for the job without config error
		require.Len(t, je.LaunchAgentCalls(), 1)
	})
}

func TestExecuteJob(t *testing.T) {
	t.Run("insufficient quota stops execution but doesn't return error", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghFactory := &github.NoopClientFactory{}
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
					ActorId:    3,
				},
			},
			TrustTier: 0,
		}).Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: false,
		}, nil)
		ghTwirp := &githubtwirp.NoopClient{
			NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
				MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{AnalyticsTrackingId: "test-tracking-id"},
					}, nil
				},
			},
			NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
				MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
					return &copilotLimitersTwirp.GetQuotaRemainingResponse{
						QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
							{
								QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
								Remaining:        0,
								Entitlement:      0,
								OveragePermitted: false,
							},
						},
					}, nil
				},
			},
			NoopBillingClient: mockBillingClient,
		}
		capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		job := &jobs.Job{
			ID:                "test-job",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			ActorLogin:        "test-actor",
			PullRequestNumber: 123,
		}

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		app := agenticapptest.NewTestCopilot(t)
		err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
		require.NoError(t, err)
	})

	t.Run("insufficient quota finalizes job", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(nil)
		ghFactory := &github.NoopClientFactory{}
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
					ActorId:    3,
				},
			},
			TrustTier: 0,
		}).Return(&billingProto.CanProceedWithUsageResponse{
			CanProceed: false,
		}, nil)
		ghTwirp := &githubtwirp.NoopClient{
			NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
				MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{AnalyticsTrackingId: "test-tracking-id"},
					}, nil
				},
			},
			NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
				MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
					return &copilotLimitersTwirp.GetQuotaRemainingResponse{
						QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
							{
								QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
								Remaining:        0,
								Entitlement:      0,
								OveragePermitted: false,
							},
						},
					}, nil
				},
			},
			NoopBillingClient: mockBillingClient,
		}
		capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)

		assignment := &jobs.Assignment{
			ID:      "test-assignment",
			OwnerID: 1,
			RepoID:  2,
		}
		jobStore.CreateAssignment(ctx, assignment)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		job := &jobs.Job{
			ID:                "test-job",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			ActorLogin:        "test-actor",
			PullRequestNumber: 123,
			Status:            jobs.JobStatusQueued,
			AssignmentID:      "test-assignment",
		}
		_, err = jobStore.CreateJob(ctx, job)
		require.NoError(t, err)

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		app := agenticapptest.NewTestCopilot(t)
		err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
		require.NoError(t, err)

		// Verify the job was finalized as failed
		updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		assert.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})

	t.Run("customer selection required error stops execution but doesn't return error", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSelectCustomerError: true, // Enable feature flag to stop execution on customer selection error
		})
		ghFactory := &github.NoopClientFactory{}
		ghTwirp := &githubtwirp.NoopClient{
			NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
				MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{AnalyticsTrackingId: "test-tracking-id"},
					}, nil
				},
			},
			NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
				MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
					return &copilotLimitersTwirp.GetQuotaRemainingResponse{
						QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
							{
								QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
								Remaining:        0,
								Entitlement:      10,
								OveragePermitted: false,
							},
						},
					}, nil
				},
				MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
					// Return empty CustomerIds array with MultiSKU to simulate customerId = -1
					return &copilotLimitersTwirp.GetConsumptiveUserResponse{
						CustomerIds: []int64{},
						AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
					}, nil
				},
			},
		}
		capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		job := &jobs.Job{
			ID:                "test-job",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			ActorLogin:        "test-actor",
			PullRequestNumber: 123,
		}

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		app := agenticapptest.NewTestCopilot(t)
		err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
		require.NoError(t, err)
	})

	t.Run("customer selection required finalizes job", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSelectCustomerError: true,
		})
		ghFactory := &github.NoopClientFactory{}
		ghTwirp := &githubtwirp.NoopClient{
			NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
				MockGetCopilotUser: func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{AnalyticsTrackingId: "test-tracking-id"},
					}, nil
				},
			},
			NoopLimiterAPI: &githubtwirp.NoopLimiterAPI{
				MockGetQuotaRemaining: func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
					return &copilotLimitersTwirp.GetQuotaRemainingResponse{
						QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
							{
								QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
								Remaining:        0,
								Entitlement:      10,
								OveragePermitted: false,
							},
						},
					}, nil
				},
				MockGetConsumptiveUser: func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
					// Return empty CustomerIds array with MultiSKU to simulate customerId = -1
					return &copilotLimitersTwirp.GetConsumptiveUserResponse{
						CustomerIds: []int64{},
						AccessType:  copilotLimitersTwirp.AccessType_ACCESS_TYPE_COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA,
					}, nil
				},
			},
		}
		capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)

		assignment := &jobs.Assignment{
			ID:      "test-assignment",
			OwnerID: 1,
			RepoID:  2,
		}
		jobStore.CreateAssignment(ctx, assignment)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		job := &jobs.Job{
			ID:                "test-job",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			ActorLogin:        "test-actor",
			PullRequestNumber: 123,
			Status:            jobs.JobStatusQueued,
			AssignmentID:      "test-assignment",
		}
		_, err = jobStore.CreateJob(ctx, job)
		require.NoError(t, err)

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		app := agenticapptest.NewTestCopilot(t)
		err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
		require.NoError(t, err)

		// Verify the job was finalized as failed
		updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		assert.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})

	t.Run("skips quota check when agent is quota exempt", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIntegrationQuotaExempt: true,
		})
		ghFactory := &github.NoopClientFactory{}
		// Use a ghTwirp with NO quota mocks — if quota is checked, it panics
		// on nil billing client. We set up enough mocks for the code past
		// the quota check (launchOptsForJob) so that executeJob succeeds.
		ghTwirp := createMockGithubTwirpClientWithQuota(t, 0, 0, false, false, nil)
		capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", ffClient)
		require.NoError(t, err)

		thirdPartyApp := agenticapptest.NewTestApp(99999).WithQuotaExempt()
		appProvider := agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, thirdPartyApp)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		// Override appProvider to include our third-party app
		je.appProvider = appProvider

		job := &jobs.Job{
			ID:               "test-job",
			OwnerID:          1,
			RepoID:           2,
			ActorID:          3,
			ActorLogin:       "test-actor",
			AgentID:          99999,
			ProblemStatement: jobs.ProblemStatement{Content: "test problem"},
			RunOptions:       jobs.RunOptions{},
		}
		_, err = jobStore.CreateJob(ctx, job)
		require.NoError(t, err)

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{Login: &repoOwner},
			Name:  &repoName,
		}

		// executeJob should skip quota check and proceed. It will call
		// launchOptsForJob and launchAgent which all succeed with noop mocks.
		err = je.executeJob(ctx, &github.NoopClient{}, thirdPartyApp, job, repo, "nonce")
		require.NoError(t, err)
	})
}

func TestCustomAgentFromJob(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	testAgentConfig := `---
name: Test Agent
description: A test custom agent
tools:
  - "*"
permissions:
  contents: write
  issues: read
  pull-requests: write
---

Test prompt for custom agent`

	tests := []struct {
		name               string
		customAgentName    string
		customAgentVersion string
		agentConfig        string
		expectCopilot      bool
		expectError        bool
	}{
		{
			name:               "returns Copilot agent when custom agent name is empty",
			customAgentName:    "",
			customAgentVersion: "",
			expectCopilot:      true,
			expectError:        false,
		},
		{
			name:               "returns agent from service",
			customAgentName:    "test-agent",
			customAgentVersion: "", // Empty version means latest
			agentConfig:        testAgentConfig,
			expectCopilot:      false,
			expectError:        false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(map[string]bool{})

			job := &jobs.Job{
				ID:         "test-job",
				OwnerID:    789,
				RepoID:     456,
				ActorID:    123,
				ActorLogin: "test-actor",
				CustomAgent: jobCustomAgent.DBRecord{
					Name:        tt.customAgentName,
					Version:     tt.customAgentVersion,
					RepoOwnerID: 789,
					RepoID:      456,
					Tools:       []string{"*"},
				},
			}

			var customAgentSvc *customagent.Service
			if tt.customAgentName != "" {
				// Create spokes with the test agent using WithRepoBlob for repo-specific blobs
				spokesOptions := []spokestest.ClientOption{
					spokestest.WithRepoBlob(
						uint64(job.RepoID),
						filepath.Join(customagent.Directory, tt.customAgentName+customagent.Extension),
						[]byte(tt.agentConfig),
					),
				}
				spokes := spokestest.NewClient(t, spokesOptions...)

				// Mock twirp client to return repository information
				ghTwirp := githubtwirp.NewNoopClient()
				ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
					return &repositoriesTwirp.FindRepositoriesByNameResponse{
						Repositories: []*repositoriesTwirp.RepositoryListItem{
							{
								Id:         job.RepoID,
								Name:       "test-repo",
								OwnerId:    job.OwnerID,
								OwnerLogin: "test-owner",
							},
						},
					}, nil
				}
				ghTwirp.NoopSweagentdAPI.MockAuthorizeCustomAgentRepoForUser = func(ctx context.Context, req *sweagentdv1.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdv1.AuthorizeCustomAgentRepoForUserResponse, error) {
					return &sweagentdv1.AuthorizeCustomAgentRepoForUserResponse{
						CanAccess: true,
					}, nil
				}
				ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
					return nil, twirp.NotFoundError("enterprise agents not configured for this repository")
				}

				customAgentSvc = customagent.NewService(obsv, spokes, ghTwirp, ffClient)
			}

			executor := &AgentJobExecutor{
				obsv:           obsv,
				ffClient:       ffClient,
				customAgentSvc: customAgentSvc,
			}

			repoOwner := "test-owner"
			repoName := "test-repo"
			repo := &gg.Repository{
				Owner: &gg.User{
					Login: &repoOwner,
				},
				Name: &repoName,
			}

			app := agenticapptest.NewTestCopilot(t)
			agent, err := executor.customAgentFromJob(ctx, job, repo, app)

			if tt.expectError {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				switch {
				case tt.expectCopilot:
					// For empty custom agent name, we expect Copilot agent
					_, isCopilot := agent.(*customagent.CopilotAgent)
					assert.True(t, isCopilot)
					assert.Equal(t, int64(456), agent.RepoID())
					assert.Equal(t, int64(789), agent.RepoOwnerID())
				default:
					// Agent is fetched from the service
					assert.Equal(t, tt.customAgentName, agent.Name())
					assert.Equal(t, "Test Agent", agent.DisplayName())
					assert.Equal(t, "A test custom agent", agent.Description())
					assert.Equal(t, "Test prompt for custom agent", agent.Prompt())
				}
			}
		})
	}
}

func TestCustomAgentFromJob_WithAgentSource(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	mainAgentConfig := `---
name: Main Agent
description: Agent from agentic app source
tools:
  - "*"
---

Main agent prompt`

	sourceRepoID := int64(999)
	sourceSHA := "abc123"

	t.Run("resolves plugin agent when copilot agent and app has AgentSource", func(t *testing.T) {
		spokes := spokestest.NewClient(t,
			spokestest.WithRepoBlob(uint64(sourceRepoID), "agents/main.md", []byte(mainAgentConfig)),
			spokestest.WithRepoBlob(uint64(sourceRepoID), "plugin.json", []byte(`{"name":"test-plugin"}`)),
			spokestest.WithCommitSHAAndBlob("main.md", sourceSHA, []byte(mainAgentConfig)),
		)

		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{
						Id:         sourceRepoID,
						Name:       "agent-repo",
						OwnerId:    100,
						OwnerLogin: "agent-owner",
					},
				},
			}, nil
		}

		pluginSvc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
		app := agenticapptest.NewTestApp(0).WithAgentSource(&sweagentd.AgentSource{
			URL: "https://github.com/agent-owner/agent-repo",
			SHA: sourceSHA,
		})

		job := &jobs.Job{
			ID:      "test-job",
			OwnerID: 789,
			RepoID:  456,
			CustomAgent: jobCustomAgent.DBRecord{
				Name:        "",
				RepoOwnerID: 789,
				RepoID:      456,
			},
		}

		customAgentSvc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		executor := &AgentJobExecutor{
			obsv:           obsv,
			ffClient:       ffClient,
			pluginSvc:      pluginSvc,
			customAgentSvc: customAgentSvc,
		}

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{Login: &repoOwner},
			Name:  &repoName,
		}

		agent, err := executor.customAgentFromJob(ctx, job, repo, app)
		require.NoError(t, err)

		_, isCopilot := agent.(*customagent.CopilotAgent)
		assert.False(t, isCopilot, "should not return a CopilotAgent when app has AgentSource")
		assert.Equal(t, "main", agent.Name())
		assert.Equal(t, "Main Agent", agent.DisplayName())
		assert.Equal(t, "Agent from agentic app source", agent.Description())
		assert.Equal(t, "Main agent prompt", agent.Prompt())
	})

	t.Run("returns copilot agent when app has no AgentSource", func(t *testing.T) {
		app := agenticapptest.NewTestCopilot(t)

		job := &jobs.Job{
			ID:      "test-job",
			OwnerID: 789,
			RepoID:  456,
			CustomAgent: jobCustomAgent.DBRecord{
				Name:        "",
				RepoOwnerID: 789,
				RepoID:      456,
			},
		}

		customAgentSvc := customagent.NewService(obsv, spokestest.NewClient(t), githubtwirp.NewNoopClient(), ffClient)
		executor := &AgentJobExecutor{
			obsv:           obsv,
			ffClient:       ffClient,
			customAgentSvc: customAgentSvc,
		}

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{Login: &repoOwner},
			Name:  &repoName,
		}

		agent, err := executor.customAgentFromJob(ctx, job, repo, app)
		require.NoError(t, err)

		_, isCopilot := agent.(*customagent.CopilotAgent)
		assert.True(t, isCopilot, "should return CopilotAgent when app has no AgentSource")
	})

	t.Run("falls back to copilot when plugin service is nil", func(t *testing.T) {
		app := agenticapptest.NewTestApp(0).WithAgentSource(&sweagentd.AgentSource{
			URL: "https://github.com/agent-owner/agent-repo",
			SHA: sourceSHA,
		})

		job := &jobs.Job{
			ID:      "test-job",
			OwnerID: 789,
			RepoID:  456,
			CustomAgent: jobCustomAgent.DBRecord{
				Name:        "",
				RepoOwnerID: 789,
				RepoID:      456,
			},
		}

		customAgentSvc := customagent.NewService(obsv, spokestest.NewClient(t), githubtwirp.NewNoopClient(), ffClient)
		executor := &AgentJobExecutor{
			obsv:           obsv,
			ffClient:       ffClient,
			pluginSvc:      nil,
			customAgentSvc: customAgentSvc,
		}

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{Login: &repoOwner},
			Name:  &repoName,
		}

		agent, err := executor.customAgentFromJob(ctx, job, repo, app)
		require.NoError(t, err)

		_, isCopilot := agent.(*customagent.CopilotAgent)
		assert.True(t, isCopilot, "should fall back to CopilotAgent when plugin service is nil")
	})
}

func TestCustomAgentFromJob_PluginErrors(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	jobStore := memory.NewStore()
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := githubtwirp.NewNoopClient()
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	repoOwner := "test-owner"
	repoName := "test-repo"
	repo := &gg.Repository{
		Owner: &gg.User{Login: &repoOwner},
		Name:  &repoName,
	}

	job := &jobs.Job{
		ID:      "test-job",
		OwnerID: 789,
		RepoID:  456,
		Status:  jobs.JobStatusQueued,
		CustomAgent: jobCustomAgent.DBRecord{
			Name:        "",
			RepoOwnerID: 789,
			RepoID:      456,
		},
	}

	assignment := &jobs.Assignment{
		ID:      "assign-1",
		OwnerID: 789,
		RepoID:  456,
	}

	_, err = jobStore.CreateAssignment(ctx, assignment)
	require.NoError(t, err)
	_, err = jobStore.CreateJob(ctx, job)
	require.NoError(t, err)

	tests := []struct {
		name            string
		app             func(t *testing.T) sweagentd.AgenticApp
		mockRepoLookup  func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error)
		spokesOpts      []spokestest.ClientOption
		wantUserConfig  bool
		wantErrContains string
	}{
		{
			name: "returns ErrAgenticAppUserConfigError when GetCustomAgentForApp fails with user config error",
			app: func(t *testing.T) sweagentd.AgenticApp {
				return agenticapptest.NewTestApp(0).WithAgentSource(&sweagentd.AgentSource{
					URL: "https://github.com/agent-owner/agent-repo",
					SHA: "abc123",
				})
			},
			// Repo resolves but plugin.json is invalid JSON → ErrInvalidPluginConfig (user error)
			mockRepoLookup: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         999,
							Name:       "agent-repo",
							OwnerId:    100,
							OwnerLogin: "agent-owner",
						},
					},
				}, nil
			},
			spokesOpts: []spokestest.ClientOption{
				spokestest.WithBlob(".plugin/plugin.json", []byte(`{invalid json`)),
			},
			wantUserConfig: true,
		},
		{
			name: "returns retryable error when repo cannot be found",
			app: func(t *testing.T) sweagentd.AgenticApp {
				return agenticapptest.NewTestApp(0).WithAgentSource(&sweagentd.AgentSource{
					URL: "https://github.com/agent-owner/agent-repo",
					SHA: "abc123",
				})
			},
			// FindRepositoriesByName returns empty → ErrFailedToGetPlugin (not a user error)
			mockRepoLookup: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{},
				}, nil
			},
			wantUserConfig: false,
		},
		{
			name: "returns retryable error when agent config blob is missing",
			app: func(t *testing.T) sweagentd.AgenticApp {
				return agenticapptest.NewTestApp(0).WithAgentSource(&sweagentd.AgentSource{
					URL: "https://github.com/agent-owner/agent-repo",
					SHA: "abc123",
				})
			},
			// Repo resolves and plugin.json exists with an agent, but agent config blob
			// is missing → ErrFailedToGetPluginCustomAgent (not a user error) → retryable
			mockRepoLookup: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         999,
							Name:       "agent-repo",
							OwnerId:    100,
							OwnerLogin: "agent-owner",
						},
					},
				}, nil
			},
			spokesOpts: []spokestest.ClientOption{
				spokestest.WithBlob(".plugin/plugin.json", []byte(`{"name":"test-plugin"}`)),
				spokestest.WithBlob("agents/main.agent.md", []byte("placeholder")),
			},
			wantUserConfig: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			spokes := spokestest.NewClient(t, tc.spokesOpts...)
			pluginGhTwirp := githubtwirp.NewNoopClient()

			if tc.mockRepoLookup != nil {
				pluginGhTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = tc.mockRepoLookup
			}

			pluginSvc := plugins.NewService(obsv, spokes, pluginGhTwirp, "https://github.com")

			je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
			je.pluginSvc = pluginSvc

			app := tc.app(t)
			_, err := je.customAgentFromJob(ctx, job, repo, app)
			require.Error(t, err)

			if tc.wantUserConfig {
				require.ErrorIs(t, err, ErrAgenticAppUserConfigError)
			} else {
				require.NotErrorIs(t, err, ErrAgenticAppUserConfigError)
			}

			if tc.wantErrContains != "" {
				assert.Contains(t, err.Error(), tc.wantErrContains)
			}
		})
	}
}

func TestExecuteJob_UserConfigError_FinalizesJob(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	ghFactory.MockPullRequest = &gg.PullRequest{
		State:     gg.Ptr("open"),
		Number:    gg.Ptr(123),
		Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
	}

	assignment := &jobs.Assignment{
		ID:      "assign-1",
		OwnerID: 1,
		RepoID:  2,
	}

	job := &jobs.Job{
		ID:                "job-1",
		OwnerID:           1,
		RepoID:            2,
		ActorID:           3,
		ActorLogin:        "actor",
		Status:            jobs.JobStatusQueued,
		AssignmentID:      "assign-1",
		PullRequestID:     123,
		PullRequestNumber: 123,
		EventType:         jobs.EventTypePullRequestReview,
		EventIdentifiers:  []string{"123"},
		Action:            jobs.AgentActionFixPRComment,
		CustomAgent: jobCustomAgent.DBRecord{
			Name:        "",
			RepoOwnerID: 1,
			RepoID:      2,
		},
	}

	// Set up spokes with invalid plugin.json to trigger ErrInvalidPluginConfig (user error)
	spokes := spokestest.NewClient(t,
		spokestest.WithBlob(".plugin/plugin.json", []byte(`{invalid json`)),
	)
	pluginGhTwirp := githubtwirp.NewNoopClient()
	// Return a valid repo so we get past resolution to the invalid plugin.json
	pluginGhTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{
					Id:         999,
					Name:       "test-plugin-repo",
					OwnerId:    100,
					OwnerLogin: "test-owner",
				},
			},
		}, nil
	}

	pluginSvc := plugins.NewService(obsv, spokes, pluginGhTwirp, "https://github.com")

	_, err = jobStore.CreateAssignment(ctx, assignment)
	require.NoError(t, err)
	_, err = jobStore.CreateJob(ctx, job)
	require.NoError(t, err)

	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
	// Override pluginSvc to trigger ErrInvalidPluginConfig (user error) in customAgentFromJob
	je.pluginSvc = pluginSvc

	// Use a third-party app WITH AgentSource so customAgentFromJob enters the
	// plugin resolution path, where invalid plugin.json triggers ErrAgenticAppUserConfigError.
	app := agenticapptest.NewTestApp(0).WithAgentSource(&sweagentd.AgentSource{
		URL: "https://github.com/test-owner/test-plugin-repo",
		SHA: "abc123",
	})

	repoOwner := "test-owner"
	repoName := "test-repo"
	repo := &gg.Repository{
		Owner: &gg.User{Login: &repoOwner},
		Name:  &repoName,
	}

	// executeJob should return nil because the job is finalized as cancelled
	err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
	require.NoError(t, err, "executeJob should not return error when job is finalized due to user config error")

	// Verify no agent was launched
	require.Len(t, je.LaunchAgentCalls(), 0)

	// Verify the job was cancelled
	updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	require.NoError(t, err)
	assert.Equal(t, jobs.JobStatusCancelled, updatedJob.Status, "Job should be cancelled when plugin/agent details can't be retrieved")
}

func TestAgentJobExecutor_LaunchAgent_FailureDoesNotRetry(t *testing.T) {
	// This test verifies that when LaunchAgent fails but the job is successfully
	// finalized as failed, we return nil (no error) to prevent Aqueduct from retrying
	// the job. This is important because launch failures (e.g., invalid workflow format)
	// are not retriable - retrying would just waste resources.
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	ghFactory.MockPullRequest = &gg.PullRequest{
		State:     gg.Ptr("open"),
		Number:    gg.Ptr(123),
		Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
	}

	assignment := &jobs.Assignment{
		ID:      "assign-1",
		OwnerID: 1,
		RepoID:  2,
	}

	job := &jobs.Job{
		ID:                "job-1",
		OwnerID:           1,
		RepoID:            2,
		ActorID:           3,
		ActorLogin:        "actor",
		Status:            jobs.JobStatusQueued,
		AssignmentID:      "assign-1",
		PullRequestID:     123,
		PullRequestNumber: 123,
		EventType:         jobs.EventTypePullRequestReview,
		EventIdentifiers:  []string{"123"},
		Action:            jobs.AgentActionFixPRComment,
	}

	agentJob := &aqueductJobs.AgentJob{
		RepositoryId:      job.RepoID,
		OwnerId:           job.OwnerID,
		AssignmentId:      job.AssignmentID,
		JobId:             job.ID,
		PullRequestId:     123,
		PullRequestNumber: 123,
	}

	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	// Set up the launcher to return an error (simulating a workflow validation failure)
	je.Launcher.LaunchAgentError = errors.New("Invalid workflow format")

	_, err = jobStore.CreateAssignment(ctx, assignment)
	require.NoError(t, err)
	_, err = jobStore.CreateJob(ctx, job)
	require.NoError(t, err)

	// ProcessJob should return nil (not an error) even though launch failed,
	// because the job was successfully finalized as failed
	err = je.ProcessJob(ctx, agentJob)
	require.NoError(t, err, "ProcessJob should not return error when job is finalized as failed")

	// Verify that LaunchAgent was called
	require.Len(t, je.LaunchAgentCalls(), 1)

	// Verify that the job was finalized as failed
	updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	require.NoError(t, err)
	require.Equal(t, jobs.JobStatusFailed, updatedJob.Status, "Job should be marked as failed")
}

func TestAgentJobExecutor_LaunchAgent_RetriableErrorAllowsRetry(t *testing.T) {
	// This test verifies that when LaunchAgent fails with a retriable error
	// (e.g., rate limit), we return the error to allow Aqueduct to retry the job.
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	ghFactory.MockPullRequest = &gg.PullRequest{
		State:     gg.Ptr("open"),
		Number:    gg.Ptr(123),
		Assignees: []*gg.User{{Login: gg.Ptr("Copilot")}},
	}

	assignment := &jobs.Assignment{
		ID:      "assign-1",
		OwnerID: 1,
		RepoID:  2,
	}

	job := &jobs.Job{
		ID:                "job-1",
		OwnerID:           1,
		RepoID:            2,
		ActorID:           3,
		ActorLogin:        "actor",
		Status:            jobs.JobStatusQueued,
		AssignmentID:      "assign-1",
		PullRequestID:     123,
		PullRequestNumber: 123,
		EventType:         jobs.EventTypePullRequestReview,
		EventIdentifiers:  []string{"123"},
		Action:            jobs.AgentActionFixPRComment,
	}

	agentJob := &aqueductJobs.AgentJob{
		RepositoryId:      job.RepoID,
		OwnerId:           job.OwnerID,
		AssignmentId:      job.AssignmentID,
		JobId:             job.ID,
		PullRequestId:     123,
		PullRequestNumber: 123,
	}

	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	// Set up the launcher to return a retriable error (e.g., rate limit or server error)
	je.Launcher.LaunchAgentError = launcher.RetriableLaunchError(errors.New("rate limit exceeded"))

	_, err = jobStore.CreateAssignment(ctx, assignment)
	require.NoError(t, err)
	_, err = jobStore.CreateJob(ctx, job)
	require.NoError(t, err)

	// ProcessJob should return an error to allow Aqueduct to retry
	err = je.ProcessJob(ctx, agentJob)
	require.Error(t, err, "ProcessJob should return error for retriable launch failures")
	assert.Contains(t, err.Error(), "retriable", "Error message should indicate retriability")

	// Verify that LaunchAgent was called
	require.Len(t, je.LaunchAgentCalls(), 1)

	// Verify that the job was NOT finalized as failed (it should still be queued for retry)
	updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
	require.NoError(t, err)
	require.Equal(t, jobs.JobStatusQueued, updatedJob.Status, "Job should still be queued to allow retry")
}

func TestExecuteJob_BranchlessJobSetsPushFalseAndDefaultBranch(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	assignment := &jobs.Assignment{
		ID:      "branchless-assign",
		OwnerID: 1,
		RepoID:  2,
	}

	jobStore := memory.NewStore()
	jobStore.CreateAssignment(ctx, assignment)
	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	// Create a branchless job (no BranchName, no features requiring a branch)
	job := &jobs.Job{
		ID:           "branchless-job",
		OwnerID:      1,
		RepoID:       2,
		ActorID:      3,
		ActorLogin:   "actor",
		Status:       jobs.JobStatusQueued,
		AssignmentID: "branchless-assign",
		BranchName:   "", // No branch
		Action:       jobs.AgentActionTask,
		Features:     jobs.EnvironmentFeatures{}, // No features
	}
	_, err = jobStore.CreateJob(ctx, job)
	require.NoError(t, err)

	repoOwner := "test-owner"
	repoName := "test-repo"
	defaultBranch := "main"
	repo := &gg.Repository{
		Owner:         &gg.User{Login: &repoOwner},
		Name:          &repoName,
		DefaultBranch: &defaultBranch,
	}

	app := agenticapptest.NewTestCopilot(t)
	err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
	require.NoError(t, err)

	require.Len(t, je.LaunchAgentCalls(), 1)
	launchOpts := je.LaunchAgentCalls()[0]

	assert.False(t, launchOpts.Push, "branchless jobs should have Push=false")
	assert.Equal(t, "main", launchOpts.BranchName, "branchless jobs should have BranchName resolved to default branch")
}

func TestExecuteJob_JobWithBranchSetsPushTrue(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	assignment := &jobs.Assignment{
		ID:      "branch-assign",
		OwnerID: 1,
		RepoID:  2,
	}

	jobStore := memory.NewStore()
	jobStore.CreateAssignment(ctx, assignment)
	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	// Create a job WITH a branch
	job := &jobs.Job{
		ID:           "branch-job",
		OwnerID:      1,
		RepoID:       2,
		ActorID:      3,
		ActorLogin:   "actor",
		Status:       jobs.JobStatusQueued,
		AssignmentID: "branch-assign",
		BranchName:   "copilot/fix-123",
		Action:       jobs.AgentActionFix,
	}
	_, err = jobStore.CreateJob(ctx, job)
	require.NoError(t, err)

	repoOwner := "test-owner"
	repoName := "test-repo"
	defaultBranch := "main"
	repo := &gg.Repository{
		Owner:         &gg.User{Login: &repoOwner},
		Name:          &repoName,
		DefaultBranch: &defaultBranch,
	}

	app := agenticapptest.NewTestCopilot(t)
	err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
	require.NoError(t, err)

	require.Len(t, je.LaunchAgentCalls(), 1)
	launchOpts := je.LaunchAgentCalls()[0]

	assert.True(t, launchOpts.Push, "jobs with a branch should have Push=true")
	assert.Equal(t, "copilot/fix-123", launchOpts.BranchName, "jobs with a branch should have BranchName set")
}

func TestExecuteJob_RequireSignedCommitsPassthrough(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	assignment := &jobs.Assignment{
		ID:      "sign-assign",
		OwnerID: 1,
		RepoID:  2,
	}

	jobStore := memory.NewStore()
	jobStore.CreateAssignment(ctx, assignment)
	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	repoOwner := "test-owner"
	repoName := "test-repo"
	defaultBranch := "main"
	repo := &gg.Repository{
		Owner:         &gg.User{Login: &repoOwner},
		Name:          &repoName,
		DefaultBranch: &defaultBranch,
	}

	app := agenticapptest.NewTestCopilot(t)

	t.Run("SignCommits is true when job requires signed commits", func(t *testing.T) {
		job := &jobs.Job{
			ID:                   "sign-job-true",
			OwnerID:              1,
			RepoID:               2,
			ActorID:              3,
			ActorLogin:           "actor",
			Status:               jobs.JobStatusQueued,
			AssignmentID:         "sign-assign",
			BranchName:           "copilot/fix-sign",
			Action:               jobs.AgentActionFix,
			RequireSignedCommits: true,
		}
		_, err = jobStore.CreateJob(ctx, job)
		require.NoError(t, err)

		err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
		require.NoError(t, err)

		calls := je.LaunchAgentCalls()
		require.NotEmpty(t, calls)
		assert.True(t, calls[len(calls)-1].SignCommits, "SignCommits should be true when job.RequireSignedCommits is true")
	})

	t.Run("SignCommits is false when job does not require signed commits", func(t *testing.T) {
		job := &jobs.Job{
			ID:                   "sign-job-false",
			OwnerID:              1,
			RepoID:               2,
			ActorID:              3,
			ActorLogin:           "actor",
			Status:               jobs.JobStatusQueued,
			AssignmentID:         "sign-assign",
			BranchName:           "copilot/fix-nosign",
			Action:               jobs.AgentActionFix,
			RequireSignedCommits: false,
		}
		_, err = jobStore.CreateJob(ctx, job)
		require.NoError(t, err)

		err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
		require.NoError(t, err)

		calls := je.LaunchAgentCalls()
		require.NotEmpty(t, calls)
		assert.False(t, calls[len(calls)-1].SignCommits, "SignCommits should be false when job.RequireSignedCommits is false")
	})
}

// TestExecuteJob_CanWriteWorkflowsPassthrough verifies that
// Job.CanWriteWorkflows is forwarded into LaunchAgentOpts unchanged for
// all three tri-state values. Because the executor reads the field from the
// persisted job (post-Cosmos-roundtrip), this also covers the retry/relaunch
// path where we must honor the original credential's capability rather than
// re-evaluating it.
func TestExecuteJob_CanWriteWorkflowsPassthrough(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(t, 1, 1, true, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	assignment := &jobs.Assignment{
		ID:      "cmwf-assign",
		OwnerID: 1,
		RepoID:  2,
	}

	jobStore := memory.NewStore()
	jobStore.CreateAssignment(ctx, assignment)
	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	repoOwner := "test-owner"
	repoName := "test-repo"
	defaultBranch := "main"
	repo := &gg.Repository{
		Owner:         &gg.User{Login: &repoOwner},
		Name:          &repoName,
		DefaultBranch: &defaultBranch,
	}

	app := agenticapptest.NewTestCopilot(t)

	run := func(t *testing.T, jobID string, value *bool) *bool {
		t.Helper()
		job := &jobs.Job{
			ID:                jobID,
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			ActorLogin:        "actor",
			Status:            jobs.JobStatusQueued,
			AssignmentID:      "cmwf-assign",
			BranchName:        "copilot/fix-" + jobID,
			Action:            jobs.AgentActionFix,
			CanWriteWorkflows: value,
		}
		_, err = jobStore.CreateJob(ctx, job)
		require.NoError(t, err)

		err = je.executeJob(ctx, &github.NoopClient{}, app, job, repo, "nonce")
		require.NoError(t, err)

		calls := je.LaunchAgentCalls()
		require.NotEmpty(t, calls)
		return calls[len(calls)-1].CanWriteWorkflows
	}

	t.Run("nil round-trips as nil (no check was performed)", func(t *testing.T) {
		got := run(t, "cmwf-nil", nil)
		assert.Nil(t, got, "nil must be preserved so launcher omits the new dynamic-workflow input")
	})

	t.Run("&true round-trips as &true", func(t *testing.T) {
		truth := true
		got := run(t, "cmwf-true", &truth)
		require.NotNil(t, got)
		assert.True(t, *got)
	})

	t.Run("&false round-trips as &false", func(t *testing.T) {
		falsehood := false
		got := run(t, "cmwf-false", &falsehood)
		require.NotNil(t, got)
		assert.False(t, *got)
	})
}

type getRepositoryByIDClient struct {
	*github.NoopClient

	mockGetRepositoryByID func(context.Context, int64) (*gg.Repository, error)
}

//nolint:revive // Method name must match interface
func (c *getRepositoryByIDClient) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	if c.mockGetRepositoryByID == nil {
		return c.NoopClient.GetRepositoryByID(ctx, id)
	}
	defer func() {
		c.MethodCalls = append(c.MethodCalls, github.MethodCall{
			Method: "GetRepositoryByID",
			Args:   []any{id},
		})
	}()
	return c.mockGetRepositoryByID(ctx, id)
}

func TestResolveAdditionalRepositories(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	jobWithRepos := &jobs.Job{
		ID:      "job-1",
		RepoID:  100,
		OwnerID: 200,
		AdditionalRepositories: []jobs.RepositoryRef{
			{RepoID: 11, OwnerID: 12, RepoNodeID: "n1", OwnerNodeID: "o1"},
			{RepoID: 21, OwnerID: 22, RepoNodeID: "n2", OwnerNodeID: "o2"},
		},
	}
	jobWithoutRepos := &jobs.Job{ID: "j"}

	tests := []struct {
		name        string
		flagEnabled bool
		job         *jobs.Job
		mockGetRepo func(context.Context, int64) (*gg.Repository, error)
		wantLen     int // expected length of returned slice; -1 means expect nil
		wantIDs     []int64
		wantCalls   []int64 // expected RepoIDs passed to GetRepositoryByID, in order
		wantErr     string
	}{
		{
			name:        "returns nil when feature flag is disabled",
			flagEnabled: false,
			job:         jobWithRepos,
			wantLen:     -1,
			wantCalls:   nil,
		},
		{
			name:        "returns nil when job has no additional repositories",
			flagEnabled: true,
			job:         jobWithoutRepos,
			wantLen:     -1,
			wantCalls:   nil,
		},
		{
			name:        "fetches metadata for each additional repository when flag is enabled",
			flagEnabled: true,
			job:         jobWithRepos,
			wantLen:     2,
			wantIDs:     []int64{11, 21},
			wantCalls:   []int64{11, 21},
		},
		{
			name:        "returns error when repository lookup fails",
			flagEnabled: true,
			job:         jobWithRepos,
			mockGetRepo: func(ctx context.Context, id int64) (*gg.Repository, error) {
				return nil, assert.AnError
			},
			wantLen:   -1,
			wantCalls: []int64{11},
			wantErr:   "failed to fetch additional repository 11",
		},
		{
			name:        "returns error when repository metadata is incomplete",
			flagEnabled: true,
			job:         jobWithRepos,
			mockGetRepo: func(ctx context.Context, id int64) (*gg.Repository, error) {
				return &gg.Repository{
					ID:   gg.Ptr(id),
					Name: gg.Ptr(""),
					Owner: &gg.User{
						ID:    gg.Ptr(int64(12)),
						Login: gg.Ptr("test-owner"),
					},
				}, nil
			},
			wantLen:   -1,
			wantCalls: []int64{11},
			wantErr:   "returned incomplete metadata",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			executor := &AgentJobExecutor{
				ffClient: featureflags.NewNoopClient(map[string]bool{
					featureflags.CopilotSWEAgentMultiRepoRead: tt.flagEnabled,
				}),
				obsv: obsv,
			}
			gh := &getRepositoryByIDClient{
				NoopClient:            &github.NoopClient{},
				mockGetRepositoryByID: tt.mockGetRepo,
			}

			got, err := executor.resolveAdditionalRepositories(ctx, gh, tt.job)
			if tt.wantErr != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.wantErr)
				assert.Nil(t, got)
			} else {
				require.NoError(t, err)

				if tt.wantLen < 0 {
					assert.Nil(t, got)
				} else {
					require.Len(t, got, tt.wantLen)
					for i, wantID := range tt.wantIDs {
						// NoopClient.GetRepositoryByID echoes the requested ID back as the
						// repo ID and hard-codes owner "test-owner" / repo "test-repo" /
						// owner ID 1.
						assert.Equal(t, "test-owner/test-repo", got[i].GitHubRepo)
						assert.Equal(t, "test-owner", got[i].GitHubRepoOwner)
						assert.Equal(t, int64(1), got[i].GitHubRepoOwnerID)
						assert.Equal(t, wantID, got[i].GitHubRepoID)
					}
				}
			}

			require.Len(t, gh.MethodCalls, len(tt.wantCalls))
			for i, wantID := range tt.wantCalls {
				assert.Equal(t, "GetRepositoryByID", gh.MethodCalls[i].Method)
				assert.Equal(t, []any{wantID}, gh.MethodCalls[i].Args)
			}
		})
	}
}

func TestLauncherTypeForJob(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("returns job.Launcher when already set", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		je := &AgentJobExecutor{
			obsv:      obsv,
			ffClient:  ffClient,
			launchers: launcher.NewStaticBuilder(launcher.NewNoopLauncher(obsv)),
		}

		job := &jobs.Job{Launcher: launcher.TypeSandbox}
		got := je.launcherTypeForJob(context.Background(), job)
		assert.Equal(t, launcher.TypeSandbox, got)
	})

	t.Run("returns sandbox when FF enabled for CCA app", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSandboxLauncher: true,
		})
		je := &AgentJobExecutor{
			obsv:        obsv,
			ffClient:    ffClient,
			launchers:   launcher.NewStaticBuilder(launcher.NewNoopLauncher(obsv)),
			appProvider: agenticapptest.NewTestProviderWithID(t, 101),
		}

		job := &jobs.Job{ActorID: 1, RepoID: 2, OwnerID: 3, AgentID: 101}
		got := je.launcherTypeForJob(context.Background(), job)
		assert.Equal(t, launcher.TypeSandbox, got)
	})

	t.Run("returns env default when FF enabled for triggered CCA app", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSandboxLauncher: true,
		})
		je := &AgentJobExecutor{
			obsv:        obsv,
			ffClient:    ffClient,
			launchers:   launcher.NewStaticBuilder(launcher.NewNoopLauncher(obsv)),
			appProvider: agenticapptest.NewTestProviderWithID(t, 101),
		}

		job := &jobs.Job{ActorID: 1, RepoID: 2, OwnerID: 3, AgentID: 101, IsTriggered: true}
		got := je.launcherTypeForJob(context.Background(), job)
		assert.Equal(t, launcher.TypeActions, got)
	})

	t.Run("returns env default when FF enabled for non-CCA app", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSandboxLauncher: true,
		})
		copilot := agenticapptest.NewTestCopilotWithID(t, 101)
		codeReview := agenticapp.NewCopilotCodeReview(202, agenticapp.CopilotCodeReviewComputeSlug, 203, "copilot-pull-request-reviewer[bot]", "commit-login", "commit@email.com")
		je := &AgentJobExecutor{
			obsv:        obsv,
			ffClient:    ffClient,
			launchers:   launcher.NewStaticBuilder(launcher.NewNoopLauncher(obsv)),
			appProvider: agenticapp.NewProvider(copilot, codeReview),
		}

		job := &jobs.Job{ActorID: 1, RepoID: 2, OwnerID: 3, AgentID: 202}
		got := je.launcherTypeForJob(context.Background(), job)
		assert.Equal(t, launcher.TypeActions, got)
	})

	t.Run("returns env default when FF disabled and no launcher set", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		je := &AgentJobExecutor{
			obsv:      obsv,
			ffClient:  ffClient,
			launchers: launcher.NewStaticBuilder(launcher.NewNoopLauncher(obsv)),
		}

		job := &jobs.Job{ActorID: 1, RepoID: 2, OwnerID: 3}
		got := je.launcherTypeForJob(context.Background(), job)
		// StaticBuilder wraps NoopLauncher which defaults to TypeActions
		assert.Equal(t, launcher.TypeActions, got)
	})

	t.Run("handles nil job without panic", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		je := &AgentJobExecutor{
			obsv:      obsv,
			ffClient:  ffClient,
			launchers: launcher.NewStaticBuilder(launcher.NewNoopLauncher(obsv)),
		}

		got := je.launcherTypeForJob(context.Background(), nil)
		assert.Equal(t, launcher.TypeActions, got)
	})

	t.Run("job.Launcher takes priority over FF", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSandboxLauncher: true,
		})
		je := &AgentJobExecutor{
			obsv:      obsv,
			ffClient:  ffClient,
			launchers: launcher.NewStaticBuilder(launcher.NewNoopLauncher(obsv)),
		}

		// Job already has Actions — FF should NOT override it
		job := &jobs.Job{Launcher: launcher.TypeActions, ActorID: 1, RepoID: 2, OwnerID: 3}
		got := je.launcherTypeForJob(context.Background(), job)
		assert.Equal(t, launcher.TypeActions, got)
	})
}
