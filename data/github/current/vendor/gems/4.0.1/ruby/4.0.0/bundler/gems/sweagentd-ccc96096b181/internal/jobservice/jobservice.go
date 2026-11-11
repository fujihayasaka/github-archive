// Package jobservice provides services for managing jobs (and sessions).
package jobservice

import (
	"context"
	"errors"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/telemetry"
)

// ErrJobNotFound is returned when a job cannot be found in the store.
var ErrJobNotFound = errors.New("job not found")

// IsJobNotFound returns true if the error is ErrJobNotFound.
func IsJobNotFound(err error) bool {
	return errors.Is(err, ErrJobNotFound)
}

type limiter interface {
	QueuedJobsExceeded(ctx context.Context, actor int64) bool
	IncrementQueuedJobs(ctx context.Context, actor int64)
	DecrementQueuedJobs(ctx context.Context, actor int64)
	IncrementRunningJobs(ctx context.Context, actor int64)
	DecrementRunningJobs(ctx context.Context, actor int64)
}

// Service provides job management services.
type Service struct {
	obsv           observability.Exporters
	ffs            featureflags.Client
	store          db.JobsStore
	capi           capi.Client
	ghf            github.ClientFactoryInterface
	twirp          githubtwirp.ClientInterface
	queue          sweagentd.AqueductClient
	limiter        limiter
	experiments    experiments.Client
	customAgentSvc *customagent.Service
	committerEmail string
	spokes         sweagentd.Spokes
	appProvider    *agenticapp.Provider
	eventEmitter   JobEventEmitter
}

// New creates a new job service with the given dependencies.
func New(
	obsv observability.Exporters,
	ffs featureflags.Client,
	store db.JobsStore,
	capi capi.Client,
	ghf github.ClientFactoryInterface,
	twirp githubtwirp.ClientInterface,
	queue sweagentd.AqueductClient,
	limiter limiter,
	experiments experiments.Client,
	customAgentSvc *customagent.Service,
	committerEmail string,
	spokes sweagentd.Spokes,
	appProvider *agenticapp.Provider,
	eventEmitter JobEventEmitter,
) *Service {
	if eventEmitter == nil {
		eventEmitter = &noopJobEventEmitter{}
	}
	return &Service{
		obsv:           obsv,
		ffs:            ffs,
		store:          store,
		capi:           capi,
		ghf:            ghf,
		twirp:          twirp,
		queue:          queue,
		limiter:        limiter,
		experiments:    experiments,
		customAgentSvc: customAgentSvc,
		committerEmail: committerEmail,
		spokes:         spokes,
		appProvider:    appProvider,
		eventEmitter:   eventEmitter,
	}
}

// GetJobsForAssignment retrieves all jobs associated with the given assignment.
func (s *Service) GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetJobsForAssignment")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("getting jobs for assignment")
	jobs, err := s.store.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		return nil, goerrors.Errorf("failed to get jobs for assignment: %w", err)
	}
	return jobs, nil
}

// GetJobByID retrieves a job by its ID.
// If no job is found, it returns [ErrJobNotFound] error.
func (s *Service) GetJobByID(ctx context.Context, ownerID, repoID int64, jobID string) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetJobByID")
	defer span.End()

	kvps := []kvp.Field{}
	kvps = append(kvps,
		kvp.String("job.id", jobID),
		kvp.Int64("job.repo_id", repoID),
		kvp.Int64("job.owner_id", ownerID),
	)

	s.obsv.LoggerWithTelemetry(ctx).Info("getting job by id", kvps...)
	job, err := s.store.GetJob(ctx, ownerID, repoID, jobID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get job by id: %w", err)
	}
	if job == nil {
		s.obsv.LoggerWithTelemetry(ctx).Info("no job found for id", kvps...)
		return nil, ErrJobNotFound
	}

	s.updateRequestContextJob(ctx, job)
	s.addRequestCtxSessionFromJob(ctx, job)
	return job, nil
}

