package jobservice

import (
	"context"
	_ "embed"
	"strconv"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

// addRequestCtxSessionFromJob adds the session to the request context from the given job.
func (s *Service) addRequestCtxSessionFromJob(ctx context.Context, job *jobs.Job) {
	workflowRunID, err := strconv.ParseUint(job.ComputeID, 10, 64)
	if err != nil {
		workflowRunID = 0
	}
	if err := requestctx.AddSession(ctx, &requestctx.CtxSession{
		ID:            job.SessionID,
		State:         string(capi.MapJobStatusToSessionState(job.Status)),
		ResourceType:  string(capi.ResourceTypePullRequest),
		ResourceID:    job.PullRequestID,
		EventType:     string(job.EventType),
		WorkflowRunID: workflowRunID,
	}); err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add session to request context with job")
	}
}

// addRequestContextSession is a helper to add the session to the request context.
func (s *Service) addRequestContextSession(ctx context.Context, session *capi.Session) {
	if session == nil {
		if err := requestctx.AddSession(ctx, nil); err != nil {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to remove session from request context")
		}
		return
	}
	if err := requestctx.AddSession(ctx, &requestctx.CtxSession{
		ID:            session.ID,
		State:         string(session.State),
		ResourceType:  string(session.ResourceType),
		ResourceID:    session.ResourceID,
		EventType:     session.EventType,
		WorkflowRunID: session.WorkflowRunID,
	}); err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add session to request context")
	}
}

// UpdateRequestContextSession is a helper to update the session in the request
// context.
//
// Deprecated: this is a temporary static method to allow the matching method to
// be removed from jobutils and placed here. New callers should use the jobservice
// to manage the job, which will manage the session and populate the context internally.
func UpdateRequestContextSession(ctx context.Context, obsv observability.Exporters, update capi.SessionUpdate) {
	updateRequestContextSession(ctx, obsv, update)
}

// updateRequestContextSession is a helper to update the session in the request context.
func (s *Service) updateRequestContextSession(ctx context.Context, update capi.SessionUpdate) {
	updateRequestContextSession(ctx, s.obsv, update)
}

// updateRequestContextSession is a helper to update the session in the request
// context.
func updateRequestContextSession(ctx context.Context, obsv observability.Exporters, update capi.SessionUpdate) {
	ctxSession, ok := requestctx.Session(ctx)
	if !ok {
		ctxSession = &requestctx.CtxSession{}
	}
	if update.ResourceID != 0 {
		ctxSession.ResourceID = update.ResourceID
	}
	if update.ResourceType != nil {
		ctxSession.ResourceType = string(*update.ResourceType)
	}
	if update.State != "" {
		ctxSession.State = string(update.State)
	}
	if update.WorkflowRunID != 0 {
		ctxSession.WorkflowRunID = update.WorkflowRunID
	}
	if err := requestctx.AddSession(ctx, ctxSession); err != nil {
		obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update session in request context")
	}
}

// UpdateRequestContextJob updates the request context with the given job.
//
// Deprecated: this is a temporary static method to allow the matching method to
// be removed from jobutils and placed here. New callers should use the jobservice
// to manage the job, which will populate the context automatically.
func UpdateRequestContextJob(ctx context.Context, obsv observability.Exporters, job *jobs.Job) {
	updateRequestContextJob(ctx, obsv, job)
}

// updateRequestContextJob is a helper to update the job in the request context.
func (s *Service) updateRequestContextJob(ctx context.Context, job *jobs.Job) {
	updateRequestContextJob(ctx, s.obsv, job)
}

// updateRequestContextJob is a helper to update the job in the request context.
func updateRequestContextJob(ctx context.Context, obsv observability.Exporters, job *jobs.Job) {
	if job == nil {
		if err := requestctx.AddJob(ctx, nil); err != nil {
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to remove job from request context")
		}
		return
	}

	ctxJob, ok := requestctx.Job(ctx)
	// If the job is not in the context or the existing (ctx) job has a different
	// ID, create a new one. This ensure that if one-off fields are set for the
	// job elsewhere, they are not overwritten by populating the full job context
	if !ok || (ctxJob.ID != "" && ctxJob.ID != job.ID) {
		ctxJob = &requestctx.CtxJob{}
		if err := requestctx.AddJob(ctx, ctxJob); err != nil {
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add job to request context")
		}
	}

	ctxJob.ID = job.ID
	ctxJob.RepoID = job.RepoID
	ctxJob.OwnerID = job.OwnerID
	ctxJob.AssignmentID = job.AssignmentID
	ctxJob.ComputeID = job.ComputeID
	ctxJob.SessionID = job.SessionID
	ctxJob.EventType = string(job.EventType)
	ctxJob.ActorID = job.ActorID
	ctxJob.PullRequestID = job.PullRequestID
	ctxJob.PullRequestNumber = job.PullRequestNumber
	ctxJob.CreatedAt = job.CreatedAt
	ctxJob.CompletedAt = job.CompletedAt
	ctxJob.QueuedAt = job.QueuedAt
	ctxJob.Status = string(job.Status)
	ctxJob.BranchName = job.BranchName

	if job.Experiments != nil {
		ctxJob.Experiments = requestctx.CtxExperiments{
			Variations:        job.Experiments.Variations,
			AssignmentContext: job.Experiments.AssignmentContext,
		}
	}

	// Only set the custom agent in the context if it is not the default agent.
	// Since the default agent has a name, it will be hard to distinguish when debugging.
	if !job.CustomAgent.IsCopilot() {
		ctxJob.CustomAgent = requestctx.CtxCustomAgent{
			Name:    job.CustomAgent.Name,
			RepoID:  job.CustomAgent.RepoID,
			OwnerID: job.CustomAgent.RepoOwnerID,
			Version: job.CustomAgent.Version,
		}
	}
}
