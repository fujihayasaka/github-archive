package jobs

import (
	"context"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestClassifyJobFailure(t *testing.T) {
	tests := []struct {
		name     string
		job      *Job
		expected SLOFailureType
	}{
		{
			name:     "nil error returns unexpected",
			job:      &Job{Status: JobStatusFailed},
			expected: SLOFailureTypeUnexpected,
		},
		{
			name: "user_cancelled returns expected",
			job: &Job{
				Status: JobStatusCancelled,
				Error:  &JobError{ResponseStatusCode: "user_cancelled"},
			},
			expected: SLOFailureTypeExpected,
		},
		{
			name: "500 error returns unexpected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "500", Service: "sweagentd"},
			},
			expected: SLOFailureTypeUnexpected,
		},
		{
			name: "quota_exceeded returns expected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "quota_exceeded", Service: "CAPIError"},
			},
			expected: SLOFailureTypeExpected,
		},
		{
			name: "402 returns expected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "402", Service: "capi"},
			},
			expected: SLOFailureTypeExpected,
		},
		{
			name: "setup_steps returns expected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "setup_steps", Service: "actions"},
			},
			expected: SLOFailureTypeExpected,
		},
		{
			name: "unknown code returns unexpected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "some_unknown_error"},
			},
			expected: SLOFailureTypeUnexpected,
		},
		{
			name: "429 returns expected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "429", Service: "capi"},
			},
			expected: SLOFailureTypeExpected,
		},
		{
			name: "rate_limit_exceeded returns expected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "rate_limit_exceeded", Service: "sweagentd"},
			},
			expected: SLOFailureTypeExpected,
		},
		{
			name: "timed_out returns unexpected",
			job: &Job{
				Status: JobStatusTimedOut,
				Error:  &JobError{ResponseStatusCode: "timed_out", Service: "actions"},
			},
			expected: SLOFailureTypeUnexpected,
		},
		{
			name: "launch_failure returns unexpected",
			job: &Job{
				Status: JobStatusFailed,
				Error:  &JobError{ResponseStatusCode: "launch_failure", Service: "actions"},
			},
			expected: SLOFailureTypeUnexpected,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := ClassifyJobFailure(tc.job)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestStatJobCompletionSLO(t *testing.T) {
	ctx := context.Background()

	t.Run("completed job emits success", func(t *testing.T) {
		var capturedKey string
		var capturedTags stats.Tags

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				capturedKey = key
				capturedTags = tags
			},
		}

		job := &Job{
			Status: JobStatusCompleted,
		}

		StatJobCompletionSLO(ctx, obsv, stats.Tags{}, job)

		require.Equal(t, "jobs.completion", capturedKey)
		assert.Equal(t, "completed", capturedTags["status"])
		assert.Equal(t, "success", capturedTags["slo_result"])
		assert.Empty(t, capturedTags["failure_type"])
		assert.Empty(t, capturedTags["error_service"])
		assert.Empty(t, capturedTags["error_code"])
	})

	t.Run("failed job with excluded error emits expected failure", func(t *testing.T) {
		var capturedKey string
		var capturedTags stats.Tags

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				capturedKey = key
				capturedTags = tags
			},
		}

		job := &Job{
			Status: JobStatusFailed,
			Error: &JobError{
				Service:            "capi",
				ResponseStatusCode: "402",
				Message:            "Payment required",
			},
		}

		StatJobCompletionSLO(ctx, obsv, stats.Tags{}, job)

		require.Equal(t, "jobs.completion", capturedKey)
		assert.Equal(t, "failed", capturedTags["status"])
		assert.Equal(t, "failure", capturedTags["slo_result"])
		assert.Equal(t, "expected", capturedTags["failure_type"])
		assert.Equal(t, "capi", capturedTags["error_service"])
		assert.Equal(t, "402", capturedTags["error_code"])
	})

	t.Run("failed job with non-excluded error emits unexpected failure", func(t *testing.T) {
		var capturedKey string
		var capturedTags stats.Tags

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				capturedKey = key
				capturedTags = tags
			},
		}

		job := &Job{
			Status: JobStatusFailed,
			Error: &JobError{
				Service:            "sweagentd",
				ResponseStatusCode: "500",
				Message:            "Internal error",
			},
		}

		StatJobCompletionSLO(ctx, obsv, stats.Tags{}, job)

		require.Equal(t, "jobs.completion", capturedKey)
		assert.Equal(t, "failed", capturedTags["status"])
		assert.Equal(t, "failure", capturedTags["slo_result"])
		assert.Equal(t, "unexpected", capturedTags["failure_type"])
		assert.Equal(t, "sweagentd", capturedTags["error_service"])
		assert.Equal(t, "500", capturedTags["error_code"])
	})

	t.Run("cancelled job emits success", func(t *testing.T) {
		var capturedKey string
		var capturedTags stats.Tags

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				capturedKey = key
				capturedTags = tags
			},
		}

		job := &Job{
			Status: JobStatusCancelled,
			Error: &JobError{
				Service:            "sweagentd",
				ResponseStatusCode: "user_cancelled",
			},
		}

		StatJobCompletionSLO(ctx, obsv, stats.Tags{}, job)

		require.Equal(t, "jobs.completion", capturedKey)
		assert.Equal(t, "cancelled", capturedTags["status"])
		assert.Equal(t, "success", capturedTags["slo_result"])
		assert.Empty(t, capturedTags["failure_type"])
	})

	t.Run("timed_out job emits unexpected failure", func(t *testing.T) {
		var capturedKey string
		var capturedTags stats.Tags

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				capturedKey = key
				capturedTags = tags
			},
		}

		job := &Job{
			Status: JobStatusTimedOut,
			Error: &JobError{
				Service:            "actions",
				ResponseStatusCode: "timed_out",
			},
		}

		StatJobCompletionSLO(ctx, obsv, stats.Tags{}, job)

		require.Equal(t, "jobs.completion", capturedKey)
		assert.Equal(t, "timed_out", capturedTags["status"])
		assert.Equal(t, "failure", capturedTags["slo_result"])
		assert.Equal(t, "unexpected", capturedTags["failure_type"])
	})

	t.Run("non-terminal job does not emit", func(t *testing.T) {
		called := false

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				called = true
			},
		}

		for _, status := range []JobStatus{JobStatusPending, JobStatusQueued, JobStatusRunning} {
			job := &Job{Status: status}
			StatJobCompletionSLO(ctx, obsv, stats.Tags{}, job)
			assert.False(t, called, "should not emit for status %s", status)
		}
	})

	t.Run("preserves base tags", func(t *testing.T) {
		var capturedTags stats.Tags

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				capturedTags = tags
			},
		}

		baseTags := stats.Tags{
			"repo_id":  "123",
			"owner_id": "456",
		}

		job := &Job{Status: JobStatusCompleted}

		StatJobCompletionSLO(ctx, obsv, baseTags, job)

		assert.Equal(t, "123", capturedTags["repo_id"])
		assert.Equal(t, "456", capturedTags["owner_id"])
		assert.Equal(t, "completed", capturedTags["status"])
	})

	t.Run("failure without error still classifies as unexpected", func(t *testing.T) {
		var capturedTags stats.Tags

		obsv := observability.NewNoopExporters()
		obsv.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, value int64) {
				capturedTags = tags
			},
		}

		job := &Job{
			Status: JobStatusFailed,
			Error:  nil,
		}

		StatJobCompletionSLO(ctx, obsv, stats.Tags{}, job)

		assert.Equal(t, "failed", capturedTags["status"])
		assert.Equal(t, "failure", capturedTags["slo_result"])
		assert.Equal(t, "unexpected", capturedTags["failure_type"])
		assert.Empty(t, capturedTags["error_service"])
		assert.Empty(t, capturedTags["error_code"])
	})
}