// GetJobBySessionID retrieves a job by its associated session ID.
// If no job is found, it returns [ErrJobNotFound] error.
func (s *Service) GetJobBySessionID(ctx context.Context, ownerID, repoID int64, sessionID string) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetJobBySessionID")
	defer span.End()

	kvps := []kvp.Field{}
	kvps = append(kvps,
		kvp.String("session.id", sessionID),
		kvp.Int64("job.repo_id", repoID),
		kvp.Int64("job.owner_id", ownerID),
	)

	s.obsv.LoggerWithTelemetry(ctx).Info("getting job by session id", kvps...)
	job, err := s.store.GetJobForSessionID(ctx, ownerID, repoID, sessionID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get job by session id: %w", err)
	}
	if job == nil {
		s.obsv.LoggerWithTelemetry(ctx).Info("no job found for session id", kvps...)
		return nil, ErrJobNotFound
	}

	s.updateRequestContextJob(ctx, job)
	s.addRequestCtxSessionFromJob(ctx, job)
	return job, nil
}

// GetAssignmentByID retrieves an assignment by its ID.
func (s *Service) GetAssignmentByID(ctx context.Context, ownerID, repoID int64, assignmentID string) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetAssignmentByID")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("getting assignment by id",
		kvp.String("assignment.id", assignmentID),
		kvp.Int64("gh.repo.id", repoID),
		kvp.Int64("gh.repo.owner_id", ownerID),
	)
	assignment, err := s.store.GetAssignment(ctx, ownerID, repoID, assignmentID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get assignment by id: %w", err)
	}
	return assignment, nil
}

// GetJobQueuedForProcessing retrieves the assignment and job associated with the given
// Aqueduct APIJob from the queue. It validates the presence of necessary identifiers
// and fetches the assignment and job from the store.
func (s *Service) GetJobQueuedForProcessing(ctx context.Context, queueJob *aqueductJobs.APIJob) (*jobs.Assignment, *jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetJobQueuedForProcessing")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("fetching job for aqueduct api job")

	repoID := queueJob.GetRepositoryId()
	ownerID := queueJob.GetOwnerId()
	assignmentID := queueJob.GetAssignmentId()
	jobID := queueJob.GetJobId()

	if ownerID == 0 || repoID == 0 || assignmentID == "" || jobID == "" {
		return nil, nil, goerrors.New("invalid api job: missing owner_id, repository_id, assignment_id, or job_id")
	}

	assignment, err := s.store.GetAssignment(ctx, ownerID, repoID, assignmentID)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get assignment from store: %w", err)
	}
	if assignment == nil {
		return nil, nil, goerrors.New("assignment not found")
	}

	job, err := s.GetJobByID(ctx, ownerID, repoID, jobID)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get job from store: %w", err)
	}

	return assignment, job, nil
}

// GetJobQueuedForExecution retrieves the job associated with the given Aqueduct agent job.
// It validates the presence of necessary identifiers and fetches the job from the store.
// The context is updated with the job and session information for further processing.
func (s *Service) GetJobQueuedForExecution(ctx context.Context, queueJob *aqueductJobs.AgentJob) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetJobQueuedForExecution")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("fetching job for aqueduct agent job")

	repoID := queueJob.GetRepositoryId()
	ownerID := queueJob.GetOwnerId()
	assignmentID := queueJob.GetAssignmentId()
	jobID := queueJob.GetJobId()

	if ownerID == 0 || repoID == 0 || assignmentID == "" || jobID == "" {
		return nil, goerrors.New("invalid agent job: missing owner_id, repository_id, assignment_id, or job_id")
	}

	job, err := s.GetJobByID(ctx, ownerID, repoID, jobID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get job from store: %w", err)
	}

	return job, nil
}

