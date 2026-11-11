package twirpserver

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
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
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

type capturingGitHubClient struct {
	*github.NoopClient

	repoIDs                 []int64
	issueContextRepoNodeIDs []string
}

func newCapturingGitHubClient() *capturingGitHubClient {
	return &capturingGitHubClient{
		NoopClient: &github.NoopClient{},
	}
}

//nolint:revive // method name must match interface github.ClientInterface
func (c *capturingGitHubClient) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	c.repoIDs = append(c.repoIDs, id)
	nodeID := fmt.Sprintf("repo-node-%d", id)
	return &gg.Repository{
		ID:            gg.Ptr(id),
		Name:          gg.Ptr(fmt.Sprintf("repo-%d", id)),
		NodeID:        gg.Ptr(nodeID),
		DefaultBranch: gg.Ptr("main"),
		Owner: &gg.User{
			ID:     gg.Ptr(id + 1000),
			Login:  gg.Ptr(fmt.Sprintf("owner-%d", id)),
			NodeID: gg.Ptr(fmt.Sprintf("owner-node-%d", id)),
		},
	}, nil
}

func (c *capturingGitHubClient) GetIssueContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*github.IssueContext, error) {
	c.issueContextRepoNodeIDs = append(c.issueContextRepoNodeIDs, repoNodeID)
	return c.NoopClient.GetIssueContext(ctx, repoNodeID, number, isAgentic)
}

type missingNodeIDGitHubClient struct {
	*github.NoopClient

	issueRepoID        int64
	issueContextCalled bool
}

func newMissingNodeIDGitHubClient(issueRepoID int64) *missingNodeIDGitHubClient {
	return &missingNodeIDGitHubClient{
		NoopClient:  &github.NoopClient{},
		issueRepoID: issueRepoID,
	}
}

//nolint:revive // method name must match interface github.ClientInterface
func (c *missingNodeIDGitHubClient) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	repo, err := c.NoopClient.GetRepositoryByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if id == c.issueRepoID {
		repo.NodeID = nil
	}
	return repo, nil
}

