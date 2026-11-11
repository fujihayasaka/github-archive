// Package jobservice provides services for managing jobs (and sessions).
package jobservice

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/telemetry"
)

// ErrJobNotFound is returned when a job cannot be found in the store.
var ErrJobNotFound = errors.New("job not found")

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
}

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
) *Service {
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
	}
}

// GetJobsForAssignment retrieves all jobs associated with the given assignment.
func (s *Service) GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetJobsForAssignment")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("getting jobs for assignment")
	jobs, err := s.store.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		return nil, fmt.Errorf("failed to get jobs for assignment: %w", err)
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
		return nil, fmt.Errorf("failed to get job by id: %w", err)
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
		return nil, fmt.Errorf("failed to get job by session id: %w", err)
	}
	if job == nil {
		s.obsv.LoggerWithTelemetry(ctx).Info("no job found for session id", kvps...)
		return nil, ErrJobNotFound
	}

	s.updateRequestContextJob(ctx, job)
	s.addRequestCtxSessionFromJob(ctx, job)
	return job, nil
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
		return nil, nil, fmt.Errorf("invalid api job: missing owner_id, repository_id, assignment_id, or job_id")
	}

	assignment, err := s.store.GetAssignment(ctx, ownerID, repoID, assignmentID)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get assignment from store: %w", err)
	}
	if assignment == nil {
		return nil, nil, fmt.Errorf("assignment not found")
	}

	job, err := s.GetJobByID(ctx, ownerID, repoID, jobID)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get job from store: %w", err)
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
		return nil, fmt.Errorf("invalid agent job: missing owner_id, repository_id, assignment_id, or job_id")
	}

	job, err := s.GetJobByID(ctx, ownerID, repoID, jobID)
	if err != nil {
		return nil, fmt.Errorf("failed to get job from store: %w", err)
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

// SaveAssignment saves the given assignment to the store.
func (s *Service) SaveAssignment(ctx context.Context, assignment *jobs.Assignment) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.SaveAssignment")
	defer span.End()

	_, err := s.store.UpsertAssignment(ctx, assignment)
	if err != nil {
		return fmt.Errorf("failed to upsert assignment: %w", err)
	}
	return nil
}

// SaveJob saves the given job to the store.
func (s *Service) SaveJob(ctx context.Context, job *jobs.Job) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.SaveJob")
	defer span.End()

	_, err := s.store.UpsertJob(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to upsert job: %w", err)
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
		return nil, fmt.Errorf("failed to update job: %w", err)
	}

	s.updateRequestContextJob(ctx, job)

	jobs.StatJobTransition(ctx, s.obsv, s.obsv.TelemetryTags(ctx), prevJobStatus, job.Status)

	s.limiter.IncrementQueuedJobs(ctx, job.ActorID)

	return job, nil
}

// UpdateJobForLaunched updates the job status to running, sets the compute ID and
// launch time, and starts the associated session.
// This method also updates the job in the request context, records the job status transition,
func (s *Service) UpdateJobForLaunched(ctx context.Context, job *jobs.Job, computeID string, launchedAt int64) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.UpdateJobForLaunched")
	defer span.End()

	runID, err := strconv.ParseUint(computeID, 10, 64)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to parse compute ID")
		return nil, fmt.Errorf("failed to parse compute ID: %w", err)
	}

	job.ComputeID = computeID
	job.LaunchedAt = launchedAt

	prevJobStatus := job.Status
	job.Status = jobs.JobStatusRunning

	// update the job in the database
	job, err = s.store.UpdateJob(ctx, job)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update job for launched")
		return nil, fmt.Errorf("failed to update job: %w", err)
	}
	s.updateRequestContextJob(ctx, job)

	s.limiter.DecrementQueuedJobs(ctx, job.ActorID)
	s.limiter.IncrementRunningJobs(ctx, job.ActorID)

	// publish job_started telemetry event to Hydro
	telemetry.PublishJobStartTelemetry(ctx, s.obsv, s.ffs, job)

	jobs.StatJobTransition(ctx, s.obsv, s.obsv.TelemetryTags(ctx), prevJobStatus, job.Status)

	if err := s.startSession(ctx, nil, job, runID); err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to start session with compute ID")
		return nil, fmt.Errorf("failed to start session: %w", err)
	}

	return job, nil
}

