package jobservice

import (
	"context"
	_ "embed"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

// addRequestCtxSessionFromJob adds the session to the request context from the given job.
func (s *Service) addRequestCtxSessionFromJob(ctx context.Context, job *jobs.Job) {
	// WorkflowRunID is only meaningful for Actions-backed jobs; for other
	// launchers leave it as zero.
	var workflowRunID uint64
	if id, ok := job.WorkflowRunID(); ok {
		workflowRunID = uint64(id)
	}
	err := requestctx.AddSession(ctx, &requestctx.CtxSession{
		ID:            job.SessionID,
		State:         string(capi.MapJobStatusToSessionState(job.Status)),
		ResourceType:  string(capi.ResourceTypePullRequest),
		ResourceID:    job.PullRequestID,
		EventType:     string(job.EventType),
		WorkflowRunID: workflowRunID,
		HeadRef:       job.BranchName,
		BaseRef:       job.BaseCommit,
	})
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add session to request context with job")
	}
}

// addRequestContextSession is a helper to add the session to the request context.
func (s *Service) addRequestContextSession(ctx context.Context, session *capi.Session) {
	if session == nil {
		err := requestctx.AddSession(ctx, nil)
		if err != nil {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to remove session from request context")
		}
		return
	}
	err := requestctx.AddSession(ctx, &requestctx.CtxSession{
		ID:            session.ID,
		State:         string(session.State),
		ResourceType:  string(session.ResourceType),
		ResourceID:    session.ResourceID,
		EventType:     session.EventType,
		WorkflowRunID: session.WorkflowRunID,
		HeadRef:       session.HeadRef,
		BaseRef:       session.BaseRef,
	})
	if err != nil {
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
	if update.HeadRef != "" {
		ctxSession.HeadRef = update.HeadRef
	}
	if update.BaseRef != "" {
		ctxSession.BaseRef = update.BaseRef
	}
	err := requestctx.AddSession(ctx, ctxSession)
	if err != nil {
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

	// Populate agent slug for telemetry when flag is enabled. The slug is
	// stored on the top-level CtxAgent so it remains visible to telemetry
	// even on code paths that clear the job from context. The CtxJob.Agent
	// fields are kept in sync for backward compatibility with consumers
	// still reading from CtxJob.
	if job != nil && s.ffs != nil && s.ffs.IsEnabled(ctx, featureflags.CopilotSWEAgentEmitAgentSlugTelemetry) {
		slug := s.agentSlug(ctx, job)
		if ctxJob, ok := requestctx.Job(ctx); ok {
			ctxJob.Agent.Slug = slug
			ctxJob.EmitAgentSlugStats = true
		}
		err := requestctx.AddAgent(ctx, &requestctx.CtxAgent{
			ID:   job.AgentID,
			Slug: slug,
		})
		if err != nil {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add agent to request context")
		}
	}
}

// updateRequestContextJob is a helper to update the job in the request context.
func updateRequestContextJob(ctx context.Context, obsv observability.Exporters, job *jobs.Job) {
	if job == nil {
		err := requestctx.AddJob(ctx, nil)
		if err != nil {
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to remove job from request context")
		}
		// Clear the top-level custom agent so it does not taint later logs.
		err = requestctx.AddCustomAgent(ctx, nil)
		if err != nil {
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to remove custom agent from request context")
		}
		return
	}

	ctxJob, ok := requestctx.Job(ctx)
	// If the job is not in the context or the existing (ctx) job has a different
	// ID, create a new one. This ensure that if one-off fields are set for the
	// job elsewhere, they are not overwritten by populating the full job context
	if !ok || (ctxJob.ID != "" && ctxJob.ID != job.ID) {
		ctxJob = &requestctx.CtxJob{}
		err := requestctx.AddJob(ctx, ctxJob)
		if err != nil {
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add job to request context")
		}
	}

	ctxJob.ID = job.ID
	ctxJob.RepoID = job.RepoID
	ctxJob.OwnerID = job.OwnerID
	ctxJob.AssignmentID = job.AssignmentID
	ctxJob.ComputeID = job.ComputeID
	ctxJob.LauncherType = string(job.Launcher)
	ctxJob.SessionID = job.SessionID
	ctxJob.EventType = string(job.EventType)
	ctxJob.ActorID = job.ActorID
	ctxJob.PullRequestID = job.PullRequestID
	ctxJob.PullRequestNumber = job.PullRequestNumber
	ctxJob.CreatedAt = job.CreatedAt
	ctxJob.RequestStartedAt = job.RequestStartedAt
	ctxJob.PreparedAt = job.PreparedAt
	ctxJob.WasDelayed = job.WasDelayed
	ctxJob.CompletedAt = job.CompletedAt
	ctxJob.QueuedAt = job.QueuedAt
	ctxJob.StartedAt = job.StartedAt
	ctxJob.Status = string(job.Status)
	ctxJob.IsAutomation = job.IsTriggered
	ctxJob.BranchName = job.BranchName
	ctxJob.Model = job.Model
	ctxJob.Agent = requestctx.CtxAgent{
		ID: job.AgentID,
	}

	if job.Experiments != nil {
		ctxJob.Experiments = requestctx.CtxExperiments{
			Variations:        job.Experiments.Variations,
			AssignmentContext: job.Experiments.AssignmentContext,
		}
	}

	// Only set the custom agent in the context if it is not the default agent.
	// Since the default agent has a name, it will be hard to distinguish when debugging.
	if !job.CustomAgent.IsCopilot() {
		ca := requestctx.CtxCustomAgent{
			Name:    job.CustomAgent.Name,
			Scope:   job.CustomAgent.Scope,
			RepoID:  job.CustomAgent.RepoID,
			OwnerID: job.CustomAgent.RepoOwnerID,
			Version: job.CustomAgent.Version,
		}
		ctxJob.CustomAgent = ca

		// Also set the top-level custom agent in the context so it is
		// included in all telemetry and logging even outside the job scope.
		err := requestctx.AddCustomAgent(ctx, &ca)
		if err != nil {
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add custom agent to request context")
		}
	} else {
		// Clear any previously set top-level custom agent so it does not
		// taint later logs when the job uses the default agent.
		_ = requestctx.AddCustomAgent(ctx, nil)
	}
}
