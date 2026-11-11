package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/aqueduct"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/customagent"
"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
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
	}
	defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), githubtwirp.NewNoopClient(), featureflags.NewNoopClient(nil))

	// Success case: job is created and queued
	t.Run("success", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	// Test that Event fields are properly set in the created job
	t.Run("success_with_event_fields", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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
		require.Equal(t, jobs.EventTypeApiCallReceived, job.EventType)
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
					IsSweagentdEnabled: true,
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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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
		require.Equal(t, jobs.EventTypeApiCallReceived, job.EventType) // EventType should still be set to API call
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
					IsSweagentdEnabled: true,
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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		// Simulate older client that doesn't send event fields at all
		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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
		require.Equal(t, jobs.EventTypeApiCallReceived, job.EventType) // EventType should still be set to API call
		require.Equal(t, "", job.EventURL)                             // Should default to empty string
		require.Nil(t, job.EventIdentifiers)                           // Should default to nil
		require.Equal(t, "", job.EventContent)                         // Should default to empty string
	})

	// CCA not enabled case
	t.Run("cca_not_enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: false,
				},
			},
		}

		obsv := observability.NewNoopExporters()

		ghf := &github.NoopClientFactory{}
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, nil, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
		}

		resp, err := server.CreateJob(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)

		// Check that it's a Twirp Aborted error
		twerr, ok := err.(twirp.Error)
		require.True(t, ok)
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
					BaseBranchName:   "main",
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
					BaseBranchName:   "main",
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
					BaseBranchName:   "main",
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
					BaseBranchName:   "main",
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
					BaseBranchName:   "main",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "problem_statement",
			},
		}

		for _, tt := range tests {
			tt := tt // capture range variable
			t.Run(tt.name, func(t *testing.T) {
				server := &Server{obsv: obsv}
				resp, err := server.CreateJob(context.Background(), tt.req)
				require.Nil(t, resp)
				require.Error(t, err)
				// Check that it's the expected Twirp error
				twerr, ok := err.(twirp.Error)
				require.True(t, ok, "Expected twirp.Error, got %T", err)
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
					IsSweagentdEnabled: true,
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
			MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
				// Return true to trigger the "copilot branch exists" rule violation
				return true, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				// Return no repository rules to keep test simple
				return nil, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				// Return no branch protection rules to keep test simple
				return nil, nil
			},
		}
		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return gh
			},
		}
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
		}

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		resp, err := server.CreateJob(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)

		// Check that it's a Twirp Aborted error with the expected message
		twerr, ok := err.(twirp.Error)
		require.True(t, ok)
		require.Equal(t, twirp.Aborted, twerr.Code())
		require.Contains(t, twerr.Msg(), "job cannot be created due to the following rule violations")

		// Verify that the jobExecutor.QueueJob was NOT called since job creation was blocked
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)
	})
}

func TestGetJobBySessionID_Found(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
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
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-1234",
		SessionID: "test-session-id",
		RepoOwner: "oregon",
		RepoName:  "trail",
		OwnerID:   789,
		RepoID:    456,
		ActorID:   1,
		ComputeID: "test-compute-id",
		Status:    jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

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
	require.Equal(t, int64(job.ActorId), testJob.ActorID)
	require.Equal(t, int64(req.RepoId), testJob.RepoID)
	require.Equal(t, int64(req.OwnerId), testJob.OwnerID)
}

func TestGetJobBySessionID_NotFound(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
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
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

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
	twerr, ok := err.(twirp.Error)
	require.True(t, ok)
	require.Equal(t, twirp.NotFound, twerr.Code())
	require.Contains(t, twerr.Msg(), "no job found for session ID")
}

func TestCreateCommand_Success(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
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
	ffClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_progress_commands": true,
	})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		RepoOwner:    "owner",
		RepoName:     "repo",
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    int64(testJob.OwnerID),
		RepoId:     int64(testJob.RepoID),
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
				IsSweagentdEnabled: true,
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
	ffClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_progress_commands": true,
	})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

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
	twerr, ok := err.(twirp.Error)
	require.True(t, ok)
	require.Equal(t, twirp.NotFound, twerr.Code())
	require.Contains(t, twerr.Msg(), "no job found for ID")
}