func (c *missingNodeIDGitHubClient) GetIssueContext(ctx context.Context, repoNodeID string, number int, isAgentic agenticapp.IsAgenticFunc) (*github.IssueContext, error) {
	if repoNodeID == "" {
		panic("GetIssueContext should not be called when repository node ID is missing")
	}
	c.issueContextCalled = true
	return c.NoopClient.GetIssueContext(ctx, repoNodeID, number, isAgentic)
}

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
		}

		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), appProvider, nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider)

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, nil, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

	testJob, _ := jobStore.CreateJob(ctx, &jobs.Job{
		ID:        "job-1234",
		SessionID: "test-session-id",
		OwnerID:   789,
		RepoID:    456,
		ActorID:   1,
		ComputeID: "test-compute-id",
		Status:    jobs.JobStatusRunning,
	})

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		customAgentSvc := customagent.NewService(obsv, spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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

	// TODO (chuxel): Remove this variation of the test after the CopilotSWEAgentCustomAgentPermissions feature flag is fully rolled out.
	t.Run("creates job with custom agent when attributes specified", func(t *testing.T) {
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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		assert.Equal(t, "job-agent", job.CustomAgent.Name) // Job-scoped agents use the name as-is (or default to "job-agent")
		assert.Equal(t, jobsCustomAgent.ScopeJob, job.CustomAgent.Scope)
		assert.Equal(t, "Custom Test Agent", job.CustomAgent.DisplayName)
		assert.Equal(t, "A custom agent for testing", job.CustomAgent.Description)
		assert.Equal(t, []string{"custom-tool", "test-tool"}, job.CustomAgent.Tools)

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		assert.Equal(t, jobsCustomAgent.ScopeJob, job.CustomAgent.Scope)
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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		assert.Equal(t, jobsCustomAgent.ScopeJob, job.CustomAgent.Scope)
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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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

	t.Run("creates job with custom agent when attributes specified and CopilotSWEAgentCustomAgentPermissions enabled uses FromDB", func(t *testing.T) {
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
			featureflags.CopilotSWEAgentCustomAgentAsAPI:       true,
			featureflags.CopilotSWEAgentCustomAgentPermissions: true,
		})

		gh := &github.NoopClient{}
		ghf := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		assert.Equal(t, jobsCustomAgent.ScopeJob, job.CustomAgent.Scope)
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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		// Create a custom agent service that will fail when accessing spokes
		// Use an empty map so no agents are available
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		// Don't set up any QueueJob expectations since the job creation should fail before reaching that point

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		// Create a custom agent service that will fail when accessing spokes
		// Use an empty map so no agents are available
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokes, mockGhTwirp, ffClient)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		// Don't set up any QueueJob expectations since the job creation should fail before reaching that point

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)

		t.Run("when version is specified", func(t *testing.T) {
			// Create spokes client with custom agent config at a specific version (SHA)
			spokes := spokestest.NewClient(t,
				spokestest.WithCommitSHAAndBlob(".github/agents/my-agent.md", testSHA, []byte(agentConfig)),
			)

			customAgentSvc := customagent.NewService(obsv, spokes, mockGhTwirp, ffClient)
			jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
			server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
			jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, customAgentSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
			server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		require.Len(t, aq.QueuedJobs(aqueductJobs.AgentJobQueueName), 0)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		// Use a non-zero app ID to ensure the test catches missing WithAgentID calls
		expectedAppID := int64(42424)
		appProvider := agenticapptest.NewTestProviderWithID(t, expectedAppID)

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capturedBypassActorID := int64(0)
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           req.IssueId,
							RepositoryId: uint64(456),
							Number:       42,
							Body:         "This is a test issue that needs to be fixed",
							HtmlUrl:      "https://github.com/test/repo/issues/42",
							Labels:       []string{"bug", "priority-high"},
						},
					}, nil
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
		}

		jobStore := memory.NewStore()
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider)

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
		// Validate that it contains the additional instructions
		require.Contains(t, job.ProblemStatement.Content, "Fix this specific issue")
		require.Equal(t, jobs.JobStatusQueued, job.Status)
		require.Equal(t, 42, job.IssueNumber)
		// Validate that the agent ID is set correctly
		require.Equal(t, expectedAppID, job.AgentID, "job.AgentID should be set to the CopilotApp ID")
		// Validate that the agent ID was passed to IsBypassActor
		require.Equal(t, expectedAppID, capturedBypassActorID, "IsBypassActor should be called with the app ID")
	})

	t.Run("uses issue repository for issue context", func(t *testing.T) {
		issueRepoID := int64(999001)
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capturingClient := newCapturingGitHubClient()

		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return capturingClient
			},
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return capturingClient, nil
			},
		}

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:            req.IssueId,
							Number:        77,
							RepositoryId:  uint64(issueRepoID),
							RepositoryNwo: "issue-owner/issue-repo",
							Body:          "ensure correct repo is used",
							HtmlUrl:       "https://github.com/test/issue-repo/issues/77",
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:        123,
			RepoId:         456,
			OwnerId:        789,
			IssueId:        555,
			BaseBranchName: "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		require.Contains(t, capturingClient.repoIDs, int64(req.RepoId))
		require.Contains(t, capturingClient.repoIDs, issueRepoID)
		expectedNodeID := fmt.Sprintf("repo-node-%d", issueRepoID)
		require.Contains(t, capturingClient.issueContextRepoNodeIDs, expectedNodeID)
		unexpectedNodeID := fmt.Sprintf("repo-node-%d", int64(req.RepoId))
		require.NotContains(t, capturingClient.issueContextRepoNodeIDs, unexpectedNodeID)
	})

	t.Run("cross_repo_issue_uses_repo_specific_client", func(t *testing.T) {
		issueRepoID := int64(777001)
		var repoNameArg, ownerNameArg string
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		assignmentClient := newCapturingGitHubClient()
		issueClient := newCapturingGitHubClient()

		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return assignmentClient
			},
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				repoNameArg = repoName
				ownerNameArg = ownerName
				return issueClient, nil
			},
		}

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:            req.IssueId,
							RepositoryId:  uint64(issueRepoID),
							RepositoryNwo: "issue-owner/issue-repo",
							Number:        88,
							Body:          "cross repo issue",
							HtmlUrl:       "https://github.com/issue-owner/issue-repo/issues/88",
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId: 123,
			RepoId:  456,
			OwnerId: 789,
			IssueId: 9900,
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		require.Equal(t, "issue-repo", repoNameArg)
		require.Equal(t, "issue-owner", ownerNameArg)
		require.Contains(t, assignmentClient.repoIDs, int64(req.RepoId))
		require.NotContains(t, assignmentClient.repoIDs, issueRepoID)
		require.Contains(t, issueClient.repoIDs, issueRepoID)
		require.NotContains(t, issueClient.repoIDs, int64(req.RepoId))
		expectedNodeID := fmt.Sprintf("repo-node-%d", issueRepoID)
		require.Contains(t, issueClient.issueContextRepoNodeIDs, expectedNodeID)

		// Verify that cross-repo issue uses full NWO format in PR body suffix
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.NotNil(t, job.Features.PullRequest)
		require.Contains(t, job.Features.PullRequest.BodySuffix, "Fixes issue-owner/issue-repo#88", "Cross-repo issue reference should use full NWO format")
	})

	t.Run("cross_repo_issue_requires_repository_nwo", func(t *testing.T) {
		issueRepoID := int64(888002)
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		assignmentClient := newCapturingGitHubClient()
		newClientRequested := false

		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return assignmentClient
			},
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				newClientRequested = true
				return newCapturingGitHubClient(), nil
			},
		}

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:            req.IssueId,
							RepositoryId:  uint64(issueRepoID),
							RepositoryNwo: "",
							Number:        12,
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId: 123,
			RepoId:  456,
			OwnerId: 789,
			IssueId: 9911,
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)
		require.Contains(t, err.Error(), "issue repository name with owner missing")
		require.False(t, newClientRequested)
	})

	t.Run("returns error when issue repository lacks node id", func(t *testing.T) {
		issueRepoID := int64(424242)
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		missingNodeClient := newMissingNodeIDGitHubClient(issueRepoID)

		ghf := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return missingNodeClient
			},
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return missingNodeClient, nil
			},
		}

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:            req.IssueId,
							Number:        66,
							RepositoryId:  uint64(issueRepoID),
							RepositoryNwo: "issue-owner/issue-repo",
							Body:          "missing node id repo",
							HtmlUrl:       "https://github.com/test/issue-repo/issues/66",
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:        123,
			RepoId:         456,
			OwnerId:        789,
			IssueId:        987,
			BaseBranchName: "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.Nil(t, resp)
		require.Error(t, err)
		require.Contains(t, err.Error(), "issue repository missing node ID")
		require.False(t, missingNodeClient.issueContextCalled)
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, lim, exp, nil, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
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
					IsAgentEnabled: false,
				},
			},
		}
		server := NewServer(obsv, defaultGHF, mockGhTwirp, memory.NewStore(), nil, ffClient, agenticapptest.NewTestProvider(t))

		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				resp, err := server.CreateJobForIssue(t.Context(), tt.req)
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

	// Issue not found case
	t.Run("issue_not_found", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           req.IssueId,
							RepositoryId: uint64(456),
							Number:       42,
							Body:         "Test issue",
							HtmlUrl:      "https://github.com/test/repo/issues/42",
							Labels:       []string{},
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

		spokes := spokestest.NewClient(t)
		spokes.MockCheckForExistingRefs = func(ctx context.Context, repoID uint64, refs []string) ([]bool, error) {
			return make([]bool, len(refs)), nil
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
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobStore := memory.NewStore()
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokes, agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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

		// Check that it's a Twirp FailedPrecondition error with the expected message
		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		require.Equal(t, twirp.FailedPrecondition, twerr.Code())
		require.Contains(t, twerr.Msg(), "job cannot be created due to the following rule violations")
	})

	// Test that issue information is properly included in the job
	t.Run("success_with_issue_details", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           req.IssueId,
							RepositoryId: uint64(456),
							Number:       123,
							Body:         "This is a detailed issue description\nwith multiple lines",
							HtmlUrl:      "https://github.com/test/repo/issues/123",
							Labels:       []string{"bug", "enhancement", "priority-high"},
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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

		// Verify same-repo issue uses short format (not full NWO)
		require.NotNil(t, job.Features.PullRequest)
		require.Contains(t, job.Features.PullRequest.BodySuffix, "Fixes #123", "Same-repo issue reference should use short format")
		require.NotContains(t, job.Features.PullRequest.BodySuffix, "Fixes test/repo#123", "Same-repo issue reference should not include NWO")
	})

	// Test that Event fields are properly set in CreateJobForIssue
	t.Run("success_with_event_fields", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           456,
							RepositoryId: uint64(456),
							Number:       123,
							Title:        "Test Issue",
							Body:         "This is a test issue",
							HtmlUrl:      "https://github.com/owner/repo/issues/123",
							Labels:       []string{},
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		require.Equal(t, jobs.EventTypeAPICallReceived, job.EventType)
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
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           789,
							RepositoryId: uint64(456),
							Number:       456,
							Title:        "Empty Content Test Issue",
							Body:         "This issue tests empty event content",
							HtmlUrl:      "https://github.com/test/repo/issues/456",
							Labels:       []string{},
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		require.Equal(t, jobs.EventTypeAPICallReceived, job.EventType)            // EventType should still be set
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
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           req.IssueId,
							RepositoryId: uint64(456),
							Number:       42,
							Title:        "Legacy Client Test Issue",
							Body:         "This issue tests legacy client compatibility",
							HtmlUrl:      "https://github.com/test/repo/issues/42",
							Labels:       []string{},
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Hour)
		limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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
		require.Equal(t, jobs.EventTypeAPICallReceived, job.EventType)           // EventType should still be set
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
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           req.IssueId,
							RepositoryId: uint64(456),
							Number:       42,
							Body:         "Test issue",
							HtmlUrl:      "https://github.com/test/repo/issues/42",
							Labels:       []string{},
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

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

	t.Run("includes_custom_agent_and_additional_instructions_in_body_suffix", func(t *testing.T) {
		// Custom agent with display name and description
		customAgentFiles := map[string]string{
			"my-agent": `---
name: My Custom Agent
description: This is my custom agent
---
Custom agent prompt`,
		}
		caSvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, customAgentFiles), githubtwirp.NewNoopClient(), featureflags.NewNoopClient(nil))

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:           req.IssueId,
							RepositoryId: uint64(456),
							Number:       42,
							Body:         "Test issue body",
							HtmlUrl:      "https://github.com/test/repo/issues/42",
							Labels:       []string{},
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
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, lim, exp, caSvc, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, agenticapptest.NewTestProvider(t))

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:                123,
			RepoId:                 456,
			OwnerId:                789,
			IssueId:                999,
			AdditionalInstructions: "Please review this carefully",
			BaseBranchName:         "main",
			CustomAgent:            "my-agent",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)
		require.NotEmpty(t, resp.JobId)

		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		require.NotNil(t, job.Features.PullRequest)

		// Verify custom agent info is in BodySuffix
		require.Contains(t, job.Features.PullRequest.BodySuffix, "Custom agent used: My Custom Agent", "Custom agent display name should be in BodySuffix")
		require.Contains(t, job.Features.PullRequest.BodySuffix, "This is my custom agent", "Custom agent description should be in BodySuffix")

		// Verify additional instructions are in BodySuffix as a collapsible section
		require.Contains(t, job.Features.PullRequest.BodySuffix, "Original prompt", "Additional instructions should be wrapped in 'Original prompt' section")
		require.Contains(t, job.Features.PullRequest.BodySuffix, "Please review this carefully", "Additional instructions content should be in BodySuffix")

		// Verify issue reference is in BodySuffix
		require.Contains(t, job.Features.PullRequest.BodySuffix, "Fixes #42", "Issue reference should be in BodySuffix")
	})
}