// GetJobQueuedForExecutionWithNonce retrieves the job associated with the given Aqueduct agent job.
// It validates the presence of necessary identifiers and fetches the job from the store.
// The context is updated with the job and session information for further processing.
func (s *Service) GetJobQueuedForExecutionWithNonce(ctx context.Context, queueJob *aqueductJobs.AgentJob) (*jobs.Job, string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetJobQueuedForExecutionWithNonce")
	defer span.End()

	job, err := s.GetJobQueuedForExecution(ctx, queueJob)
	if err != nil {
		return nil, "", err
	}

	if !job.IsQueued() && !job.IsPending() {
		// Nonce should only be regenerated if the job is in a pending or queued state.
		// We only warn here instead of erroring because the caller is using this
		// to get the job too, so they haven't had the opportunity to check the
		// job state yet.
		s.obsv.LoggerWithTelemetry(ctx).Warn("job is not in a state that allows nonce regeneration")
	}

	// Generate a new nonce for the job to ensure idempotency and security.
	// This nonce can be used for authenticating requests related to this job.
	//
	// We don't persist the nonce hash to the database here. Instead, we expect
	// the caller to call UpdateJobForLaunched with the job and nonce once the
	// agent is successfully launched.

	nonce := jobs.GenerateNonce()
	job.NonceHash = jobs.HashNonce(nonce)

	return job, nonce, nil
}

// SaveJob saves the given job to the store.
func (s *Service) SaveJob(ctx context.Context, job *jobs.Job) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.SaveJob")
	defer span.End()

	_, err := s.store.UpsertJob(ctx, job)
	if err != nil {
		return goerrors.Errorf("failed to upsert job: %w", err)
	}
	return nil
}

// UpdateFromExecutionResult updates the job status and StartedAt timestamp based on execution updates.
// It automatically sets StartedAt if it's the first update (StartedAt == 0) and uses patch operations for efficiency.
func (s *Service) UpdateFromExecutionResult(ctx context.Context, job *jobs.Job, newStatus jobs.JobStatus) error {
	patch := db.JobPatch{}

	// Only update status if it has changed and is not terminal
	if job.Status != newStatus && !newStatus.IsTerminal() {
		patch.Status = &newStatus
	}

	// If this is the first execution update and we're updating to a non-terminal status, set StartedAt
	if job.StartedAt == 0 && !newStatus.IsTerminal() {
		now := time.Now().Unix()
		patch.StartedAt = &now
	}

	// Exit early if there's nothing to do
	if patch.Status == nil && patch.StartedAt == nil {
		return nil
	}

	err := s.store.PatchJob(ctx, job, patch)
	if err != nil {
		return goerrors.Errorf("failed to patch job: %w", err)
	}

	s.emitJobUpdated(ctx, job)

	if patch.Status != nil {
		jobs.StatJobTransition(ctx, s.obsv, s.obsv.TelemetryTags(ctx), job.Status, newStatus)
	}

	if patch.StartedAt != nil {
		// Add tags for custom setup steps and runs-on value
		// Emit "ubuntu-latest" if runs-on is empty or matches "ubuntu-latest", otherwise emit "other"
		runsOnValue := "ubuntu-latest"
		if job.RunsOn != "" && job.RunsOn != "ubuntu-latest" {
			runsOnValue = "other"
		}
		tags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
			"custom_setup_steps": strconv.FormatBool(job.CustomSetupStepsUsed),
			"runs_on":            runsOnValue,
			"event_type":         string(job.EventType),
			"agent_type":         string(job.Action),
			"async_sessions":     strconv.FormatBool(job.UseAsyncSessions),
		})
		s.obsv.DistributionMs(ctx, "jobs.launched_to_started", tags, time.Unix(*patch.StartedAt, 0).Sub(time.Unix(job.LaunchedAt, 0)))
		if job.RequestStartedAt > 0 {
			duration := time.Unix(*patch.StartedAt, 0).Sub(time.Unix(job.RequestStartedAt, 0))
			if duration >= 0 {
				s.obsv.DistributionMs(ctx, "jobs.request_to_started_ms", tags, duration)
			}
		}
	}

	return nil
}

// UpdateJobForQueued updates the job status to queued and sets the queued time.
// This method also updates the job in the request context and records the job status transition.
func (s *Service) UpdateJobForQueued(ctx context.Context, job *jobs.Job, queuedAt int64) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.UpdateJobForQueued")
	defer span.End()

	job.QueuedAt = queuedAt

	prevJobStatus := job.Status
	job.Status = jobs.JobStatusQueued

	var err error

	// update the job in the database
	job, err = s.store.UpdateJob(ctx, job)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update job for queued")
		return nil, goerrors.Errorf("failed to update job: %w", err)
	}

	s.updateRequestContextJob(ctx, job)

	jobs.StatJobTransition(ctx, s.obsv, s.obsv.TelemetryTags(ctx), prevJobStatus, job.Status)

	s.limiter.IncrementQueuedJobs(ctx, job.ActorID)

	s.emitJobUpdated(ctx, job)

	return job, nil
}

