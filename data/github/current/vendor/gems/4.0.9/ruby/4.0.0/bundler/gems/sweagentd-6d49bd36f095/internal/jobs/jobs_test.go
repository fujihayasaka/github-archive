package jobs

import (
	"encoding/json"
	"errors"
	"fmt"
	"testing"

	"github.com/github/sweagentd/internal/joberrors"
	"github.com/stretchr/testify/require"
)

// alwaysErrReader is an io.Reader that always returns an error, used to
// simulate crypto/rand failures in tests.
type alwaysErrReader struct{}

func (alwaysErrReader) Read(_ []byte) (int, error) {
	return 0, errors.New("mock rand error")
}

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
		nonce, err := GenerateNonce()
		require.NoError(t, err)
		require.NotEmpty(t, nonce)
		require.Len(t, nonce, 64, "Nonce should be 64 characters (32 bytes hex-encoded)")
	})

	t.Run("GenerateNonce returns error when crypto/rand fails", func(t *testing.T) {
		orig := randReader
		randReader = alwaysErrReader{}
		t.Cleanup(func() { randReader = orig })

		_, err := GenerateNonce()
		require.Error(t, err)
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

func TestCreateJobError(t *testing.T) {
	t.Run("extracts joberrors.JobError from error chain", func(t *testing.T) {
		inner := &joberrors.JobError{Service: "capi", Code: "429"}
		err := fmt.Errorf("outer: %w", inner)

		je := CreateJobError(err)
		require.Equal(t, "capi", je.Service)
		require.Equal(t, "429", je.ResponseStatusCode)
		require.Contains(t, je.Message, "capi:429")
	})

	t.Run("falls back to status code from marked error", func(t *testing.T) {
		err := errors.New("something broke")

		je := CreateJobError(err)
		require.Empty(t, je.Service)
		require.Equal(t, "500", je.ResponseStatusCode)
		require.Equal(t, "something broke", je.Message)
	})
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

func TestJob_ActorType(t *testing.T) {
	tests := []struct {
		name        string
		actorType   ActorType
		isOrgActor  bool
		isBillToOrg bool
	}{
		{
			name:        "org actor",
			actorType:   ActorTypeOrg,
			isOrgActor:  true,
			isBillToOrg: true,
		},
		{
			name:        "user actor",
			actorType:   ActorTypeUser,
			isOrgActor:  false,
			isBillToOrg: false,
		},
		{
			name:        "empty actor type defaults to user",
			actorType:   "",
			isOrgActor:  false,
			isBillToOrg: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			job := &Job{ActorType: tt.actorType}
			require.Equal(t, tt.isOrgActor, job.IsOrgActor())
			require.Equal(t, tt.isBillToOrg, job.IsBillToOrg())
		})
	}
}

func TestNewJob_AdditionalRepositories(t *testing.T) {
	tests := []struct {
		name                   string
		additionalRepositories []RepositoryRef
		want                   []RepositoryRef
	}{
		{
			name: "propagates AdditionalRepositories from assignment",
			additionalRepositories: []RepositoryRef{
				{RepoID: 10, OwnerID: 11, RepoNodeID: "repo-node-10", OwnerNodeID: "owner-node-11"},
				{RepoID: 20, OwnerID: 21, RepoNodeID: "repo-node-20", OwnerNodeID: "owner-node-21"},
			},
			want: []RepositoryRef{
				{RepoID: 10, OwnerID: 11, RepoNodeID: "repo-node-10", OwnerNodeID: "owner-node-11"},
				{RepoID: 20, OwnerID: 21, RepoNodeID: "repo-node-20", OwnerNodeID: "owner-node-21"},
			},
		},
		{
			name:                   "AdditionalRepositories is empty when not set on assignment",
			additionalRepositories: nil,
			want:                   nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assignment := NewAssignment(1, 2, "owner-node", "repo-node", "owner", "repo", false)
			assignment.AdditionalRepositories = tt.additionalRepositories
			actor := JobActor{ID: 123, Login: "testuser"}

			job := assignment.NewJob(AgentActionTask, actor, "abc123")

			require.NotNil(t, job)
			require.Equal(t, tt.want, job.AdditionalRepositories)
		})
	}
}

func TestNewJob_OrgActor(t *testing.T) {
	assignment := NewAssignment(100, 200, "owner-node", "repo-node", "test-org", "repo", false)
	orgActor := JobActor{
		ID:    100,
		Login: "test-org",
		Type:  ActorTypeOrg,
	}

	job := assignment.NewJob(AgentActionTask, orgActor, "abc123")

	require.NotNil(t, job)
	require.Equal(t, ActorTypeOrg, job.ActorType)
	require.Equal(t, int64(100), job.ActorID)
	require.Equal(t, "test-org", job.ActorLogin)
	require.True(t, job.IsOrgActor())
	require.True(t, job.IsBillToOrg())
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

func TestJob_WorkflowRunID(t *testing.T) {
	tests := []struct {
		name   string
		job    Job
		wantID int64
		wantOK bool
	}{
		{
			name:   "actions launcher with numeric ID",
			job:    Job{Launcher: "actions", ComputeID: "12345"},
			wantID: 12345,
			wantOK: true,
		},
		{
			name:   "empty launcher (legacy) with numeric ID",
			job:    Job{ComputeID: "12345"},
			wantID: 12345,
			wantOK: true,
		},
		{
			name:   "non-actions launcher returns ok=false even if numeric",
			job:    Job{Launcher: "sandbox", ComputeID: "12345"},
			wantOK: false,
		},
		{
			name:   "non-numeric compute ID returns ok=false",
			job:    Job{Launcher: "actions", ComputeID: "sb-abc"},
			wantOK: false,
		},
		{
			name:   "empty compute ID returns ok=false",
			job:    Job{Launcher: "actions"},
			wantOK: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			id, ok := tt.job.WorkflowRunID()
			require.Equal(t, tt.wantOK, ok)
			if ok {
				require.Equal(t, tt.wantID, id)
			}
		})
	}
}

func TestJob_IsActionsLauncher(t *testing.T) {
	require.True(t, (&Job{}).IsActionsLauncher())
	require.True(t, (&Job{Launcher: "actions"}).IsActionsLauncher())
	require.False(t, (&Job{Launcher: "sandbox"}).IsActionsLauncher())
	require.False(t, (&Job{Launcher: "docker"}).IsActionsLauncher())
}

func TestJob_ComputeType(t *testing.T) {
	require.Equal(t, "actions", (&Job{}).ComputeType())
	require.Equal(t, "actions", (&Job{Launcher: "actions"}).ComputeType())
	require.Equal(t, "sandbox", (&Job{Launcher: "sandbox"}).ComputeType())
	require.Equal(t, "docker", (&Job{Launcher: "docker"}).ComputeType())
}

// TestJob_CanWriteWorkflows_JSONRoundTrip guarantees that all three
// tri-state values of Job.CanWriteWorkflows survive a Cosmos round-trip
// (modeled here as a JSON round-trip). The launcher reads this field at
// LaunchAgent time, including on retries / relaunches, so we must not lose
// the original check result.
func TestJob_CanWriteWorkflows_JSONRoundTrip(t *testing.T) {
	truth := true
	falsehood := false

	tests := []struct {
		name          string
		value         *bool
		expectInJSON  bool
		expectedField string
	}{
		{
			name:          "nil is omitted from JSON",
			value:         nil,
			expectInJSON:  false,
			expectedField: "",
		},
		{
			name:          "true round-trips as true",
			value:         &truth,
			expectInJSON:  true,
			expectedField: `"can_write_workflows":true`,
		},
		{
			name:          "false round-trips as false",
			value:         &falsehood,
			expectInJSON:  true,
			expectedField: `"can_write_workflows":false`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			j := &Job{CanWriteWorkflows: tt.value}

			data, err := json.Marshal(j)
			require.NoError(t, err)

			if tt.expectInJSON {
				require.Contains(t, string(data), tt.expectedField)
			} else {
				require.NotContains(t, string(data), "can_write_workflows",
					"nil value must be omitted from JSON so FF-off jobs are byte-identical to today")
			}

			var decoded Job
			require.NoError(t, json.Unmarshal(data, &decoded))

			if tt.value == nil {
				require.Nil(t, decoded.CanWriteWorkflows)
			} else {
				require.NotNil(t, decoded.CanWriteWorkflows)
				require.Equal(t, *tt.value, *decoded.CanWriteWorkflows)
			}
		})
	}
}

