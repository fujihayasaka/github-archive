package events

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

// TestEmitWorkflowRunMetrics_TagSelection verifies session_error_code is taken
// from job.Error (async path) with fallback to session.Error.Code (sync path).
func TestEmitWorkflowRunMetrics_TagSelection(t *testing.T) {
	tests := []struct {
		name       string
		job        *jobs.Job
		session    *capi.Session
		wantTagVal string
	}{
		{
			name:       "prefers job.Error.Summary when populated",
			job:        &jobs.Job{Error: &jobs.JobError{Service: "capi", ResponseStatusCode: "429"}},
			session:    &capi.Session{Error: &capi.SessionError{Code: "git:500"}},
			wantTagVal: "capi:429",
		},
		{
			name:       "falls back to session.Error.Code when job.Error empty",
			job:        &jobs.Job{},
			session:    &capi.Session{Error: &capi.SessionError{Code: "git:500"}},
			wantTagVal: "git:500",
		},
		{
			name:       "empty when neither is set",
			job:        &jobs.Job{},
			session:    &capi.Session{},
			wantTagVal: "",
		},
		{
			name:       "tolerates nil job",
			job:        nil,
			session:    &capi.Session{Error: &capi.SessionError{Code: "git:500"}},
			wantTagVal: "git:500",
		},
		{
			name:       "tolerates nil session with populated job.Error",
			job:        &jobs.Job{Error: &jobs.JobError{Service: "capi", ResponseStatusCode: "429"}},
			session:    nil,
			wantTagVal: "capi:429",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			calls := []stepMetricsDistributionCall{}
			obsv := observability.NewNoopExporters()
			obsv.Statter = &stepMetricsTestStatter{calls: &calls}
			h := &Handler{obsv: obsv}

			run := &WorkflowRun{Conclusion: "failure", UsageMs: 1234}
			h.emitWorkflowRunMetrics(context.Background(), tt.job, tt.session, run, 42, "copilot", nil)

			require.Len(t, calls, 1)
			require.Equal(t, "dynamic_workflow_completed", calls[0].key)
			require.Equal(t, tt.wantTagVal, calls[0].tags["session_error_code"])
			require.Equal(t, "not_reached", calls[0].tags["processing_request_conclusion"])
		})
	}
}