func TestCreateCommand_JobActorIdMismatch(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
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
	ffClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_progress_commands": true,
	})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-id",
		SessionID: "session-id",
		ActorID:   123,
		OwnerID:   1,
		RepoID:    2,
		RepoOwner: "owner",
		RepoName:  "repo",
		Status:    jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    int64(testJob.OwnerID),
		RepoId:     int64(testJob.RepoID),
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
	twerr, ok := err.(twirp.Error)
	require.True(t, ok)
	require.Equal(t, twirp.NotFound, twerr.Code())
}

func TestCreateCommand_TerminalJob(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
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
	ffClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_progress_commands": true,
	})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-id",
		SessionID: "session-id",
		ActorID:   42,
		OwnerID:   1,
		RepoID:    2,
		RepoOwner: "owner",
		RepoName:  "repo",
		Status:    jobs.JobStatusCompleted,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    int64(testJob.OwnerID),
		RepoId:     int64(testJob.RepoID),
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
	twerr, ok := err.(twirp.Error)
	require.True(t, ok, "Expected twirp.Error, got %T", err)
	require.Equal(t, twirp.FailedPrecondition, twerr.Code())
	require.Contains(t, twerr.Msg(), "cannot create command for job in terminal state")
}

func TestCreateCommand_InsufficientQuota(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
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
	}

	// Create server
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_progress_commands": true,
	})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		RepoOwner:    "owner",
		RepoName:     "repo",
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    int64(testJob.OwnerID),
		RepoId:     int64(testJob.RepoID),
		ActorId:    42,
		ExternalId: "external-id",
		Content:    "This is a test command",
		Timestamp:  time.Now().Unix(),
	}

	// Execute
	resp, err := server.CreateCommand(ctx, req)
	require.Error(t, err)
	require.Nil(t, resp)

	// Check that it returns a ResourceExhausted error when quota is insufficient
	twerr, ok := err.(twirp.Error)
	require.True(t, ok, "Expected twirp.Error, got %T", err)
	require.Equal(t, twirp.ResourceExhausted, twerr.Code())
	require.Contains(t, twerr.Msg(), "insufficient premium quota")

	// Verify that the command was NOT created in the store
	cmds, err := jobStore.GetCommands(ctx, testJob.AssignmentID, testJob.ID)
	require.NoError(t, err)
	require.Len(t, cmds, 0, "Command should not be created when quota is insufficient")
}

func TestCreateCommand_SufficientQuotaWithOverage(t *testing.T) {
	ctx := t.Context()

	mockGhTwirp := &githubtwirp.NoopClient{
		NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
			ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
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
	}

	// Create server
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_progress_commands": true,
	})

	gh := &github.NoopClient{}
	ghf := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return gh
		},
	}
	jobStore := memory.NewStore()
	limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:           "job-id",
		SessionID:    "session-id",
		AssignmentID: "assignment-id",
		ActorID:      42,
		OwnerID:      1,
		RepoID:       2,
		RepoOwner:    "owner",
		RepoName:     "repo",
		Status:       jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

	req := &jobs_pb.CreateCommandRequest{
		JobId:      testJob.ID,
		OwnerId:    int64(testJob.OwnerID),
		RepoId:     int64(testJob.RepoID),
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

// MockGitHubClientWithRules simulates a GitHub client that returns rule violations
type MockGitHubClientWithRules struct {
	github.NoopClient
}

func TestCreateJob_CustomAgents(t *testing.T) {
	t.Run("creates job with default Copilot custom agent when feature flag disabled", func(t *testing.T) {
		ctx := context.Background()
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: false,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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
		assert.Equal(t, "copilot", job.CustomAgent.Name) // Returns Copilot agent when FF disabled
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
					IsSweagentdEnabled: true,
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
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: true,
		})

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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		customAgentSvc := customagent.NewService(obsv, spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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

	t.Run("creates job with custom custom agent when attributes specified", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents:  true,
			featureflags.CopilotSWEAgentCustomAgentAsAPI: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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

		// Verify that the job was created with the custom custom agent
		job, err := jobStore.GetJob(ctx, int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, "custom", job.CustomAgent.Name)
		assert.Equal(t, "Custom Test Agent", job.CustomAgent.DisplayName)
		assert.Equal(t, "A custom agent for testing", job.CustomAgent.Description)
		assert.Equal(t, "You are a custom test agent", job.CustomAgent.Prompt)
		assert.Equal(t, []string{"custom-tool", "test-tool"}, job.CustomAgent.Tools)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("creates job with default Copilot custom agent when no custom agent specified", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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
		assert.Equal(t, "copilot", job.CustomAgent.Name)
		assert.Equal(t, "Copilot", job.CustomAgent.DisplayName)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 1)
	})

	t.Run("returns error when custom agent loading fails", func(t *testing.T) {
		ctx := context.Background()

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
					return nil, fmt.Errorf("unexpected error accessing repositories")
				},
			},
		}

		// Create server with custom agent feature flag enabled
		obsv := observability.NewNoopExporters()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: true,
		})

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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		// Create a custom agent service that will fail when accessing spokes
		// Use an empty map so no agents are available
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t))

		// Don't set up any QueueJob expectations since the job creation should fail before reaching that point

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
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
					IsSweagentdEnabled: true,
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
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentUseCustomAgents: true,
		})

		// Create a GitHub client that will fail when accessing repository
		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		// Create a custom agent service that will fail when accessing spokes
		// Use an empty map so no agents are available
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t))

		// Don't set up any QueueJob expectations since the job creation should fail before reaching that point

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "main",
			CustomAgent:      "does-not-exist",
		}

		// Execute
		_, err := server.CreateJob(ctx, req)
		require.Error(t, err)
		require.Equal(t, err.(twirp.Error).Code(), twirp.NotFound)
		assert.Contains(t, err.Error(), "specified custom agent not found")
	})
}

