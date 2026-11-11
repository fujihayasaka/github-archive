package agentcallback

import (
	"context"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/requestctx"
)

// UpdateRequestContextJobUpdate adds a job update to the request context for
// logging and telemetry purposes.
func (s *jobManager) UpdateRequestContextJobUpdate(ctx context.Context, job *JobUpdate, action jobs.AgentAction) {
	err := requestctx.AddJobUpdate(ctx, &requestctx.CtxJobUpdate{
		Action:    string(action),
		Kind:      string(job.Kind),
		CreatedAt: job.CreatedAt.Unix(),
	})
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add job update to request context")
	}
}
