package jobevents

import (
	"testing"
	"time"

	"github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1/entities"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMapJob(t *testing.T) {
	t.Run("maps basic job fields correctly", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "job-123",
			AssignmentID:             "assignment-456",
			AgentID:                  12345,
			ActorID:                  789,
			ActorLogin:               "testuser",
			ActorDisplayLogin:        "testuser",
			ActorAnalyticsTrackingID: "tracking-123",
			Status:                   jobs.JobStatusRunning,
			RepoID:                   100,
			RepoNodeID:               "R_node123",
			OwnerID:                  200,
			OwnerNodeID:              "O_node456",
			EventType:                jobs.EventTypeIssueAssignment,
			EventURL:                 "https://github.com/owner/repo/issues/1",
			EventIdentifiers:         []string{"issue-1"},
			EventContent:             "Fix the bug",
			CreatedAt:                1700000000,
			QueuedAt:                 1700000100,
			LaunchedAt:               1700000200,
			CompletedAt:              1700000300,
			Title:                    "Fix authentication bug",
			ComputeID:                "12345678",
			Model:                    "gpt-4o",
			BranchName:               "copilot/fix-123",
			BaseCommit:               "main",
		}

		result := mapJob(job)

		assert.Equal(t, "job-123", result.Id)
		assert.Equal(t, "assignment-456", result.AssignmentId)
		assert.Equal(t, int64(12345), result.AgentId)
		assert.Equal(t, int64(789), result.Actor.Id)
		assert.Equal(t, "testuser", result.Actor.Login)
		assert.Equal(t, "testuser", result.Actor.DisplayLogin)
		assert.Equal(t, "tracking-123", result.Actor.AnalyticsTrackingId)
		assert.Equal(t, entities.JobStatus_RUNNING, result.Status)
		assert.Equal(t, int64(100), result.Repository.Id)
		assert.Equal(t, "R_node123", result.Repository.NodeId)
		assert.Equal(t, int64(200), result.Repository.OwnerId)
		assert.Equal(t, "O_node456", result.Repository.OwnerNodeId)
		assert.Equal(t, "issue_assignment", result.Event.Type)
		assert.Equal(t, "https://github.com/owner/repo/issues/1", result.Event.Url)
		assert.Equal(t, []string{"issue-1"}, result.Event.Identifiers)
		assert.Equal(t, "Fix the bug", result.Event.Content)
		assert.NotNil(t, result.CreatedAt)
		assert.NotNil(t, result.QueuedAt)
		assert.NotNil(t, result.StartedAt)
		assert.NotNil(t, result.CompletedAt)
		assert.Equal(t, "Fix authentication bug", result.Title)
		assert.Equal(t, "12345678", result.ComputeId)
		assert.Equal(t, "gpt-4o", result.Model)
		assert.Equal(t, "copilot/fix-123", result.HeadRef)
		assert.Equal(t, "main", result.BaseRef)
	})

	t.Run("maps job with error correctly", func(t *testing.T) {
		job := &jobs.Job{
			ID:     "job-with-error",
			Status: jobs.JobStatusFailed,
			Error: &jobs.JobError{
				ResponseStatusCode: "500",
				Message:            "Internal server error",
			},
		}

		result := mapJob(job)

		require.NotNil(t, result.Error)
		assert.Equal(t, "500", result.Error.Code)
		assert.Equal(t, "Internal server error", result.Error.Message)
	})

	t.Run("maps job with pull request correctly", func(t *testing.T) {
		job := &jobs.Job{
			ID:                "job-with-pr",
			PullRequestID:     12345,
			PullRequestNumber: 42,
		}

		result := mapJob(job)

		require.NotNil(t, result.PullRequest)
		assert.Equal(t, int64(12345), result.PullRequest.Id)
		assert.Equal(t, int32(42), result.PullRequest.Number)
	})

	t.Run("does not include pull request when not set", func(t *testing.T) {
		job := &jobs.Job{
			ID:                "job-without-pr",
			PullRequestID:     0,
			PullRequestNumber: 0,
		}

		result := mapJob(job)

		assert.Nil(t, result.PullRequest)
	})

	t.Run("maps job with custom agent correctly", func(t *testing.T) {
		job := &jobs.Job{
			ID:     "job-with-custom-agent",
			Status: jobs.JobStatusRunning,
			CustomAgent: customagent.DBRecord{
				Name:        "my-agent",
				Version:     "1.0.0",
				RepoID:      999,
				RepoOwnerID: 888,
				DisplayName: "My Agent",
				Description: "A test agent",
			},
		}

		result := mapJob(job)

		require.NotNil(t, result.CustomAgent)
		assert.Equal(t, "my-agent", result.CustomAgent.Name)
		assert.Equal(t, "1.0.0", result.CustomAgent.Version)
		assert.Equal(t, "My Agent", result.CustomAgent.DisplayName)
		assert.Equal(t, "A test agent", result.CustomAgent.Description)
		require.NotNil(t, result.CustomAgent.Repository)
		assert.Equal(t, int64(999), result.CustomAgent.Repository.Id)
		assert.Equal(t, int64(888), result.CustomAgent.Repository.OwnerId)
	})

	t.Run("does not include custom agent when not set", func(t *testing.T) {
		job := &jobs.Job{
			ID:          "job-without-custom-agent",
			Status:      jobs.JobStatusRunning,
			CustomAgent: customagent.DBRecord{},
		}

		result := mapJob(job)

		assert.Nil(t, result.CustomAgent)
	})

	t.Run("returns nil timestamps for zero values", func(t *testing.T) {
		job := &jobs.Job{
			ID:          "job-new",
			Status:      jobs.JobStatusPending,
			CreatedAt:   0,
			QueuedAt:    0,
			LaunchedAt:  0,
			CompletedAt: 0,
		}

		result := mapJob(job)

		assert.Nil(t, result.CreatedAt)
		assert.Nil(t, result.QueuedAt)
		assert.Nil(t, result.StartedAt)
		assert.Nil(t, result.CompletedAt)
	})
}