func TestCreateJob_BaseBranchName(t *testing.T) {
	// Shared defaults for subtests
	obsv := observability.NewNoopExporters()
	defaultGH := &github.NoopClient{}
	defaultGHF := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return defaultGH
		},
	}

	t.Run("uses base_branch_name when provided", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "feature-branch", // Custom branch name
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

	t.Run("falls back to default branch when base_branch_name is empty", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "", // Empty - should fall back to default
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

	t.Run("falls back to default branch when base_branch_name is whitespace only", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
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
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t))

		// jobsInQueue := aq.QueuedJobs(aqueductJobs.APIJobQueueName)
		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobRequest{
			ActorId:          123,
			RepoId:           456,
			OwnerId:          789,
			ProblemStatement: "Fix the bug",
			BaseBranchName:   "   \t\n  ", // Whitespace only - should fall back to default
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
}

func TestCreateJobForIssue(t *testing.T) {
	// Shared defaults for subtests
	obsv := observability.NewNoopExporters()
	defaultGH := &github.NoopClient{}
	defaultGHF := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return defaultGH
		},
	}
	defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), githubtwirp.NewNoopClient(), featureflags.NewNoopClient(nil))

	// Success case: job is created and queued for an issue
	t.Run("success", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:      req.IssueId,
							Number:  42,
							Body:    "This is a test issue that needs to be fixed",
							HtmlUrl: "https://github.com/test/repo/issues/42",
							Labels:  []string{"bug", "priority-high"},
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

		jobStore := memory.NewStore()
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		lim := limiter.NewJobLimiter(jobStore, 10, time.Minute*5)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Fix this specific issue",
			BaseBranchName:         "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, int64(req.ActorId), job.ActorID)
		require.Equal(t, int64(req.RepoId), job.RepoID)
		require.Equal(t, int64(req.OwnerId), job.OwnerID)
		// Validate that it contains the issue body
		require.Contains(t, job.ProblemStatement.Content, "This is a test issue.")
		// Validate that it countains the additional instructions
		require.Contains(t, job.ProblemStatement.Content, "Fix this specific issue")
		require.Equal(t, jobs.JobStatusQueued, job.Status)
		require.Equal(t, 42, job.IssueNumber)
	})

	// CCA not enabled case
	t.Run("cca_not_enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: false,
				},
			},
		}

		obsv := observability.NewNoopExporters()

		ghf := &github.NoopClientFactory{}
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		lim := limiter.NewJobLimiter(jobStore, 10, time.Minute*5)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, lim, exp, nil, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Fix this issue",
			BaseBranchName:         "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)

		// Check that it's a Twirp Aborted error
		twerr, ok := err.(twirp.Error)
		require.True(t, ok)
		require.Equal(t, twirp.Aborted, twerr.Code())
		require.Contains(t, twerr.Msg(), "user or repo does not have CCA enabled")
	})

	// Validation cases (table-driven)
	t.Run("validates_fields", func(t *testing.T) {
		tests := []struct {
			name              string
			req               *jobs_pb.CreateJobForIssueRequest
			expectedErrorCode twirp.ErrorCode
			expectedErrorMsg  string
		}{
			{
				name: "missing actor_id",
				req: &jobs_pb.CreateJobForIssueRequest{
					ActorId:                0, // Missing
					RepoId:                 456,
					OwnerId:                789,
					IssueId:                999,
					AdditionalInstructions: "Fix the bug",
					BaseBranchName:         "main",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "actor_id",
			},
			{
				name: "missing owner_id",
				req: &jobs_pb.CreateJobForIssueRequest{
					ActorId:                123,
					RepoId:                 456,
					OwnerId:                0, // Missing
					IssueId:                999,
					AdditionalInstructions: "Fix the bug",
					BaseBranchName:         "main",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "owner_id",
			},
			{
				name: "missing repo_id",
				req: &jobs_pb.CreateJobForIssueRequest{
					ActorId:                123,
					RepoId:                 0, // Missing
					OwnerId:                789,
					IssueId:                999,
					AdditionalInstructions: "Fix the bug",
					BaseBranchName:         "main",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "repo_id",
			},
			{
				name: "missing issue_id",
				req: &jobs_pb.CreateJobForIssueRequest{
					ActorId:                123,
					RepoId:                 456,
					OwnerId:                789,
					IssueId:                0, // Missing
					AdditionalInstructions: "Fix the bug",
					BaseBranchName:         "main",
				},
				expectedErrorCode: twirp.InvalidArgument,
				expectedErrorMsg:  "issue_id",
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: false,
				},
			},
		}
		server := NewServer(obsv, defaultGHF, mockGhTwirp, memory.NewStore(), nil, ffClient)

		for _, tt := range tests {
			tt := tt // capture range variable
			t.Run(tt.name, func(t *testing.T) {
				resp, err := server.CreateJobForIssue(t.Context(), tt.req)
				require.Nil(t, resp)
				require.Error(t, err)
				// Check that it's the expected Twirp error
				twerr, ok := err.(twirp.Error)
				require.True(t, ok, "Expected twirp.Error, got %T", err)
				require.Equal(t, tt.expectedErrorCode, twerr.Code())
				require.Contains(t, twerr.Msg(), tt.expectedErrorMsg)
			})
		}
	})

	// Issue not found case
	t.Run("issue_not_found", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return nil, errors.New("issue not found")
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
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		lim := limiter.NewJobLimiter(jobStore, 10, time.Minute*5)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Fix this issue",
			BaseBranchName:         "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to get issue by ID")
	})

	// Rules violation case: job creation blocked due to repo rules
	t.Run("rules_violation", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:      req.IssueId,
							Number:  42,
							Body:    "Test issue",
							HtmlUrl: "https://github.com/test/repo/issues/42",
							Labels:  []string{},
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

		gh := &github.NoopClient{
			MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
				// Return true to trigger the "copilot branch exists" rule violation
				return true, nil
			},
			MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
				// Return no repository rules to keep test simple
				return nil, nil
			},
			MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
				// Return no branch protection rules to keep test simple
				return nil, nil
			},
		}
		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return gh
			},
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		lim := limiter.NewJobLimiter(jobStore, 10, time.Minute*5)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, ghf, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Fix this issue",
			BaseBranchName:         "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)

		// Check that it's a Twirp Aborted error with the expected message
		twerr, ok := err.(twirp.Error)
		require.True(t, ok)
		require.Equal(t, twirp.Aborted, twerr.Code())
		require.Contains(t, twerr.Msg(), "job cannot be created due to the following rule violations")
	})

	// Test that issue information is properly included in the job
	t.Run("success_with_issue_details", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:      req.IssueId,
							Number:  123,
							Body:    "This is a detailed issue description\nwith multiple lines",
							HtmlUrl: "https://github.com/test/repo/issues/123",
							Labels:  []string{"bug", "enhancement", "priority-high"},
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

		jobStore := memory.NewStore()
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		lim := limiter.NewJobLimiter(jobStore, 10, time.Minute*5)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))
		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Please fix this specific bug",
			BaseBranchName:         "develop",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify issue number is set
		require.Equal(t, 123, job.IssueNumber)

		// Verify the base commit uses the provided branch
		require.Equal(t, "develop", job.BaseCommit)
	})

	// Test that Event fields are properly set in CreateJobForIssue
	t.Run("success_with_event_fields", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:      456,
							Number:  123,
							Title:   "Test Issue",
							Body:    "This is a test issue",
							HtmlUrl: "https://github.com/owner/repo/issues/123",
							Labels:  []string{},
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

		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                456,
			AdditionalInstructions: "Please add more tests",
			BaseBranchName:         "feature-branch",
			EventContent:           "User assigned issue via web interface",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify Event fields are set correctly
		require.Equal(t, jobs.EventTypeApiCallReceived, job.EventType)
		require.Equal(t, "https://github.com/owner/repo/issues/123", job.EventURL)
		require.Equal(t, []string{"456"}, job.EventIdentifiers)
		require.Equal(t, "User assigned issue via web interface", job.EventContent)
	})

	// Test that Event fields handle empty content correctly
	t.Run("success_with_empty_event_content", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:      789,
							Number:  456,
							Title:   "Empty Content Test Issue",
							Body:    "This issue tests empty event content",
							HtmlUrl: "https://github.com/test/repo/issues/456",
							Labels:  []string{},
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

		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                789,
			AdditionalInstructions: "Please handle this carefully",
			BaseBranchName:         "main",
			// EventContent is intentionally empty
			EventContent: "",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify Event fields are set correctly even with empty content
		require.Equal(t, jobs.EventTypeApiCallReceived, job.EventType)            // EventType should still be set
		require.Equal(t, "https://github.com/test/repo/issues/456", job.EventURL) // URL should come from issue
		require.Equal(t, []string{"789"}, job.EventIdentifiers)                   // Identifiers should be set from issue ID
		require.Equal(t, "", job.EventContent)                                    // Empty content should be preserved
	})

	// Test that older clients (without event content field) work correctly for CreateJobForIssue
	t.Run("success_with_omitted_event_content_legacy_client", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:      req.IssueId,
							Number:  42,
							Title:   "Legacy Client Test Issue",
							Body:    "This issue tests legacy client compatibility",
							HtmlUrl: "https://github.com/test/repo/issues/42",
							Labels:  []string{},
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

		jobStore := memory.NewStore()
		limiter := jobLimiter.NewJobLimiter(jobStore, 10, time.Hour)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		// Simulate older client that doesn't send event_content field at all
		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Please handle this carefully",
			BaseBranchName:         "main",
			// Note: EventContent field is completely omitted to simulate
			// an older client that hasn't updated to the new proto
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)

		// Verify that job creation succeeds and Event fields get default values
		require.Equal(t, jobs.EventTypeApiCallReceived, job.EventType)           // EventType should still be set
		require.Equal(t, "https://github.com/test/repo/issues/42", job.EventURL) // URL should come from issue
		require.Equal(t, []string{"999"}, job.EventIdentifiers)                  // Identifiers should be set from issue ID
		require.Equal(t, "", job.EventContent)                                   // Should default to empty string
	})

	// Test fallback to default branch when base_branch_name is empty/whitespace
	t.Run("success_with_default_branch_fallback", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsSweagentdEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:      req.IssueId,
							Number:  42,
							Body:    "Test issue",
							HtmlUrl: "https://github.com/test/repo/issues/42",
							Labels:  []string{},
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

		jobStore := memory.NewStore()
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		lim := limiter.NewJobLimiter(jobStore, 10, time.Minute*5)
		jobService := jobservice.New(obsv, ffClient, jobStore, nil, defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t))

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Fix the issue",
			BaseBranchName:         "   \t\n  ", // Whitespace only - should fall back to default
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.Equal(t, "main", job.BaseCommit) // Should use the repository's default branch
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
