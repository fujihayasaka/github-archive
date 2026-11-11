package agentcallback

import (
	"context"
	"errors"
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
)

// CheckQuotaResponse represents the callback response payload and reports
// whether the user has enough quota to continue the current session.
type CheckQuotaResponse struct {
	HasEnoughQuota bool `json:"has_enough_quota"`
}

func (m *jobManager) handleCheckQuota(ctx context.Context, r *http.Request, job *jobs.Job) (*JobResult, error) {
	ctx, span := m.obsv.Tracer.Start(ctx, "agentcallback.jobManager.handleCheckQuota")
	defer span.End()

	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: in-session runtime checkQuota")

	hasEnoughQuota, _, _, err := githubtwirp.CheckPremiumQuota(
		ctx,
		m.ghTwirp,
		m.ffClient,
		m.obsv,
		job.OwnerID,
		job.RepoID,
		job.ActorID,
		false,
	)

	if err != nil {
		// Customer selection required should be treated as insufficient quota.
		if errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
			m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("customer selection required; treating as insufficient quota in in-session runtime checkQuota callback")
			hasEnoughQuota = false
		} else {
			// Fail open on transient check errors to avoid interrupting active sessions.
			// log the error and increment a metric
			m.obsv.LogAndReportError(ctx, err, "failed to check quota in in-session runtime checkQuota callback, allowing session to continue")
			m.obsv.Increment(ctx, "events.check_quota_callback_error", stats.Tags{"error_type": "quota_check_failed"})
			hasEnoughQuota = true
		}
	}

	m.obsv.LoggerWithRequestTelemetry(ctx, r).WithFields(
		kvp.Bool("has_enough_quota", hasEnoughQuota),
	).Info("in-session runtime checkQuota result")

	return &JobResult{
		Status: jobs.JobStatusRunning,
		Response: &CheckQuotaResponse{
			HasEnoughQuota: hasEnoughQuota,
		},
	}, nil
}