// UpdateJobForLaunched updates the job status to running, sets the compute ID and
// launch time, and starts the associated session.
// This method also updates the job in the request context, records the job status transition,
func (s *Service) UpdateJobForLaunched(ctx context.Context, job *jobs.Job, computeID string, launchedAt int64) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.UpdateJobForLaunched")
	defer span.End()

	telemetryPublisher := telemetry.NewTelemetryPublisher(s.obsv, s.twirp, s.ffs)

	runID, err := strconv.ParseUint(computeID, 10, 64)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to parse compute ID")
		return nil, goerrors.Errorf("failed to parse compute ID: %w", err)
	}

	job.ComputeID = computeID
	job.LaunchedAt = launchedAt

	prevJobStatus := job.Status
	job.Status = jobs.JobStatusRunning

	// update the job in the database
	job, err = s.store.UpdateJob(ctx, job)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update job for launched")
		return nil, goerrors.Errorf("failed to update job: %w", err)
	}
	s.updateRequestContextJob(ctx, job)

	s.limiter.DecrementQueuedJobs(ctx, job.ActorID)
	s.limiter.IncrementRunningJobs(ctx, job.ActorID)

	jobs.StatJobTransition(ctx, s.obsv, s.obsv.TelemetryTags(ctx), prevJobStatus, job.Status)

	// Emit jobs.queue_wait_duration_ms: (launched_at - queued_at)
	// This measures how long the job waited in the queue before being scheduled for execution by GitHub Actions
	if job.QueuedAt > 0 {
		queueWaitDuration := time.Unix(launchedAt, 0).Sub(time.Unix(job.QueuedAt, 0))
		// Add tags for custom setup steps and runs-on value
		runsOnValue := "ubuntu-latest"
		if job.RunsOn != "" && job.RunsOn != "ubuntu-latest" {
			runsOnValue = "other"
		}
		tags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
			"custom_setup_steps": strconv.FormatBool(job.CustomSetupStepsUsed),
			"runs_on":            runsOnValue,
			"event_type":         string(job.EventType),
			"agent_type":         string(job.Action),
			"async_sessions":     strconv.FormatBool(job.UseAsyncSessions),
		})
		s.obsv.DistributionMs(ctx, "jobs.queue_wait_duration_ms", tags, queueWaitDuration)
	}

	// Only update a session if async sessions are not enabled for the job.
	// When UseAsyncSessions is true, the runtime handles session management.
	if !job.UseAsyncSessions {
		err = s.updateSession(ctx, nil, job, capi.SessionUpdate{WorkflowRunID: runID})
		if err != nil {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update session with compute ID")
			if !s.ffs.IsEnabled(ctx, featureflags.CopilotSWEAgentSkipSessionFailures) {
				return nil, goerrors.Errorf("failed to update session: %w", err)
			}
		}
	}

	telemetryPublisher.PublishJobStartedTelemetry(ctx, job)

	s.emitJobUpdated(ctx, job)

	return job, nil
}

// FinalizeUnexecutedJob finalizes a job that was never executed, updating its
// status and finalizing its associated session if applicable.
func (s *Service) FinalizeUnexecutedJob(ctx context.Context, job *jobs.Job, status jobs.JobStatus, jobError *jobs.JobError) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.FinalizeUnexecutedJob")
	defer span.End()

	sessionClient, err := s.GetSessionClient(ctx, job.AgentID, job)
	if err != nil {
		return goerrors.Errorf("failed to create session client: %w", err)
	}

	return s.finalizeUnexecutedJob(ctx, sessionClient, job, status, jobError)
}

