package jobservice

import (
	"context"
	"fmt"
	"time"

	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
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
		return fmt.Errorf("failed to get job for queued api job: %w", err)
	}

	gh, err := s.ghf.NewClientForRepo(ctx, apiJob)
	if err != nil {
		return err
	}

	builder := s.JobBuilderForJob(assignment, job).
		WithExperiments()

	_, job, err = builder.Build(ctx, gh)
	if err != nil {
		return fmt.Errorf("failed to build job: %w", err)
	}

	_, err = s.QueueJobForExecution(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to queue job for execution: %w", err)
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
	s.obsv.LoggerWithTelemetry(ctx).Info("checking if actor has exceeded the maximum number of queued jobs")
	if s.limiter.QueuedJobsExceeded(ctx, job.ActorID) {
		s.obsv.LoggerWithTelemetry(ctx).WithError(limits.ErrActorExceededMaxQueuedJobs).Error("actor has exceeded maximum queued jobs")

		innerErr := s.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, "exceeded the maximum number of queued jobs")
		if innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after job queue limit exceed")
		}
		return nil, limits.ErrActorExceededMaxQueuedJobs
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("queuing job for additional processing")

	apiJob := aqueductJobs.ToAPIJob(ctx, job)
	_, err := s.queue.QueueJob(ctx, apiJob)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to queue job for additional processing")
		if innerErr := s.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, "Failed to queue job"); innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after queue failure")
		}
		return nil, fmt.Errorf("failed to queue job for additional processing: %w", err)
	}

	s.updateRequestContextJob(ctx, job)
	s.obsv.LoggerWithTelemetry(ctx).Info("finished queuing job for additional processing")

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
	s.obsv.LoggerWithTelemetry(ctx).Info("checking if actor has exceeded the maximum number of queued jobs")
	if s.limiter.QueuedJobsExceeded(ctx, job.ActorID) {
		s.obsv.LoggerWithTelemetry(ctx).WithError(limits.ErrActorExceededMaxQueuedJobs).Error("actor has exceeded maximum queued jobs")

		innerErr := s.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, "exceeded the maximum number of queued jobs")
		if innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after job queue limit exceed")
		}
		return nil, limits.ErrActorExceededMaxQueuedJobs
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("queuing job for execution")

	var err error

	// The session was likely already created, but we must ensure that we don't
	// queue a job without a session, so we make sure here. This is idempotent
	// if the session already exists.
	if job.SessionID == "" {
		s.obsv.LoggerWithTelemetry(ctx).Warn("Session ID doesn't exist on job when queuing for execution, creating a new session")

		sessionName := "New Session"
		if job.Action == jobs.AgentActionFix {
			sessionName = "Initial implementation"
		} else {
			sessionName = fmt.Sprintf("Review from @%s", job.ActorDisplayLogin)
		}

		id, err := s.createSessionForJob(ctx, job, capi.SessionStateQueued, sessionName)
		if err != nil {
			return nil, fmt.Errorf("failed to create session: %w", err)
		}

		job.SessionID = id
	}

	queuedAt := time.Now().Unix()

	s.obsv.LoggerWithTelemetry(ctx).Info("updating job with queue info")

	job, err = s.UpdateJobForQueued(ctx, job, queuedAt)
	if err != nil {
		return nil, fmt.Errorf("failed to update job with queue info: %w", err)
	}

	agentJob := aqueductJobs.ToAgentJob(ctx, job)
	_, err = s.queue.QueueJob(ctx, agentJob)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to queue job for execution")
		if innerErr := s.finalizeUnexecutedJob(ctx, nil, job, jobs.JobStatusFailed, "Failed to queue job"); innerErr != nil {
			s.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after queue failure")
		}
		return nil, fmt.Errorf("failed to queue job for execution: %w", err)
	}

	s.updateRequestContextJob(ctx, job)
	s.obsv.LoggerWithTelemetry(ctx).Info("finished queuing job for execution")

	return agentJob, nil
}