func TestMapJobStatus(t *testing.T) {
	testCases := []struct {
		input    jobs.JobStatus
		expected entities.JobStatus
	}{
		{jobs.JobStatusPending, entities.JobStatus_PENDING},
		{jobs.JobStatusQueued, entities.JobStatus_QUEUED},
		{jobs.JobStatusRunning, entities.JobStatus_RUNNING},
		{jobs.JobStatusCompleted, entities.JobStatus_COMPLETED},
		{jobs.JobStatusFailed, entities.JobStatus_FAILED},
		{jobs.JobStatusCancelled, entities.JobStatus_CANCELLED},
		{jobs.JobStatusTimedOut, entities.JobStatus_TIMED_OUT},
		{jobs.JobStatus("unknown"), entities.JobStatus_UNKNOWN},
		{jobs.JobStatus(""), entities.JobStatus_UNKNOWN},
	}

	for _, tc := range testCases {
		t.Run(string(tc.input), func(t *testing.T) {
			result := mapJobStatus(tc.input)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestMapActor(t *testing.T) {
	job := &jobs.Job{
		ActorID:                  123,
		ActorLogin:               "actor-login",
		ActorDisplayLogin:        "actor-display",
		ActorAnalyticsTrackingID: "analytics-id",
	}

	result := mapActor(job)

	assert.Equal(t, int64(123), result.Id)
	assert.Equal(t, "actor-login", result.Login)
	assert.Equal(t, "actor-display", result.DisplayLogin)
	assert.Equal(t, "analytics-id", result.AnalyticsTrackingId)
}

func TestMapRepository(t *testing.T) {
	job := &jobs.Job{
		RepoID:      100,
		RepoNodeID:  "R_node",
		OwnerID:     200,
		OwnerNodeID: "O_node",
	}

	result := mapRepository(job)

	assert.Equal(t, int64(100), result.Id)
	assert.Equal(t, "R_node", result.NodeId)
	assert.Equal(t, int64(200), result.OwnerId)
	assert.Equal(t, "O_node", result.OwnerNodeId)
}

func TestMapCustomAgent(t *testing.T) {
	t.Run("returns nil when no custom agent", func(t *testing.T) {
		job := &jobs.Job{
			CustomAgent: customagent.DBRecord{},
		}

		result := mapCustomAgent(job)

		assert.Nil(t, result)
	})

	t.Run("maps custom agent correctly", func(t *testing.T) {
		job := &jobs.Job{
			CustomAgent: customagent.DBRecord{
				Name:        "agent-name",
				Version:     "2.0.0",
				RepoID:      111,
				RepoOwnerID: 222,
				DisplayName: "Display Name",
				Description: "Agent description",
			},
		}

		result := mapCustomAgent(job)

		require.NotNil(t, result)
		assert.Equal(t, "agent-name", result.Name)
		assert.Equal(t, "2.0.0", result.Version)
		assert.Equal(t, "Display Name", result.DisplayName)
		assert.Equal(t, "Agent description", result.Description)
		require.NotNil(t, result.Repository)
		assert.Equal(t, int64(111), result.Repository.Id)
		assert.Equal(t, int64(222), result.Repository.OwnerId)
	})
}

func TestMapCustomAgentRepository(t *testing.T) {
	job := &jobs.Job{
		CustomAgent: customagent.DBRecord{
			RepoID:      333,
			RepoOwnerID: 444,
		},
	}

	result := mapCustomAgentRepository(job)

	assert.Equal(t, int64(333), result.Id)
	assert.Equal(t, int64(444), result.OwnerId)
	// NodeId and OwnerNodeId are not available in CustomAgent DBRecord
	assert.Empty(t, result.NodeId)
	assert.Empty(t, result.OwnerNodeId)
}

func TestMapEvent(t *testing.T) {
	job := &jobs.Job{
		EventType:        jobs.EventTypePullRequestComment,
		EventURL:         "https://github.com/org/repo/pull/1#comment-123",
		EventIdentifiers: []string{"comment-123", "pr-1"},
		EventContent:     "Please fix this issue",
	}

	result := mapEvent(job)

	assert.Equal(t, "pull_request_comment", result.Type)
	assert.Equal(t, "https://github.com/org/repo/pull/1#comment-123", result.Url)
	assert.Equal(t, []string{"comment-123", "pr-1"}, result.Identifiers)
	assert.Equal(t, "Please fix this issue", result.Content)
}

func TestMapJobError(t *testing.T) {
	jobError := &jobs.JobError{
		ResponseStatusCode: "404",
		Message:            "Resource not found",
	}

	result := mapJobError(jobError)

	assert.Equal(t, "404", result.Code)
	assert.Equal(t, "Resource not found", result.Message)
}

func TestMapPullRequest(t *testing.T) {
	job := &jobs.Job{
		PullRequestID:     99999,
		PullRequestNumber: 100,
	}

	result := mapPullRequest(job)

	assert.Equal(t, int64(99999), result.Id)
	assert.Equal(t, int32(100), result.Number)
}

func TestTimestampFromUnix(t *testing.T) {
	t.Run("returns nil for zero", func(t *testing.T) {
		result := timestampFromUnix(0)
		assert.Nil(t, result)
	})

	t.Run("converts unix timestamp correctly", func(t *testing.T) {
		// Use a known timestamp: 2023-11-15 12:00:00 UTC
		unixTime := int64(1700049600)
		result := timestampFromUnix(unixTime)

		require.NotNil(t, result)
		assert.Equal(t, unixTime, result.GetSeconds())
		assert.Equal(t, int32(0), result.GetNanos())
	})
}

func TestMapProgress(t *testing.T) {
	t.Run("returns nil for nil progress", func(t *testing.T) {
		result := mapProgress(nil)
		assert.Nil(t, result)
	})

	t.Run("maps progress correctly", func(t *testing.T) {
		createdAt := time.Date(2023, 11, 15, 12, 0, 0, 0, time.UTC)
		progress := &ProgressUpdate{
			Content:   []byte(`{"kind":"message","message":{"role":"assistant"}}`),
			Namespace: "sessions-legacy",
			Kind:      "log",
			Version:   "0",
			CreatedAt: createdAt,
		}

		result := mapProgress(progress)

		require.NotNil(t, result)
		assert.NotEmpty(t, result.Id) // UUID should be generated
		assert.Equal(t, "sessions-legacy", result.Namespace)
		assert.Equal(t, "log", result.Kind)
		assert.Equal(t, "0", result.Version)
		assert.JSONEq(t, `{"kind":"message","message":{"role":"assistant"}}`, string(result.Content))
		assert.Equal(t, createdAt.Unix(), result.CreatedAt.GetSeconds())
	})

	t.Run("generates unique IDs for each call", func(t *testing.T) {
		progress := &ProgressUpdate{
			Content:   []byte("test"),
			Namespace: "test-ns",
			Kind:      "test-kind",
			Version:   "1",
			CreatedAt: time.Now(),
		}

		result1 := mapProgress(progress)
		result2 := mapProgress(progress)

		require.NotNil(t, result1)
		require.NotNil(t, result2)
		assert.NotEqual(t, result1.Id, result2.Id)
	})
}

func TestMapJobWithAllEventTypes(t *testing.T) {
	eventTypes := []jobs.EventType{
		jobs.EventTypeIssueCreated,
		jobs.EventTypeIssueAssignment,
		jobs.EventTypePullRequestComment,
		jobs.EventTypePullRequestCommentNonCopilotPullRequest,
		jobs.EventTypePullRequestReview,
		jobs.EventTypePullRequestReviewNonCopilotPullRequest,
		jobs.EventTypeCodeScanningAlertsAssignment,
		jobs.EventTypeAPICallReceived,
		jobs.EventTypeSlack,
	}

	for _, eventType := range eventTypes {
		t.Run(string(eventType), func(t *testing.T) {
			job := &jobs.Job{
				ID:        "job-1",
				EventType: eventType,
			}

			result := mapJob(job)

			assert.Equal(t, string(eventType), result.Event.Type)
		})
	}
}