// FinalizeJob finalizes the job by updating its status and completed time.
// It also handles decrementing the running job count and publishing telemetry events.
// The terminalReason parameter is included in the Hydro telemetry event to describe
// why the job ended (e.g., "workflow_cancelled", "workflow_failed", "workflow_timed_out").
func (s *Service) FinalizeJob(ctx context.Context, job *jobs.Job, jobStatus jobs.JobStatus, jobError *jobs.JobError, completedAt int64) error {
	return s.finalizeJob(ctx, job, jobStatus, jobError, completedAt)
}

// emitJobUpdated emits a JobUpdated event if async sessions are enabled for the job.
func (s *Service) emitJobUpdated(ctx context.Context, job *jobs.Job) {
	if job.UseAsyncSessions {
		s.eventEmitter.EmitJobUpdated(ctx, job, s.obsv)
	}
}

// finalizeJob finalizes the job by updating its status and completed time.
// It also handles decrementing the running job count and publishing telemetry events.
func (s *Service) finalizeJob(ctx context.Context, job *jobs.Job, jobStatus jobs.JobStatus, jobError *jobs.JobError, completedAt int64) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.finalizeJob")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("finalizing job")

	tags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{"status": string(jobStatus)})
	s.obsv.Increment(ctx, "jobs.finalize", tags)

	if job.IsTerminal() && job.Status == jobStatus {
		s.obsv.LoggerWithTelemetry(ctx).Info("job is already in a terminal state, nothing to do")
		return nil // already in terminal state
	}

	prevJobStatus := job.Status

	fromQueued := prevJobStatus == jobs.JobStatusQueued
	fromRunning := prevJobStatus == jobs.JobStatusRunning

	job.Status = jobStatus

	if jobError != nil {
		job.Error = jobError
	}

	// We're updating the job to a terminal state, so update the completion timestamp
	prevCompletedAt := job.CompletedAt
	if job.CompletedAt == 0 {
		if completedAt == 0 {
			completedAt = time.Now().Unix()
		}

		job.CompletedAt = completedAt
	}

	var err error

	//nolint:nestif // because this is clearer to read
	if job.Persisted() {
		// If the job exists in the database, we need only patch the fields that changed.
		patch := db.JobPatch{Status: &job.Status}

		if prevCompletedAt != job.CompletedAt {
			patch.CompletedAt = &completedAt
		}

		if jobError != nil {
			patch.Error = jobError
		}

		err = s.store.PatchJob(ctx, job, patch)
		if err != nil {
			if !errors.Is(err, db.ErrPreconditionFailedOnUpdate) {
				return goerrors.Errorf("failed to patch job: %w", err)
			}
			// Since we are in cleanup mode, fetch the latest job, confirm it is
			// in the expected terminal state, and retry the patch again if not.
			job, err = s.store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
			if err != nil {
				return goerrors.Errorf("failed to get job after precondition failed on update: %w", err)
			}

			// Job has been fetched again from the database, check if it's already in the desired status.
			if job.IsTerminal() && job.Status == jobStatus {
				s.obsv.LoggerWithTelemetry(ctx).Info("job is already in a terminal state, nothing to do")
				return nil // already in terminal state
			}

			err = s.store.PatchJob(ctx, job, patch)
			if err != nil {
				return goerrors.Errorf("failed to patch job after precondition failed on update: %w", err)
			}
		}
	} else {
		// Otherwise we may be saving the job for the first time, so do an upsert.
		job, err = s.store.UpsertJob(ctx, job)
		if err != nil {
			return goerrors.Errorf("failed to upsert job: %w", err)
		}
	}

	if fromQueued {
		s.limiter.DecrementQueuedJobs(ctx, job.ActorID)
	}
	if fromRunning {
		s.limiter.DecrementRunningJobs(ctx, job.ActorID)
	}

	jobs.StatJobTransition(ctx, s.obsv, s.obsv.TelemetryTags(ctx), prevJobStatus, jobStatus)

	s.updateRequestContextJob(ctx, job)

	telemetryPublisher := telemetry.NewTelemetryPublisher(s.obsv, s.twirp, s.ffs)

	// We want to ensure all commands associated with the job are marked as "ignored"
	commands, err := s.store.GetCommandsWithStatus(ctx, job.AssignmentID, job.ID, command.StatusPending)
	if err != nil {
		return goerrors.Errorf("failed to get pending commands for job: %w", err)
	}
	ignored := command.StatusIgnored
	err = s.store.BatchPatchCommands(ctx, commands, db.CommandPatch{Status: &ignored})
	if err != nil {
		return goerrors.Errorf("failed to patch commands as ignored: %w", err)
	}

	for _, cmd := range commands {
		// Since we batch updated, we need to update the command in place to ensure
		// it reflects the actual state of the command.
		cmd.Status = ignored
		telemetryPublisher.PublishCommandUpdatedTelemetry(ctx, cmd)
	}

	s.emitJobUpdated(ctx, job)

	s.obsv.LoggerWithTelemetry(ctx).Info("patched job with terminal status")

	telemetryPublisher.PublishJobCompletedTelemetry(ctx, job)

	// Emit job performance metrics for terminal states
	s.emitJobPerformanceMetrics(ctx, job)

	// Emit the SLO completion metric for tracking job success rate
	jobs.StatJobCompletionSLO(ctx, s.obsv, s.obsv.TelemetryTags(ctx), job)

	return nil
}

