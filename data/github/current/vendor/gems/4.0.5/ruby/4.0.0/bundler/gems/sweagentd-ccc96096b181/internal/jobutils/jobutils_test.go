package jobutils

import (
	"context"
	"errors"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
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
	"github.com/github/sweagentd/internal/spokes/spokestest"
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
			ID:      "test-job-timeout",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
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

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		// Use comprehensive analysis to get job status and other details
		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, ffClient, job, repo, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, workflowDetails.ToJobError(), 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusTimedOut, updatedJob.Status)
	})

	t.Run("sets cancelled status for cancelled without timeout annotation", func(t *testing.T) {
		job := &jobs.Job{
			ID:      "test-job-cancelled",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
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

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		// Use comprehensive analysis to get job status and other details
		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, ffClient, job, repo, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, workflowDetails.ToJobError(), 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, updatedJob.Status)
		require.Equal(t, joberrors.ErrUserCancelled.Code, updatedJob.Error.ResponseStatusCode)
		require.Equal(t, "The session was cancelled by the user.", updatedJob.Error.Message)
	})

	t.Run("detect custom setup step failures and set error code/message accordingly", func(t *testing.T) {
		job := &jobs.Job{
			ID:      "test-job-failed",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
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

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		workflowDetails, err := GetWorkflowDetails(ctx, obsv, &github.NoopClient{}, ffClient, job, repo, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		require.Equal(t, joberrors.ErrActionsSetupSteps.String(), workflowDetails.ErrorCode)
		require.Equal(t, "The \"Custom step\" custom setup step from your .github/workflows/copilot-setup-steps.yml file failed.", workflowDetails.ErrorMessage)

		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, workflowDetails.ToJobError(), 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
	})

	t.Run("detects billing locked from annotations and sets error code", func(t *testing.T) {
		job := &jobs.Job{
			ID:      "test-job-billing-locked",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		jobsStore.CreateJob(ctx, job)
		twirp := mockTwirpClientForEnterpriseUser

		workflowJobID := int64(12350)
		workflowJob := &gg.WorkflowJob{
			ID:         &workflowJobID,
			Conclusion: stringPtr("failure"),
			Steps:      []*gg.TaskStep{}, // empty steps - workflow failed before any steps ran
		}
		gh := &github.NoopClient{
			MockListCheckRunAnnotations: func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
				return []*gg.CheckRunAnnotation{
					{
						AnnotationLevel: stringPtr("failure"),
						Message:         stringPtr("The job was not started because your account is locked due to a billing issue."),
					},
				}, nil
			},
		}

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, ffClient, job, repo, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, workflowDetails.JobStatus)
		require.Equal(t, joberrors.ErrActionsBillingLocked.String(), workflowDetails.ErrorCode)
		require.Equal(t, "The job was not started because the account is locked due to a billing issue.", workflowDetails.ErrorMessage)

		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, workflowDetails.ToJobError(), 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
		require.Equal(t, joberrors.ErrActionsBillingLocked.Code, updatedJob.Error.ResponseStatusCode)
	})

	t.Run("detects exit code 143 from annotations and sets terminated error", func(t *testing.T) {
		job := &jobs.Job{
			ID:      "test-job-terminated",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
		}
		jobsStore.CreateJob(ctx, job)
		twirp := mockTwirpClientForEnterpriseUser

		workflowJobID := int64(12351)
		workflowJob := &gg.WorkflowJob{
			ID:         &workflowJobID,
			Conclusion: stringPtr("failure"),
			Steps:      []*gg.TaskStep{},
		}
		gh := &github.NoopClient{
			MockListCheckRunAnnotations: func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
				return []*gg.CheckRunAnnotation{
					{
						AnnotationLevel: stringPtr("failure"),
						Message:         stringPtr("Processing Request (Linux)\nProcess completed with exit code 143."),
					},
				}, nil
			},
		}

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, ffClient, job, repo, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, workflowDetails.JobStatus)
		require.Equal(t, joberrors.ErrActionsTerminated.String(), workflowDetails.ErrorCode)
		require.Equal(t, "The agent was terminated unexpectedly (exit code 143). This typically indicates the job was forcefully stopped.", workflowDetails.ErrorMessage)

		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, workflowDetails.ToJobError(), 1234567890)
		require.NoError(t, err)

		updatedJob, err := jobsStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status)
		require.Equal(t, joberrors.ErrActionsTerminated.Code, updatedJob.Error.ResponseStatusCode)
	})

	t.Run("handles annotation fetch error gracefully", func(t *testing.T) {
		job := &jobs.Job{
			ID:      "test-job-error",
			OwnerID: 1,
			RepoID:  2,
			Status:  jobs.JobStatusRunning,
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

		repoOwner := "test-owner"
		repoName := "test-repo"
		repo := &gg.Repository{
			Owner: &gg.User{
				Login: &repoOwner,
			},
			Name: &repoName,
		}

		// Use comprehensive analysis to get job status and other details
		workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, ffClient, job, repo, workflowJob, jobs.JobStatusFailed)
		require.NoError(t, err)
		service := jobservice.New(obsv, ffClient, jobsStore, capi.NewNoopClient(), &github.NoopClientFactory{}, twirp, aqueduct.NewMemoryClient(obsv), limiter, experiments.NewNoopClient(), nil, "test@example.com", spokestest.NewClient(t), agenticapptest.NewTestProvider(t), nil)
		err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, workflowDetails.ToJobError(), 1234567890)
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
					Name:       stringPtr("Processing Request (Linux)"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Processing Request (Linux)", steps[0].GetName())
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
					Name:       stringPtr("Processing Request (Linux)"),
					Conclusion: stringPtr("success"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Validate runner OS", steps[0].GetName())
		require.Equal(t, joberrors.ErrActionsNotSupported.String(), errorCode)
		require.Contains(t, errorMessage, "Only Linux and Windows runners are supported.")
	})

	t.Run("detects firewall validation not-supported step (Linux)", func(t *testing.T) {
		workflowJob := &gg.WorkflowJob{
			Conclusion: stringPtr("failure"),
			Steps: []*gg.TaskStep{
				{
					Name:       stringPtr("Validate firewall settings (Linux)"),
					Conclusion: stringPtr("failure"),
				},
				{
					Name:       stringPtr("Processing Request (Linux)"),
					Conclusion: stringPtr("success"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 1)
		require.Equal(t, "Validate firewall settings (Linux)", steps[0].GetName())
		require.Equal(t, joberrors.ErrActionsNotSupported.String(), errorCode)
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
		require.Equal(t, joberrors.ErrActionsNotSupported.String(), errorCode)
		require.Contains(t, errorMessage, "Only Linux and Windows runners are supported.")
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
					Name:       stringPtr("Validate firewall settings (Linux)"),
					Conclusion: stringPtr("failure"),
				},
			},
		}

		steps, errorCode, errorMessage := getFailedSteps(workflowJob)
		require.Len(t, steps, 2)
		// Should return error for the first failed step found in iteration order
		require.Equal(t, joberrors.ErrActionsNotSupported.String(), errorCode)
		require.Contains(t, errorMessage, "Only Linux and Windows runners are supported.")
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
		require.Equal(t, joberrors.ErrActionsSetupSteps.String(), errorCode)
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

func TestToJobError(t *testing.T) {
	tests := []struct {
		name     string
		details  *WorkflowJobDetails
		expected *jobs.JobError
	}{
		{
			name:     "nil WorkflowJobDetails returns nil",
			details:  nil,
			expected: nil,
		},
		{
			name:     "empty error code and message returns nil",
			details:  &WorkflowJobDetails{},
			expected: nil,
		},
		{
			name: "error code without service prefix",
			details: &WorkflowJobDetails{
				ErrorCode:    "some_error",
				ErrorMessage: "Some error occurred",
			},
			expected: &jobs.JobError{
				Service:            "",
				ResponseStatusCode: "some_error",
				Message:            "Some error occurred",
			},
		},
		{
			name: "error code with service prefix",
			details: &WorkflowJobDetails{
				ErrorCode:    "capi:429",
				ErrorMessage: "Rate limited",
			},
			expected: &jobs.JobError{
				Service:            "capi",
				ResponseStatusCode: "429",
				Message:            "Rate limited",
			},
		},
		{
			name: "error code with multiple colons uses first as separator",
			details: &WorkflowJobDetails{
				ErrorCode:    "service:code:extra",
				ErrorMessage: "Error with colons",
			},
			expected: &jobs.JobError{
				Service:            "service",
				ResponseStatusCode: "code:extra",
				Message:            "Error with colons",
			},
		},
		{
			name: "empty error message uses default message",
			details: &WorkflowJobDetails{
				ErrorCode:    "actions:timed_out",
				ErrorMessage: "",
			},
			expected: &jobs.JobError{
				Service:            "actions",
				ResponseStatusCode: "timed_out",
				Message:            DefaultSessionErrorMessage,
			},
		},
		{
			name: "only error message provided",
			details: &WorkflowJobDetails{
				ErrorCode:    "",
				ErrorMessage: "Custom error message",
			},
			expected: &jobs.JobError{
				Service:            "",
				ResponseStatusCode: "",
				Message:            "Custom error message",
			},
		},
		{
			name: "only error code provided uses default message",
			details: &WorkflowJobDetails{
				ErrorCode:    "capi:500",
				ErrorMessage: "",
			},
			expected: &jobs.JobError{
				Service:            "capi",
				ResponseStatusCode: "500",
				Message:            DefaultSessionErrorMessage,
			},
		},
		{
			name: "actions setup steps error",
			details: &WorkflowJobDetails{
				ErrorCode:    joberrors.ErrActionsSetupSteps.String(),
				ErrorMessage: "The \"Custom step\" custom setup step from your .github/workflows/copilot-setup-steps.yml file failed.",
			},
			expected: &jobs.JobError{
				Service:            "actions",
				ResponseStatusCode: "setup_steps",
				Message:            "The \"Custom step\" custom setup step from your .github/workflows/copilot-setup-steps.yml file failed.",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.details.ToJobError()
			if tt.expected == nil {
				require.Nil(t, result)
			} else {
				require.NotNil(t, result)
				require.Equal(t, tt.expected.Service, result.Service)
				require.Equal(t, tt.expected.ResponseStatusCode, result.ResponseStatusCode)
				require.Equal(t, tt.expected.Message, result.Message)
			}
		})
	}
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