// TestJob_CanWriteWorkflows_FFOffByteIdentity asserts that a job whose
// workflow-modification capability has not been checked (FF off / out-of-scope
// path) JSON-marshals byte-identically to a job that never had the field —
// the wire-level contract that guarantees zero behavioral change when the FF
// is off.
func TestJob_CanWriteWorkflows_FFOffByteIdentity(t *testing.T) {
	baseline := &Job{ID: "abc", OwnerID: 1, RepoID: 2}
	withNilField := &Job{ID: "abc", OwnerID: 1, RepoID: 2, CanWriteWorkflows: nil}

	baselineJSON, err := json.Marshal(baseline)
	require.NoError(t, err)
	withNilJSON, err := json.Marshal(withNilField)
	require.NoError(t, err)

	require.JSONEq(t, string(baselineJSON), string(withNilJSON),
		"unset *bool must marshal identically to a job with no such field")
	require.NotContains(t, string(baselineJSON), "can_write_workflows")
}

func TestInheritedWorkflowsAccess(t *testing.T) {
	const targetAgent int64 = 42
	const otherAgent int64 = 99
	trueVal := true
	falseVal := false

	t.Run("returns nil for nil list", func(t *testing.T) {
		require.Nil(t, InheritedWorkflowsAccess(nil, targetAgent))
	})

	t.Run("returns nil for empty slice", func(t *testing.T) {
		require.Nil(t, InheritedWorkflowsAccess([]*Job{}, targetAgent))
	})

	t.Run("returns nil when no same-agent job has a checked value", func(t *testing.T) {
		jobsList := []*Job{
			{ID: "job-1", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: nil},
			{ID: "job-2", CreatedAt: 200, AgentID: targetAgent, CanWriteWorkflows: nil},
		}
		require.Nil(t, InheritedWorkflowsAccess(jobsList, targetAgent))
	})

	t.Run("returns value from single matching job", func(t *testing.T) {
		jobsList := []*Job{
			{ID: "job-1", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
		}
		result := InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("ignores jobs from other agents", func(t *testing.T) {
		jobsList := []*Job{
			{ID: "job-1", CreatedAt: 500, AgentID: otherAgent, CanWriteWorkflows: &falseVal},
			{ID: "job-2", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
		}
		result := InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("returns most recent non-nil value from same agent", func(t *testing.T) {
		jobsList := []*Job{
			{ID: "oldest", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
			{ID: "newest", CreatedAt: 300, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
			{ID: "middle", CreatedAt: 200, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
		}
		result := InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("falls back to older non-nil value when newest is nil (stuck-nil mitigation)", func(t *testing.T) {
		jobsList := []*Job{
			{ID: "older", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
			{ID: "newest", CreatedAt: 500, AgentID: targetAgent, CanWriteWorkflows: nil},
		}
		result := InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.False(t, *result)
	})

	t.Run("skips nil entries in slice", func(t *testing.T) {
		jobsList := []*Job{
			nil,
			{ID: "job-1", CreatedAt: 100, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
			nil,
		}
		result := InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})
}