func (s *Service) finalizeUnexecutedJob(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, status jobs.JobStatus, jobError *jobs.JobError) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.finalizeUnexecutedJob")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("finalizing unexecuted job")

	completedAt := time.Now().Unix()
	err := s.finalizeJob(ctx, job, status, jobError, completedAt)
	if err != nil {
		return goerrors.Errorf("failed to finalize job: %w", err)
	}

	// When UseAsyncSessions is true, sessions are managed by upstream services, not sweagentd.
	if job.UseAsyncSessions {
		return nil
	}

	// Use jobError's message as the customer visible message for finalizing the session.
	if job.SessionID != "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("finalizing session for unexecuted job")
	}
	err = s.finalizeUnexecutedSession(ctx, sessionClient, job, jobError)
	if err != nil {
		s.obsv.LogAndReportError(ctx, err, "failed to finalize session")
	}

	return nil
}

// emitJobPerformanceMetrics emits DataDog distribution metrics for job performance
// when a job reaches a terminal state. These metrics enable p50/p95/p99 percentile
// analysis for job lifecycle phases.
func (s *Service) emitJobPerformanceMetrics(ctx context.Context, job *jobs.Job) {
	if !job.IsTerminal() {
		return
	}

	// Build tags for metrics - use bounded values only to avoid cardinality explosion
	// Emit "ubuntu-latest" if runs-on is empty or matches "ubuntu-latest", otherwise emit "other"
	runsOnValue := "ubuntu-latest"
	if job.RunsOn != "" && job.RunsOn != "ubuntu-latest" {
		runsOnValue = "other"
	}
	tags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"event_type":         string(job.EventType),
		"agent_type":         string(job.Action),
		"terminal_state":     string(job.Status),
		"custom_setup_steps": strconv.FormatBool(job.CustomSetupStepsUsed),
		"runs_on":            runsOnValue,
		"async_sessions":     strconv.FormatBool(job.UseAsyncSessions),
	})

	// Emit jobs.total_duration_ms: (completed_at - created_at)
	// This measures the full job lifecycle from creation to completion
	if job.CreatedAt > 0 && job.CompletedAt > 0 {
		totalDuration := time.Unix(job.CompletedAt, 0).Sub(time.Unix(job.CreatedAt, 0))
		if totalDuration >= 0 {
			s.obsv.DistributionMs(ctx, "jobs.total_duration_ms", tags, totalDuration)
		}
	}

	// Emit jobs.execution_duration_ms: (completed_at - started_at)
	// This measures how long the agent actually executed
	if job.StartedAt > 0 && job.CompletedAt > 0 {
		executionDuration := time.Unix(job.CompletedAt, 0).Sub(time.Unix(job.StartedAt, 0))
		if executionDuration >= 0 {
			s.obsv.DistributionMs(ctx, "jobs.execution_duration_ms", tags, executionDuration)
		}
	}
}