// FinalizeUnexecutedJob finalizes a job that was never executed, updating its
// status and finalizing its associated session if applicable.
func (s *Service) FinalizeUnexecutedJob(ctx context.Context, job *jobs.Job, status jobs.JobStatus, errorMessage string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.FinalizeUnexecutedJob")
	defer span.End()

	sessionClient, err := s.getSessionClient(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to create session client: %w", err)
	}
	return s.finalizeUnexecutedJob(ctx, sessionClient, job, status, errorMessage)
}

// finalizeUnexecutedJob finalizes a job that was never executed, updating its
// status and finalizing its associated session if applicable. It requires a
// session client to avoid creating one unnecessarily.
func (s *Service) finalizeUnexecutedJob(ctx context.Context, sessionClient capi.SessionClient, job *jobs.Job, status jobs.JobStatus, errorMessage string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.finalizeUnexecutedJob")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("finalizing unexecuted job")
	completedAt := time.Now().Unix()

	if err := s.FinalizeJob(ctx, job, status, completedAt); err != nil {
		return fmt.Errorf("failed to finalize job: %w", err)
	}

	if job.SessionID != "" {
		s.obsv.LoggerWithTelemetry(ctx).Info("finalizing session for unexecuted job")
	}
	if err := s.finalizeUnexecutedSession(ctx, sessionClient, job, errorMessage); err != nil {
		s.obsv.LogAndReportError(ctx, err, "failed to finalize session")
	}

	return nil
}

// FinalizeJob finalizes the job by updating its status and completed time.
// It also handles decrementing the running job count and publishing telemetry events.
func (s *Service) FinalizeJob(ctx context.Context, job *jobs.Job, jobStatus jobs.JobStatus, completedAt int64) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.FinalizeJob")
	defer span.End()

	s.obsv.LoggerWithTelemetry(ctx).Info("finalizing job")

	tags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{"status": string(jobStatus)})
	s.obsv.Increment(ctx, "jobs.finalize", tags)

	if job.IsTerminal() && job.Status == jobStatus {
		s.obsv.LoggerWithTelemetry(ctx).Info("job is already in a terminal state, nothing to do")
		return nil // already in terminal state
	}

	prevJobStatus := job.Status

	patch := db.JobPatch{Status: &jobStatus}
	if job.CompletedAt == 0 {
		if completedAt == 0 {
			completedAt = time.Now().Unix()
		}
		patch.CompletedAt = &completedAt
	}

	fromQueued := job.Status == jobs.JobStatusQueued
	fromRunning := job.Status == jobs.JobStatusRunning

	if err := s.store.PatchJob(ctx, job, patch); err != nil {
		if errors.Is(err, db.ErrPreconditionFailedOnUpdate) {
			// Since we are in cleanup mode, fetch the latest job, confirm it is
			// in the expected terminal state, and retry the patch again if not.
			job, err = s.store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
			if err != nil {
				return fmt.Errorf("failed to get job after precondition failed on update: %w", err)
			}
			err = s.store.PatchJob(ctx, job, patch)
			if err != nil {
				return fmt.Errorf("failed to patch job after precondition failed on update: %w", err)
			}
		} else {
			return fmt.Errorf("failed to patch job: %w", err)
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

	telemetryPublisher := telemetry.NewTelemetryPublisher(s.obsv, s.twirp.UserDetailAPI(), s.ffs)

	if s.ffs.IsEnabledForUser(ctx, featureflags.CopilotSweAgentCommands, job.ActorID) {
		// We want to ensure all commands associated with the job are marked as "ignored"
		commands, err := s.store.GetCommandsWithStatus(ctx, job.AssignmentID, job.ID, command.StatusPending)
		if err != nil {
			return fmt.Errorf("failed to get pending commands for job: %w", err)
		}
		ignored := command.StatusIgnored
		err = s.store.BatchPatchCommands(ctx, commands, db.CommandPatch{Status: &ignored})
		if err != nil {
			return fmt.Errorf("failed to patch commands as ignored: %w", err)
		}

		for _, cmd := range commands {
			// Since we batch updated, we need to update the command in place to ensure
			// it reflects the actual state of the command.
			cmd.Status = ignored
			telemetryPublisher.PublishCommandUpdatedTelemetry(ctx, cmd)
		}
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("patched job with terminal status")

	telemetryPublisher.PublishJobCompletedTelemetry(ctx, job)

	return nil
}