func TestCreateJobForIssue_AgentIDFromRequest(t *testing.T) {
	obsv := observability.NewNoopExporters()
	defaultGH := &github.NoopClient{}
	defaultGHF := &github.NoopClientFactory{
		MockNewClient: func(token string) github.ClientInterface {
			return defaultGH
		},
	}
	defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), githubtwirp.NewNoopClient(), featureflags.NewNoopClient(nil))

	t.Run("uses agent ID from request", func(t *testing.T) {
		customAppID := int64(12345)
		customApp := agenticapptest.NewTestCopilotWithID(t, customAppID)
		appProvider := agenticapp.NewProvider(customApp)

		ffClient := featureflags.NewNoopClient(nil)

		capturedAgentID := int64(0)
		capturedBypassActorID := int64(0)
		mockGhTwirp := &githubtwirp.NoopClient{
			MockIsAgentEnabled: func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
				capturedAgentID = agentID
				return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
			},
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
				MockGetIssueById: func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
					return &sweagentdTwirp.GetIssueByIdResponse{
						Issue: &sweagentdTwirp.Issue{
							Id:            req.IssueId,
							RepositoryId:  uint64(456),
							RepositoryNwo: "test-owner/test-repo",
							Number:        42,
							Body:          "Test issue",
							HtmlUrl:       "https://github.com/test-owner/test-repo/issues/42",
						},
					}, nil
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
		}

		jobStore := memory.NewStore()
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:        123,
			RepoId:         456,
			OwnerId:        789,
			IssueId:        999,
			AgentId:        customAppID,
			BaseBranchName: "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.NoError(t, err)
		require.NotNil(t, resp)

		// Verify the custom agent ID was used for enablement check
		assert.Equal(t, customAppID, capturedAgentID, "IsAgentEnabled should be called with the custom agent ID")

		// Verify the custom agent ID was used for IsBypassActor check
		assert.Equal(t, customAppID, capturedBypassActorID, "IsBypassActor should be called with the custom agent ID")

		// Verify the job's AgentID is set correctly
		job, err := jobStore.GetJob(t.Context(), int64(req.OwnerId), int64(req.RepoId), resp.JobId)
		require.NoError(t, err)
		require.NotNil(t, job)
		assert.Equal(t, customAppID, job.AgentID, "job.AgentID should be set to the custom agent ID")
	})

	t.Run("returns error when agent ID not found", func(t *testing.T) {
		copilotAppID := int64(99999)
		customApp := agenticapptest.NewTestCopilotWithID(t, copilotAppID)
		appProvider := agenticapp.NewProvider(customApp)

		ffClient := featureflags.NewNoopClient(nil)

		mockGhTwirp := &githubtwirp.NoopClient{
			NoopSweagentdAPI: &githubtwirp.NoopSweagentdAPI{
				ConfigurationForRepositoryResponse: &sweagentdTwirp.ConfigurationForRepositoryResponse{
					IsAgentEnabled: true,
				},
			},
		}

		jobStore := memory.NewStore()
		exp := experiments.NewNoopClient()
		aq := aqueduct.NewMemoryClient(obsv)
		countTracker := jobLimiter.NewJobCountMemoryTracker(10, time.Minute*5)
		lim := jobLimiter.NewJobLimiter(jobStore, countTracker)
		jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), defaultGHF, mockGhTwirp, aq, lim, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), appProvider, nil)

		server := NewServer(obsv, defaultGHF, mockGhTwirp, jobStore, jobService, ffClient, appProvider)

		req := &jobs_pb.CreateJobForIssueRequest{
			ActorId:        123,
			RepoId:         456,
			OwnerId:        789,
			IssueId:        999,
			AgentId:        int64(55555), // Non-existent agent ID
			BaseBranchName: "main",
		}

		resp, err := server.CreateJobForIssue(t.Context(), req)
		require.Error(t, err)
		require.Nil(t, resp)
		assert.Contains(t, err.Error(), "failed to find agentic app by ID")
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
	t.Run("uses GetAssignmentForPR when feature flag is off", func(t *testing.T) {
		ctx := t.Context()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentWorkOnCurrentBranch: false,
		})

		prID := int64(12345)
		assignment := &jobs.Assignment{
			ID:            "test-assignment-id",
			OwnerID:       789,
			RepoID:        456,
			PullRequestID: prID,
		}
		_, err := jobStore.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		testJob := &jobs.Job{
			ID:           "job-1234",
			AssignmentID: assignment.ID,
			OwnerID:      789,
			RepoID:       456,
		}
		_, err = jobStore.CreateJob(ctx, testJob)
		require.NoError(t, err)

		server := NewServer(observability.NewNoopExporters(), nil, nil, jobStore, nil, ffClient, agenticapptest.NewTestProvider(t))

		resp, err := server.ListJobsForPullRequest(ctx, &jobs_pb.ListJobsForPullRequestRequest{
			OwnerId:       789,
			RepoId:        456,
			PullRequestId: prID,
		})
		require.NoError(t, err)
		require.Len(t, resp.Jobs, 1)
		assert.Equal(t, testJob.ID, resp.Jobs[0].Id)
	})

	t.Run("uses GetAssignmentForResource when feature flag is on", func(t *testing.T) {
		ctx := t.Context()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentWorkOnCurrentBranch: true,
		})

		prID := int64(12345)
		assignment := &jobs.Assignment{
			ID:      "test-assignment-id",
			OwnerID: 789,
			RepoID:  456,
			Resources: []jobs.AssignmentResource{
				{Type: "pull_request", ID: strconv.FormatInt(prID, 10)},
			},
		}
		_, err := jobStore.CreateAssignment(ctx, assignment)
		require.NoError(t, err)

		testJob := &jobs.Job{
			ID:           "job-5678",
			AssignmentID: assignment.ID,
			OwnerID:      789,
			RepoID:       456,
		}
		_, err = jobStore.CreateJob(ctx, testJob)
		require.NoError(t, err)

		server := NewServer(observability.NewNoopExporters(), nil, nil, jobStore, nil, ffClient, agenticapptest.NewTestProvider(t))

		resp, err := server.ListJobsForPullRequest(ctx, &jobs_pb.ListJobsForPullRequestRequest{
			OwnerId:       789,
			RepoId:        456,
			PullRequestId: prID,
		})
		require.NoError(t, err)
		require.Len(t, resp.Jobs, 1)
		assert.Equal(t, testJob.ID, resp.Jobs[0].Id)
	})

	t.Run("returns not found when no assignment exists", func(t *testing.T) {
		ctx := t.Context()
		jobStore := memory.NewStore()
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		server := NewServer(observability.NewNoopExporters(), nil, nil, jobStore, nil, ffClient, agenticapptest.NewTestProvider(t))

		resp, err := server.ListJobsForPullRequest(ctx, &jobs_pb.ListJobsForPullRequestRequest{
			OwnerId:       789,
			RepoId:        456,
			PullRequestId: 99999,
		})
		require.Nil(t, resp)

		var twerr twirp.Error
		require.True(t, errors.As(err, &twerr))
		assert.Equal(t, twirp.NotFound, twerr.Code())
	})
}
