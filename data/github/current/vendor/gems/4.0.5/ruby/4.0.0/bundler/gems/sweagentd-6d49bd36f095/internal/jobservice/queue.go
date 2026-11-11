package jobservice

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	limits "github.com/github/sweagentd/internal/limiter"
)

// Process processes an aqueduct APIJob from the queue, finishes creating the
// job by performing any deferred steps that require more time or resources,
// then enqueues a new aqueduct AgentJob.
//
// APIJobs represent new jobs created using the Jobs REST or Twirp APIs.
// AgentJobs represent jobs that have been fully built up and are ready for execution.
//
// When jobs are created using the REST/Twirp APIs, we need to create a session
// and initialize enough of the job that we can return a meaningful response to
// the user, allowing them to monitor the state of the job as we continue processing.
//
// We defer the more expensive job creation "build up" steps like checking branch
// protection rules, creating a branch, and optionally creating a pull request
// using an Aqueduct queue. This enables the service to control the rate of job
// processing, handle rate limiting, and retry failed processing steps without
// impacting the user.
//
// Jobs in the queue that have been created using the REST/Twirp APIs and need
// to be processed are represented by APIJob Aqueduct jobs.
func (s *Service) Process(ctx context.Context, apiJob *aqueductJobs.APIJob) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.Process")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("processing aqueduct api job")

	assignment, job, err := s.GetJobQueuedForProcessing(ctx, apiJob)
	if err != nil {
		if IsAssignmentNotFound(err) {
			s.obsv.LoggerWithTelemetry(ctx).Warn("assignment not found for queued api job, skipping")
			return nil
		}
		return goerrors.Errorf("failed to get job for queued api job: %w", err)
	}

	app, err := s.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		return goerrors.Errorf("failed to find agentic app by ID: %w", err)
	}

	gh, err := s.ghf.NewClientForRepo(ctx, app, apiJob)
	if err != nil {
		return err
	}

	repo, err := gh.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	builder := s.JobBuilderForJob(assignment, job, repo).
		WithExperiments().
		WithAINameGen()

	_, job, err = builder.Build(ctx, gh)
	if err != nil {
		return goerrors.Errorf("failed to build job: %w", err)
	}

	_, err = s.QueueJobForExecution(ctx, job)
	if err != nil {
		return goerrors.Errorf("failed to queue job for execution: %w", err)
	}

	return nil
}

// QueueJobForProcessing queues a new aqueduct APIJob for processing.
// This is used for jobs created via the REST or Twirp APIs that need further
// processing to be fully built up before execution.
func (s *Service) QueueJobForProcessing(ctx context.Context, job *jobs.Job) (*aqueductJobs.APIJob, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.QueueJobForProcessing")
	defer span.End()

	s.updateRequestContextJob(ctx, job)
	// check if the actor has exceeded the max queued jobs before queuing the job
	if s.limiter.QueuedJobsExceeded(ctx, job.ActorID, job.AgentID) {
		s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", false)).WithError(limits.ErrActorExceededMaxQueuedJobs).Error("queue job for processing")

		innerErr := s.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrRateLimitExceeded, "exceeded the maximum number of queued jobs"))
		if innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after job queue limit exceed")
		}
		return nil, limits.ErrActorExceededMaxQueuedJobs
	}

	apiJob := aqueductJobs.ToAPIJob(ctx, job)
	_, err := s.queue.QueueJob(ctx, apiJob)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", false)).WithError(err).Error("queue job for processing")
		innerErr := s.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrQueueFailure, "Failed to queue job"))
		if innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after queue failure")
		}
		return nil, goerrors.Errorf("failed to queue job for additional processing: %w", err)
	}

	s.updateRequestContextJob(ctx, job)
	s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", true)).Info("queue job for processing")

	return apiJob, nil
}

// QueueJobForExecution queues a new aqueduct AgentJob for processing.
// Queuing an AgentJob assumes that the (sweagentd) job has been created, and
// fully "built up". The associated session, branch, and optionally a pull request
// should already exist before calling this method.
func (s *Service) QueueJobForExecution(ctx context.Context, job *jobs.Job) (*aqueductJobs.AgentJob, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.QueueJobForExecution")
	defer span.End()

	s.updateRequestContextJob(ctx, job)
	// check if the actor has exceeded the max queued jobs before queuing the job
	if s.limiter.QueuedJobsExceeded(ctx, job.ActorID, job.AgentID) {
		s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", false)).WithError(limits.ErrActorExceededMaxQueuedJobs).Error("queued jobs limit check")

		innerErr := s.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrRateLimitExceeded, "exceeded the maximum number of queued jobs"))
		if innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after job queue limit exceed")
		}
		return nil, limits.ErrActorExceededMaxQueuedJobs
	}

	var err error
	var sessionClient capi.SessionClient

	// The session was likely already created, but we must ensure that we don't
	// queue a job without a session, so we make sure here. This is idempotent
	// if the session already exists.
	// When UseAsyncSessions is true, sessions are no longer managed by sweagentd.
	if !job.UseAsyncSessions && job.SessionID == "" {
		s.obsv.LoggerWithTelemetry(ctx).Warn("Session ID doesn't exist on job when queuing for execution, creating a new session")

		var sessionName string

		switch job.Action {
		case jobs.AgentActionFix:
			sessionName = "Initial implementation"
		case jobs.AgentActionFixPRComment:
			sessionName = fmt.Sprintf("Review from @%s", job.ActorDisplayLogin)
		default:
			sessionName = "New Session"
		}

		sessionClient, err = s.GetSessionClient(ctx, job.AgentID, job)
		if err != nil {
			return nil, goerrors.Errorf("failed to get session client: %w", err)
		}

		id, err := s.createSessionForJob(ctx, sessionClient, job, capi.SessionStateQueued, sessionName)
		if err != nil {
			return nil, goerrors.Errorf("failed to create session: %w", err)
		}

		job.SessionID = id
	}

	queuedAt := time.Now().Unix()

	job, err = s.UpdateJobForQueued(ctx, job, queuedAt)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(kvp.Bool("success", false)).Error("update job with queue info")
		return nil, goerrors.Errorf("failed to update job with queue info: %w", err)
	}
	s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", true)).Info("update job with queue info")

	agentJob := aqueductJobs.ToAgentJob(ctx, job)
	_, err = s.queue.QueueJob(ctx, agentJob)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", false)).WithError(err).Error("queue job for execution")
		innerErr := s.finalizeUnexecutedJob(ctx, sessionClient, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrQueueFailure, "Failed to queue job"))
		if innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after queue failure")
		}
		return nil, goerrors.Errorf("failed to queue job for execution: %w", err)
	}

	s.updateRequestContextJob(ctx, job)
	s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", true)).Info("queue job for execution")

	return agentJob, nil
}
