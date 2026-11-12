package agentcallback

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
)

func (m *jobManager) handleError(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	// This is a contract with the runtime. See https://github.com/github/sweagentd/blob/463009a5df2a9297ef617b33504209001cbe42f9/runtime/src/types.ts#L5
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: error")

	var agentError *AgentError
	err := json.Unmarshal([]byte(update.Content), &agentError)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal agent error: %w", err)
	}

	if !agentError.SkipReport {
		m.obsv.LogAndReportError(ctx, agentError, "")
	} else {
		m.obsv.LoggerWithRequestTelemetry(ctx, r).WithError(agentError).Error("agent error (not reported to Sentry)")
	}

	tags := m.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"is_vision_flow": strconv.FormatBool(agentError.IsVisionFlow),
		"skip_report":    strconv.FormatBool(agentError.SkipReport),
	})

	m.obsv.Statter.Counter("agent.job_error_callback", tags, 1)

	jobErr := &jobs.JobError{Message: agentError.Description()}
	err = m.jobsStore.PatchJob(ctx, job, db.JobPatch{Error: jobErr})
	if err != nil {
		return nil, fmt.Errorf("failed to patch job: %w", err)
	}

	jobResult := &JobResult{
		Status:      jobs.JobStatusFailed,
		CompletedAt: time.Now().UTC(),
		Result:      agentError,
	}

	return jobResult, nil
}
