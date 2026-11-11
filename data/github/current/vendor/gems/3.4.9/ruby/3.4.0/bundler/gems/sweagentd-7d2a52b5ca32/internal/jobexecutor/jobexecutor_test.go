package jobexecutor

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"testing"
	"time"

	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	sweagentv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	sweagentEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0/entities"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	jobCustomAgent "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/protojson"
)

func TestGetPremiumQuotaStatus(t *testing.T) {
	tests := []struct {
		name             string
		remainingQuota   int32
		totalQuota       int32
		overagePermitted bool
		ghError          error
		expectedHasQuota bool
		expectedQuota    int32
		expectError      bool
	}{
		{
			name:             "Sufficient quota",
			remainingQuota:   5,
			totalQuota:       10,
			overagePermitted: false,
			ghError:          nil,
			expectedHasQuota: true,
			expectedQuota:    10,
			expectError:      false,
		},
		{
			name:             "Zero quota but overage permitted",
			remainingQuota:   0,
			totalQuota:       10,
			overagePermitted: true,
			ghError:          nil,
			expectedHasQuota: true,
			expectedQuota:    10,
			expectError:      false,
		},
		{
			name:             "No quota and no overage",
			remainingQuota:   0,
			totalQuota:       10,
			overagePermitted: false,
			ghError:          nil,
			expectedHasQuota: false,
			expectedQuota:    10,
			expectError:      false,
		},
		{
			name:             "GitHub API error",
			remainingQuota:   0,
			totalQuota:       0,
			overagePermitted: false,
			ghError:          errors.New("github API error"),
			expectedHasQuota: false,
			expectedQuota:    0,
			expectError:      true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(map[string]bool{})
			ghTwirp := createMockGithubTwirpClientWithQuota(tt.remainingQuota, tt.totalQuota, tt.overagePermitted, tt.ghError)

			executor := &AgentJobExecutor{
				ffClient: ffClient,
				ghTwirp:  ghTwirp,
				obsv:     observability.NewNoopExporters(),
			}
			hasQuota, quota, err := executor.GetPremiumQuotaStatus(context.Background(), int64(123), int64(456), int64(789))

			if tt.expectError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}

			assert.Equal(t, tt.expectedHasQuota, hasQuota)
			assert.Equal(t, tt.expectedQuota, quota)
		})
	}
}

func TestGetPremiumQuotaStatus_EmitsPremiumQuotaExceededMetric(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghTwirp := createMockGithubTwirpClientWithQuota(0, 10, false, nil)

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

	hasQuota, quota, err := executor.GetPremiumQuotaStatus(context.Background(), 1, 2, 3)
	require.NoError(t, err)
	assert.False(t, hasQuota)
	assert.Equal(t, int32(10), quota)
	assert.Equal(t, "events.premium_quota_exceeded", recordedKey)
	assert.Equal(t, int64(1), recordedValue)
	assert.Len(t, recordedTags, 0)
}

func TestGetPremiumQuotaStatus_ChecksBillingPlatformWhenFeatureFlagEnabled(t *testing.T) {
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
			ffClient := featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentUseBillingPlatform: true,
			})
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
				ffClient: ffClient,
				ghTwirp:  ghTwirp,
				obsv:     obsv,
			}
			hasQuota, quota, err := executor.GetPremiumQuotaStatus(context.Background(), int64(123), int64(456), int64(789))
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

func TestGetPremiumQuotaStatus_ReturnsErrorWhenCustomerIdIsMinusOne(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentUseBillingPlatform: true,
	})

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
		ffClient: ffClient,
		ghTwirp:  ghTwirp,
		obsv:     obsv,
	}

	hasQuota, quota, err := executor.GetPremiumQuotaStatus(context.Background(), int64(123), int64(456), int64(789))

	require.Error(t, err)
	assert.Contains(t, err.Error(), "customer selection required")
	assert.False(t, hasQuota)
	assert.Equal(t, int32(0), quota)
}

