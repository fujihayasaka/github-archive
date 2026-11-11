package jobutils

import (
	"context"
	"errors"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/aqueduct"
"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/observability"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

var mockTwirpClientForEnterpriseUser = newMockTwirpClientWithUserDetails(&copilotUsersTwirp.CopilotUserDetails{
	CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
})

// newMockTwirpClientWithUserDetails returns a mock githubtwirp.ClientInterface that returns a response for GetCopilotUser
// with the provided CopilotUserDetails.
func newMockTwirpClientWithUserDetails(userDetails *copilotUsersTwirp.CopilotUserDetails) githubtwirp.ClientInterface {
	client := githubtwirp.NewNoopClient()
	client.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: userDetails,
		}, nil
	}

	return client
}

func TestGetWorkflowDetails(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	jobsStore := memory.NewStore()
	limiter := &noopLimiter{}

	t.Run("detects timeout from annotations and sets timed_out status", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "test-job-timeout",
			OwnerID:   1,
			RepoID:    2,
			Status:    jobs.JobStatusRunning,
			RepoName:  "test-repo",
			RepoOwner: "test-owner",
		}
		jobsStore.CreateJob(ctx, job)
		twirp := mockTwirpClientForEnterpriseUser

		workflowJobID := int64(12345)
		workflowJob := &gg.WorkflowJob{
			ID:         &workflowJobID,
			Conclusion: stringPtr("cancelled"),
		}
		gh := &github.NoopClient{
			MockListCheckRunAnnotations: func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
				return []*gg.CheckRunAnnotation{
					{
						AnnotationLevel: stringPtr("failure"),
						Message:         stringPtr("The job has exceeded the maximum execution time of 1m0s"),
					},
				}, nil
			},
		}

		// Use comprehensive analysis to get job status and other details
		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, job, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t))
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusTimedOut, updatedJob.Status)
	})

	t.Run("sets cancelled status for cancelled without timeout annotation", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "test-job-cancelled",
			OwnerID:   1,
			RepoID:    2,
			Status:    jobs.JobStatusRunning,
			RepoName:  "test-repo",
			RepoOwner: "test-owner",
		}
		jobsStore.CreateJob(ctx, job)
		twirp := mockTwirpClientForEnterpriseUser

		workflowJobID := int64(12346)
		workflowJob := &gg.WorkflowJob{
			ID:         &workflowJobID,
			Conclusion: stringPtr("cancelled"),
		}
		gh := &github.NoopClient{
			MockListCheckRunAnnotations: func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
				return []*gg.CheckRunAnnotation{
					{
						AnnotationLevel: stringPtr("failure"),
						Message:         stringPtr("The run was canceled by @user"),
					},
				}, nil
			},
		}

		// Use comprehensive analysis to get job status and other details
		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, job, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t))
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
	})

	t.Run("detect custom setup step failures and set error code/message accordingly", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "test-job-failed",
			OwnerID:   1,
			RepoID:    2,
			Status:    jobs.JobStatusRunning,
			RepoName:  "test-repo",
			RepoOwner: "test-owner",
		}
		jobsStore.CreateJob(ctx, job)
		twirp := mockTwirpClientForEnterpriseUser

		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Custom step"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		workflowDetails, err := GetWorkflowDetails(ctx, obsv, &github.NoopClient{}, job, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		require.Equal(t, joberrors.ErrorActionsSetupSteps.String(), workflowDetails.ErrorCode)
		require.Equal(t, "The \"Custom step\" custom setup step from your .github/workflows/copilot-setup-steps.yml file failed.", workflowDetails.ErrorMessage)

		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t))
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})

	t.Run("handles annotation fetch error gracefully", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "test-job-error",
			OwnerID:   1,
			RepoID:    2,
			Status:    jobs.JobStatusRunning,
			RepoName:  "test-repo",
			RepoOwner: "test-owner",
		}
		jobsStore.CreateJob(ctx, job)
		twirp := mockTwirpClientForEnterpriseUser

		workflowJobID := int64(12347)
		workflowJob := &gg.WorkflowJob{
			ID:         &workflowJobID,
			Conclusion: stringPtr("cancelled"),
		}
		gh := &github.NoopClient{
			MockListCheckRunAnnotations: func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
				return nil, errors.New("failed to fetch annotations")
			},
		}

		// Use comprehensive analysis to get job status and other details
		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, job, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t))
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
	})
}

