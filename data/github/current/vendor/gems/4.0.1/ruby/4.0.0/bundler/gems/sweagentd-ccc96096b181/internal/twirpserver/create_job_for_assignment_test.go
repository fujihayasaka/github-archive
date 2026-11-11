package twirpserver

import (
	"context"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
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
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	jobLimiter "github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func setupTestServer(t *testing.T) (*Server, *memory.Store, *aqueduct.MemoryClient, *githubtwirp.NoopClient) {
	t.Helper()

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
	limiter := jobLimiter.NewJobLimiter(jobStore, countTracker)
	exp := experiments.NewNoopClient()
	aq := aqueduct.NewMemoryClient(obsv)
	defaultCASvc := customagent.NewService(obsv, customagenttest.MakeSpokes(t, map[string]string{}), mockGhTwirp, ffClient)
	jobService := jobservice.New(obsv, ffClient, jobStore, capi.NewNoopClient(), ghf, mockGhTwirp, aq, limiter, exp, defaultCASvc, "test@example.com", spokestest.NewClient(t), agapp, nil)

	server := NewServer(obsv, ghf, mockGhTwirp, jobStore, jobService, ffClient, agapp)

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

		// Check that it's an error about assignment not found
		require.Contains(t, err.Error(), "failed to get assignment")
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

		// Check that it's an error about assignment not found
		require.Contains(t, err.Error(), "failed to get assignment")
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
		require.Contains(t, job.Model, "claude-sonnet", "new job should use the requested model, not inherit from previous job")

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
		// BaseCommit should be the branch name (not the original base commit) so the job
		// works on the tip of the existing branch rather than creating a new branch from the original base
		require.Equal(t, "copilot/fix-bug-123", job.BaseCommit,
			"follow-up job should use the branch name as BaseCommit to work on the existing branch")

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
}