func TestCheckQuota_CustomerSelectionRequired_WithFeatureFlag(t *testing.T) {
	tests := []struct {
		name                string
		featureFlagEnabled  bool
		expectError         bool
		expectSessionFailed bool
	}{
		{
			name:                "feature flag enabled - should fail session and return error",
			featureFlagEnabled:  true,
			expectError:         true,
			expectSessionFailed: true,
		},
		{
			name:                "feature flag disabled - should log and continue",
			featureFlagEnabled:  false,
			expectError:         false,
			expectSessionFailed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			obsv := observability.NewNoopExporters()

			ffClient := featureflags.NewNoopClient(map[string]bool{
				featureflags.CopilotSWEAgentUseBillingPlatform:   true,
				featureflags.CopilotSWEAgentSelectCustomerError: tt.featureFlagEnabled,
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
				RepoOwner:         "testowner",
				RepoName:          "testrepo",
				PullRequestNumber: 123,
				Status:            jobs.JobStatusQueued,
				AssignmentID:      "test-assignment",
			}
			jobStore.CreateJob(ctx, job)

			capiClient := capi.NewNoopClient()
			je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

			gh := ghFactory.NewClient("test-token")

			// Call checkQuota directly through the private method via the test executor
			err := je.AgentJobExecutor.checkQuota(ctx, gh, job)

			if tt.expectError {
				// When feature flag is enabled, should return error
				require.Error(t, err)
				assert.ErrorIs(t, err, githubtwirp.ErrCustomerSelectionRequired)
			} else {
				// When feature flag is disabled, should NOT return error (continue execution)
				require.NoError(t, err)
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
	ghTwirp := createMockGithubTwirpClientWithQuota(1, 1, true, nil)
	capiClient := capi.NewNoopClient()

	testJob := &jobs.Job{
		ID:        "job-1234",
		RepoOwner: "oregon",
		RepoName:  "trail",
		OwnerID:   1,
		RepoID:    2,
		ComputeID: "test-compute-id",
		ActorID:   3,
		Status:    jobs.JobStatusRunning,
	}

	sessionClient := capiClient.NewSessionClient(testJob.ActorID, "test-token")
	// Create a session for the job
	sessionResp, err := sessionClient.CreateSession(ctx, testJob.OwnerID, testJob.RepoID, 123,
		jobs.EventTypePullRequestReview, "https://example.com", []string{"123"}, "@copilot please help i only know how to vibe code",
		capi.SessionStateInProgress, "Test Session")
	require.NoError(t, err)
	testJob.SessionID = sessionResp.ID

	_, err = jobStore.CreateJob(ctx, testJob)
	require.NoError(t, err)

	t.Run("using valid Job", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		err := je.CancelJob(ctx, nil, testJob)
		require.NoError(t, err)
		assert.Equal(t, 1, len(je.TerminateAgentCalls()))
		terminateCallOpts := je.TerminateAgentCalls()[0]
		assert.Equal(t, testJob.RepoID, terminateCallOpts.RepoID)
		assert.Equal(t, testJob.OwnerID, terminateCallOpts.OwnerID)
		assert.Equal(t, testJob.RepoName, terminateCallOpts.RepoName)
		assert.Equal(t, testJob.RepoOwner, terminateCallOpts.RepoOwner)
		assert.Equal(t, testJob.ComputeID, terminateCallOpts.ComputeID)
	})
	t.Run("fails on terminal job", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		testJobNonTerminal := *testJob
		testJobNonTerminal.Status = jobs.JobStatusCompleted
		err := je.CancelJob(ctx, nil, &testJobNonTerminal)
		require.Error(t, err)
	})
	t.Run("finalizes non-executed job", func(t *testing.T) {
		testJobNonExecuted := *testJob
		testJobNonExecuted.Status = jobs.JobStatusQueued
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		err = je.CancelJob(ctx, nil, &testJobNonExecuted)
		require.NoError(t, err)
	})
	t.Run("errors on invalid status", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		testJobBadStatus := *testJob
		testJobBadStatus.Status = "fail me yo"
		err := je.CancelJob(ctx, nil, &testJobBadStatus)
		require.Error(t, err)
	})
	t.Run("errors if terminate fails", func(t *testing.T) {
		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		je.Launcher.TerminateAgentError = fmt.Errorf("you died of dysentery")
		err := je.CancelJob(ctx, nil, testJob)
		require.Error(t, err)
	})
}

func TestAgentJobExecutor_ProcessJob(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(1, 1, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret")
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
		RepoOwner:         "owner",
		RepoName:          "repo",
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
		obsvWithPublisher := obsv.WithPublisher(publisher)

		jobStore := memory.NewStore()
		jobStore.CreateAssignment(context.Background(), assignment)
		je := NewTestJobExecutor(obsvWithPublisher, hydroFFClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

		job := &jobs.Job{
			ID:                "job-1",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			RepoOwner:         "owner",
			RepoName:          "repo",
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
}

func TestAgentJobExecutor_ExecuteJob_SetsDefaultCustomAgent(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	jobStore := memory.NewStore()
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(1, 1, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret")
	require.NoError(t, err)

	je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)

	job := &jobs.Job{
		ID:               "test-job",
		RepoOwner:        "test-owner",
		RepoName:         "test-repo",
		ActorID:          123,
		Status:           jobs.JobStatusPending,
		RepoID:           456,
		OwnerID:          789,
		ProblemStatement: jobs.ProblemStatement{Content: "test problem"},
		RunOptions:       jobs.RunOptions{},
	}
	createdJob, err := jobStore.CreateJob(context.Background(), job)
	require.NoError(t, err)

	gh := &github.NoopClient{}

	err = je.executeJob(context.Background(), gh, createdJob, "nonce")
	require.NoError(t, err)

	expectedCustomAgent := customagent.Copilot(789, 456, createdJob.RepoOwner, createdJob.RepoName)

	require.Equal(t, expectedCustomAgent, createdJob.Args.CustomAgent)
}

func createMockGithubTwirpClientWithQuota(remainingQuota, totalQuota int32, overagePermitted bool, err error) *githubtwirp.NoopClient {
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
		NoopBillingClient: &billingMocks.MockClientInterface{},
	}
}

func TestProcessJob_CustomAgentConfigError(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	jobStore := memory.NewStore()
	ffClient := featureflags.NewNoopClient(nil)
	ghFactory := &github.NoopClientFactory{}
	ghTwirp := createMockGithubTwirpClientWithQuota(1, 1, true, nil)
	capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret")
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
		RepoOwner:    "owner",
		RepoName:     "repo",
		ActorLogin:   "actor",
		Status:       jobs.JobStatusQueued,
		AssignmentID: "assign-1",
		CustomAgent: jobCustomAgent.DBRecord{
			Name:        "invalid-agent",
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
			RepoOwner:    "owner",
			RepoName:     "repo",
			ActorLogin:   "actor",
			Status:       jobs.JobStatusQueued,
			AssignmentID: "assign-1",
			CustomAgent: jobCustomAgent.DBRecord{
				Name:        "valid-agent",
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
		}
		capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret")
		require.NoError(t, err)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		job := &jobs.Job{
			ID:                "test-job",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			RepoOwner:         "test-owner",
			RepoName:          "test-repo",
			ActorLogin:        "test-actor",
			PullRequestNumber: 123,
		}

		err = je.executeJob(ctx, &github.NoopClient{}, job, "nonce")
		require.NoError(t, err)
	})

	t.Run("customer selection required error stops execution but doesn't return error", func(t *testing.T) {
		ctx := context.Background()
		obsv := observability.NewNoopExporters()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseBillingPlatform:   true,
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
		capiClient, err := capi.NewClient(obsv, "https://api.githubcopilot.com", "integration-id", "hmac-secret")
		require.NoError(t, err)

		je := NewTestJobExecutor(obsv, ffClient, jobStore, ghFactory, ghTwirp, capiClient, nil, nil)
		job := &jobs.Job{
			ID:                "test-job",
			OwnerID:           1,
			RepoID:            2,
			ActorID:           3,
			RepoOwner:         "test-owner",
			RepoName:          "test-repo",
			ActorLogin:        "test-actor",
			PullRequestNumber: 123,
		}

		err = je.executeJob(ctx, &github.NoopClient{}, job, "nonce")
		require.NoError(t, err)
	})
}