func TestGetFailedSteps(t *testing.T) {
	t.Run("returns empty when workflow job is nil", func(t *testing.T) {
		steps, errorCode, errorMessage := getFailedSteps(nil)
		require.Empty(t, steps)
		require.Empty(t, errorCode)
		require.Empty(t, errorMessage)
	})

	t.Run("returns empty when no steps failed", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("success"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate runner OS"),
					Conclusion: stringPtr("success"),
				},
				{
					Name:       stringPtr("Processing Request"),
					Conclusion: stringPtr("success"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Empty(t, steps)
		require.Empty(t, errorCode)
		require.Empty(t, errorMessage)
	})

	t.Run("detects failed steps without error message", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate runner OS"),
					Conclusion: stringPtr("success"),
				},
				{
					Name:       stringPtr("Processing Request"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Processing Request", steps[0].GetName())
		require.Empty(t, errorCode)
		require.Empty(t, errorMessage)
	})

	t.Run("detects Validate runner OS not-supported step", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate runner OS"),
					Conclusion: stringPtr("failure"),
				},
				{
					Name:       stringPtr("Processing Request"),
					Conclusion: stringPtr("success"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Validate runner OS", steps[0].GetName())
		require.Equal(t, joberrors.ErrorActionsNotSupported.String(), errorCode)
		require.Contains(t, errorMessage, "Only Linux runners are supported.")
	})

	t.Run("detects firewall validation not-supported step", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate firewall settings"),
					Conclusion: stringPtr("failure"),
				},
				{
					Name:       stringPtr("Processing Request"),
					Conclusion: stringPtr("success"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Validate firewall settings", steps[0].GetName())
		require.Equal(t, joberrors.ErrorActionsNotSupported.String(), errorCode)
		require.Contains(t, errorMessage, "You must disable the agent firewall in the repository's settings to use self-hosted runners.")
	})

	t.Run("sets error message for not-supported steps", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate runner OS"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Validate runner OS", steps[0].GetName())
		require.Equal(t, joberrors.ErrorActionsNotSupported.String(), errorCode)
		require.Contains(t, errorMessage, "Only Linux runners are supported.")
	})

	t.Run("prioritizes first failed not-supported step when multiple steps fail", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate runner OS"),
					Conclusion: stringPtr("failure"),
				},
				{
					Name:       stringPtr("Validate firewall settings"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 2)
		// Should return error for the first failed step found in iteration order
		require.Equal(t, joberrors.ErrorActionsNotSupported.String(), errorCode)
		require.Contains(t, errorMessage, "Only Linux runners are supported.")
	})

	t.Run("detects custom setup step failure", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Custom Setup Step"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Custom Setup Step", steps[0].GetName())
		require.Equal(t, joberrors.ErrorActionsSetupSteps.String(), errorCode)
		require.Equal(t, "The \"Custom Setup Step\" custom setup step from your .github/workflows/copilot-setup-steps.yml file failed.", errorMessage)
	})

	t.Run("does not set error message for successful workflow", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("success"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate runner OS"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1) // Still detects failed steps
		require.Empty(t, errorCode)
		require.Empty(t, errorMessage)
	})
}

// Helper function to create string pointers
func stringPtr(s string) *string {
	return &s
}

// noopLimiter implements limiter interface for testing
type noopLimiter struct{}

func (n *noopLimiter) QueuedJobsExceeded(ctx context.Context, actorID int64) bool { return false }
func (n *noopLimiter) IncrementQueuedJobs(ctx context.Context, actorID int64)     {}
func (n *noopLimiter) DecrementQueuedJobs(ctx context.Context, actorID int64)     {}
func (n *noopLimiter) DecrementRunningJobs(ctx context.Context, actorID int64)    {}
func (n *noopLimiter) IncrementRunningJobs(ctx context.Context, actorID int64)    {}
