package jobs

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewAssignment_UseAsyncSessions(t *testing.T) {
	t.Run("UseAsyncSessions set to true", func(t *testing.T) {
		assignment := NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", true)
		require.NotNil(t, assignment)
		require.True(t, assignment.UseAsyncSessions, "UseAsyncSessions should be true")
		require.Equal(t, int64(1), assignment.OwnerID)
		require.Equal(t, int64(2), assignment.RepoID)
	})

	t.Run("UseAsyncSessions set to false", func(t *testing.T) {
		assignment := NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", false)
		require.NotNil(t, assignment)
		require.False(t, assignment.UseAsyncSessions, "UseAsyncSessions should be false")
	})

	t.Run("UseAsyncSessions with resources", func(t *testing.T) {
		resource := AssignmentResource{Type: "issue", ID: "123"}
		assignment := NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", true, resource)
		require.NotNil(t, assignment)
		require.True(t, assignment.UseAsyncSessions)
		require.Len(t, assignment.Resources, 1)
		require.Equal(t, "issue", assignment.Resources[0].Type)
	})
}

func TestJobNonceGeneration(t *testing.T) {
	t.Run("GenerateNonce produces correct length", func(t *testing.T) {
		nonce := GenerateNonce()
		require.NotEmpty(t, nonce)
		require.Len(t, nonce, 64, "Nonce should be 64 characters (32 bytes hex-encoded)")
	})
}

func TestJobErrorSummary(t *testing.T) {
	tests := []struct {
		name     string
		jobError *JobError
		want     string
	}{
		{
			name:     "empty error",
			jobError: &JobError{},
			want:     "",
		},
		{
			name: "service only",
			jobError: &JobError{
				Service: "github",
			},
			want: "github",
		},
		{
			name: "status code only",
			jobError: &JobError{
				ResponseStatusCode: "500",
			},
			want: "500",
		},
		{
			name: "service and status code",
			jobError: &JobError{
				Service:            "github",
				ResponseStatusCode: "500",
			},
			want: "github:500",
		},
		{
			name: "message is not included in summary",
			jobError: &JobError{
				Message:            "something went wrong",
				Service:            "api",
				ResponseStatusCode: "404",
			},
			want: "api:404",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.jobError.Summary()
			require.Equal(t, tt.want, got)
		})
	}
}

func TestNewJob_SessionID(t *testing.T) {
	t.Run("SessionID is a new UUID when UseAsyncSessions is true", func(t *testing.T) {
		assignment := NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", true)
		actor := JobActor{
			ID:         123,
			Login:      "testuser",
			TrackingID: "tracking-id",
		}

		job := assignment.NewJob(AgentActionTask, actor, "abc123")

		require.NotNil(t, job)
		require.True(t, job.UseAsyncSessions, "UseAsyncSessions should be true")
		require.NotEmpty(t, job.SessionID, "SessionID should not be empty")
		require.NotEqual(t, job.ID, job.SessionID, "SessionID should be a separate UUID from job ID")
		// Verify SessionID is a valid UUID format (36 chars with hyphens)
		require.Len(t, job.SessionID, 36, "SessionID should be a UUID")
	})

	t.Run("SessionID is empty when UseAsyncSessions is false", func(t *testing.T) {
		assignment := NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", false)
		actor := JobActor{
			ID:         123,
			Login:      "testuser",
			TrackingID: "tracking-id",
		}

		job := assignment.NewJob(AgentActionTask, actor, "abc123")

		require.NotNil(t, job)
		require.False(t, job.UseAsyncSessions, "UseAsyncSessions should be false")
		require.Empty(t, job.SessionID, "SessionID should be empty when UseAsyncSessions is false")
	})
}

func TestRefName(t *testing.T) {
	t.Run("returns full ref name when BranchName is a full ref", func(t *testing.T) {
		job := Job{
			BranchName: "refs/heads/main",
			Features: EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "not-me",
				},
				Branch: &BranchFeature{
					Name: "also-not-me",
				},
			},
		}
		require.Equal(t, "refs/heads/main", job.RefName())
	})

	t.Run("returns full ref name when BranchName is a short name", func(t *testing.T) {
		job := Job{
			BranchName: "feature-branch",
		}
		require.Equal(t, "refs/heads/feature-branch", job.RefName())
	})

	t.Run("returns full ref name when using a nonstandard namespace", func(t *testing.T) {
		job := Job{
			Features: EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "refs/copilot/v1.0.0",
				},
			},
		}
		require.Equal(t, "refs/copilot/v1.0.0", job.RefName())
	})

	t.Run("returns Branch name when BranchName is empty", func(t *testing.T) {
		job := Job{
			Features: EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "not-me",
				},
				Branch: &BranchFeature{
					Name: "branch-name",
				},
			},
		}
		require.Equal(t, "refs/heads/branch-name", job.RefName())
	})

	t.Run("returns Branch name when both BranchName and PR head ref are empty", func(t *testing.T) {
		job := Job{
			Features: EnvironmentFeatures{
				Branch: &BranchFeature{
					Name: "branch-name",
				},
			},
		}
		require.Equal(t, "refs/heads/branch-name", job.RefName())
	})

	t.Run("returns empty string when no ref information is available", func(t *testing.T) {
		job := Job{}
		require.Equal(t, "", job.RefName())
	})
}
