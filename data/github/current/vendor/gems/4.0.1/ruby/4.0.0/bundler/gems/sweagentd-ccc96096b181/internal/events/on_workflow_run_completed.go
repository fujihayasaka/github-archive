package events

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	gg "github.com/google/go-github/v75/github"
)

func (h *Handler) OnWorkflowRunCompleted(ctx context.Context, event WorkflowRunCompletedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.OnWorkflowRunCompleted")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)

	repoID := event.Repo.ID
	repoOwnerID := event.Repo.OwnerID
	run := event.WorkflowRun
	var session *capi.Session

	defer func() { h.emitWorkflowRunMetrics(ctx, session, run) }()

	computeID := strconv.FormatInt(run.ID, 10)
	job, err := h.jobsStore.GetJobForComputeID(ctx, repoOwnerID, repoID, computeID)
	if err != nil {
		return fmt.Errorf("getting job for workflow run %w", err)
	}

	// We should always have a job for agent workflows runs
	if job == nil {
		return errors.New("failed to find job for workflow run")
	}

	jobutils.UpdateRequestContextJob(ctx, h.obsv, job) //nolint:staticcheck // temporary during migration to jobservice
	if err := requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
		ID:     &job.PullRequestID,
		Number: job.PullRequestNumber,
	}); err != nil {
		logger.WithError(err).Error("failed to add pull request to context")
	}

	app, err := h.appProvider.FindByID(event.AgentID)
	if err != nil {
		return fmt.Errorf("failed to find agentic app by ID: %w", err)
	}

	gh, err := h.ghFactory.NewClientFromRepo(ctx, app, event.Repo.ID, event.Repo.OwnerID)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	repo, err := gh.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		return goerrors.Errorf("failed to get repository associated with assignment: %w", err)
	}

	logger.Info("processing workflow run completion for job", kvp.String("conclusion", run.Conclusion))
	workflowJobStatus, err := h.determineWorkflowJobStatus(ctx, gh, job, run)
	if err != nil {
		return fmt.Errorf("failed to determine workflow job status: %w", err)
	}
	logger.Info(fmt.Sprintf("determined workflow status is %s", workflowJobStatus.Status))

	// Create job error from workflow details
	jobError := workflowJobStatus.Details.ToJobError()

	// Finalize the job with the determined status
	err = h.jobService.FinalizeJob(ctx, job, workflowJobStatus.Status, jobError, run.CompletedAt) //nolint:staticcheck // temporary during migration to jobservice
	if err != nil {
		return fmt.Errorf("failed to finalize job: %w", err)
	}

	session, err = h.updateSessionFromWorkflow(ctx, gh, job, repo, workflowJobStatus.Details)
	if err != nil {
		return fmt.Errorf("failed to update session from workflow: %w", err)
	}

	actx, err := gh.GetPullRequestContext(ctx, job.RepoNodeID, job.PullRequestNumber, h.appProvider.IsAgenticActor)
	if err != nil {
		return fmt.Errorf("failed to get pull request context: %w", err)
	}

	// Remove the 👀 reactions from all comments and reviews for the job
	jobutils.RemoveReactionsForJob(ctx, h.obsv, gh, actx, job, h.appProvider.IsAgenticActor)

	// Emit step duration metrics for well-known steps
	h.emitWorkflowStepTelemetry(ctx, workflowJobStatus.Job)

	return h.handlePendingJobsForAssignment(ctx, gh, job, actx)
}

func (h *Handler) updateSessionFromWorkflow(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repo *gg.Repository, details *jobutils.WorkflowJobDetails) (*capi.Session, error) {
	// When UseAsyncSessions is true, sessions are managed by the upstream service, not sweagentd.
	if job.UseAsyncSessions {
		h.obsv.LoggerWithTelemetry(ctx).Info("skipping session update for async sessions job")
		return nil, nil
	}

	session, err := h.jobService.GetSessionForJob(ctx, job) //nolint:staticcheck // temporary during migration to jobservice
	if err != nil {
		return nil, fmt.Errorf("failed to get session for job: %w", err)
	}

	// Use pre-computed details
	sessionUpdate, err := jobutils.GetSessionUpdateForWorkflowRun(ctx, h.obsv, h.jobService, gh, job, session, details)
	if err != nil {
		return nil, fmt.Errorf("failed to get session update for workflow run: %w", err)
	}

	// TODO(colbylwilliams): For now, we don't want to fail the handler if we
	// can't finalize the session since we're still obligated to handle pending
	// jobs for the assignment. So we'll just log the error and move on
	if err := jobutils.FinalizeSessionForWorkflow(ctx, h.obsv, gh, h.ffClient, h.jobService, job, repo, *sessionUpdate); err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to finalize session")
		if limiter.IsAnyRateLimitError(err) {
			return nil, err
		}
	}

	return session.WithSessionUpdate(sessionUpdate), nil
}

func (h *Handler) emitWorkflowRunMetrics(ctx context.Context, session *capi.Session, run *WorkflowRun) {
	var sessionErrorCode string
	if session != nil && session.Error != nil && session.Error.Code != "" {
		sessionErrorCode = session.Error.Code
	}

	tags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"workflow_run_conclusion": run.Conclusion,
		"session_error_code":      sessionErrorCode,
	})
	h.obsv.Statter.DistributionMs("dynamic_workflow_completed", tags, time.Duration(run.UsageMs)*time.Millisecond)
}

// emitWorkflowStepTelemetry emits duration metrics for well-known workflow steps.
// It iterates through all steps in the workflow job and records a distribution metric
// for each step that matches our known step names (defined in launcher.ActionsWorkflowJobKnownSteps).
// When there are any failing steps, it also logs an event to Splunk with the failing steps.
func (h *Handler) emitWorkflowStepTelemetry(ctx context.Context, workflowJob *gg.WorkflowJob) {
	if workflowJob == nil {
		return
	}

	knownSteps := launcher.ActionsWorkflowJobKnownSteps()
	var failedSteps []string

	for _, step := range workflowJob.Steps {
		if step == nil {
			continue
		}

		stepName := step.GetName()

		// Only check known steps
		if stepName == "" || !slices.Contains(knownSteps, stepName) {
			continue
		}

		// Track failed steps
		conclusion := step.GetConclusion()
		if conclusion == "failure" {
			failedSteps = append(failedSteps, stepName)
		}

		// Calculate step duration
		startedAt := step.GetStartedAt()
		completedAt := step.GetCompletedAt()

		if startedAt.IsZero() || completedAt.IsZero() {
			continue
		}

		duration := completedAt.Time.Sub(startedAt.Time)
		if duration < 0 {
			continue
		}

		tags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
			"step_name":       stepName,
			"step_conclusion": conclusion,
		})
		h.obsv.Statter.DistributionMs("dynamic_workflow_step_duration", tags, duration)
	}

	// Log an event to Splunk if there are any failing steps
	if len(failedSteps) > 0 {
		logger := h.obsv.LoggerWithTelemetry(ctx)
		logger.Info("workflow steps failed",
			kvp.Strings("failed_steps", failedSteps),
		)
	}
}

func (h *Handler) handlePendingJobsForAssignment(ctx context.Context, gh github.ClientInterface, job *jobs.Job, actx *github.PullRequestContext) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.handlePendingJobsForAssignment")
	defer span.End()

	assignment, err := h.jobsStore.GetAssignment(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		return fmt.Errorf("failed to get assignment: %w", err)
	}

	logger := h.obsv.LoggerWithTelemetry(ctx)

	repo, err := gh.GetRepositoryByID(ctx, assignment.RepoID)
	if err != nil {
		return goerrors.Errorf("failed to get repository associated with assignment: %w", err)
	}

	allJobs, pendingJob, err := jobutils.JobsForAssignment(ctx, h.obsv, h.jobService, gh, h.ffClient, assignment, repo)
	if err != nil {
		return fmt.Errorf("failed to get jobs for assignment: %w", err)
	}

	if pendingJob == nil {
		logger.Info("No pending job to process")
		return nil
	}

	jobutils.UpdateRequestContextJob(ctx, h.obsv, pendingJob) //nolint:staticcheck // temporary during migration to jobservice

	if has, runningJobID := jobs.HasQueuedOrRunningJobs(allJobs); has {
		// TODO(colbylwilliams): We should only get here after a job reaches a
		// terminal state. Since only one job can be running at a time, if we got
		// here that's a bug. Log the error so we can investigate.
		logger.Error("Running job found after job completed for assignment",
			kvp.String("running_job_id", runningJobID))
		return nil
	}

	if actx == nil {
		actx, err = gh.GetPullRequestContext(ctx, job.RepoNodeID, job.PullRequestNumber, h.appProvider.IsAgenticActor)
		if err != nil {
			return fmt.Errorf("failed to get pull request context: %w", err)
		}
	}

	pr := actx.PullRequest

	// Make sure the PR is still open and the author is Agentic
	_, isAgenticActor := h.appProvider.IsAgenticActor(pr.Author)
	if pr.IsClosed() || !isAgenticActor {
		logger.Info("Not processing pending jobs because PR is closed or not authored by Agentic")
		return nil
	}

	pendingJob, err = jobutils.ProcessPendingJob(ctx, gh, actx, allJobs, pendingJob, h.appProvider.IsAgenticActor)
	if err != nil {
		return fmt.Errorf("failed to process pending job: %w", err)
	}

	// Reload the logger with any job fields that may have changed
	jobutils.UpdateRequestContextJob(ctx, h.obsv, pendingJob) //nolint:staticcheck // temporary during migration to jobservice
	logger = h.obsv.LoggerWithTelemetry(ctx)

	logger.Info("Processing pending job for pull request")

	problemStatement, err := problemstatement.NewPullRequestBuilder(h.obsv, actx, pendingJob, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.appProvider).Build(ctx)
	if err != nil {
		return fmt.Errorf("failed to create problem statement: %w", err)
	}
	pendingJob.ProblemStatement = problemStatement

	pendingJob, err = h.jobsStore.UpsertJob(ctx, pendingJob)
	if err != nil {
		return fmt.Errorf("failed to update job: %w", err)
	}

	jobutils.UpdateRequestContextJob(ctx, h.obsv, pendingJob) //nolint:staticcheck // temporary during migration to jobservice
	logger = h.obsv.LoggerWithTelemetry(ctx)

	logger.Info("Job upserted for pull request")

	logger.Info("Executing pending job for pull request")

	_, err = h.jobService.QueueJobForExecution(ctx, pendingJob)
	if err != nil {
		return fmt.Errorf("failed to queue job: %w", err)
	}

	return nil
}

type workflowStatus struct {
	Job     *gg.WorkflowJob
	Status  jobs.JobStatus
	Details *jobutils.WorkflowJobDetails
}

// determineWorkflowJobStatus analyzes the workflow run and job to determine the most accurate job status.
// If the workflow never started, or we fail to get the workflow details from the GitHub API,
// we fall back to a simple mapping from the workflow run conclusion to a job status.
func (h *Handler) determineWorkflowJobStatus(ctx context.Context, gh github.ClientInterface, job *jobs.Job, run *WorkflowRun) (*workflowStatus, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.String("conclusion", run.Conclusion))

	// There are a few cases where we'd return a basic status, without much info
	status := &workflowStatus{
		Job:     nil,
		Status:  jobutils.MapConclusionToJobStatus(run.Conclusion),
		Details: nil,
	}

	var workflowJob *gg.WorkflowJob
	var err error

	// Fetch repository information dynamically
	repo, err := gh.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		logger.WithError(err).Error("failed to get repository for job, falling back to conclusion mapping")
		return status, nil
	}
	workflowJobs, err := gh.ListWorkflowJobs(ctx, repo.Owner.GetLogin(), repo.GetName(), run.ID)
	if err != nil {
		logger.WithError(err).Error("failed to list workflow jobs, falling back to conclusion mapping")
		if limiter.IsAnyRateLimitError(err) {
			return nil, err
		}
		return status, nil
	}

	// We expect exactly one job for our workflow runs
	if len(workflowJobs) == 0 {
		logger.Warn("no workflow jobs found for workflow run, falling back to conclusion mapping")
		return status, nil
	}

	if len(workflowJobs) != 1 {
		logger.Warn("unexpected number of workflow jobs found for workflow run",
			kvp.Int("job_count", len(workflowJobs)))
		// Use the first job if there are multiple
	}

	workflowJob = workflowJobs[0]

	// If workflow job is nil, fall back to conclusion mapping without logging
	if workflowJob == nil {
		logger.Info("workflow job is nil, falling back to conclusion mapping")
		status.Job = workflowJob
		return status, nil
	}

	// Log workflow job details for analysis
	conclusion := ""
	if workflowJob.Conclusion != nil {
		conclusion = *workflowJob.Conclusion
	}
	logger.Info("retrieved workflow job for analysis",
		kvp.Int64("workflow_job_id", workflowJob.GetID()),
		kvp.String("name", workflowJob.GetName()),
		kvp.String("status", workflowJob.GetStatus()),
		kvp.String("conclusion", conclusion),
		kvp.Time("started_at", workflowJob.GetStartedAt().Time),
		kvp.Time("completed_at", workflowJob.GetCompletedAt().Time),
	)

	// We know the run completed because that triggered this Hydro event,
	// but Conclusion comes back as `null` sometimes, likely due to rate-limiting.
	// If it's `null`, return the conclusion we know of from the Hydro event. This
	// means we won't get details about failed steps, but at least the job status will
	// be accurate. See https://github.com/github/sweagentd/issues/6208
	if workflowJob.Conclusion == nil {
		logger.Info("workflow job conclusion is nil, falling back to conclusion mapping")
		status.Job = workflowJob

		// Add default error classification when conclusion is missing and job is not successful
		if h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentWorkflowErrorClassification, job) &&
			status.Status != jobs.JobStatusCompleted {
			status.Details = &jobutils.WorkflowJobDetails{
				WorkflowJob:  workflowJob,
				JobStatus:    status.Status,
				ErrorCode:    joberrors.ErrActionsMissingConclusion.String(),
				ErrorMessage: "Workflow completed but conclusion is not available. This may indicate rate limiting or API issues.",
			}
		}

		return status, nil
	}

	// Perform comprehensive analysis (job status, errors, failed steps)
	workflowJobDetails, err := jobutils.GetWorkflowDetails(ctx, h.obsv, gh, h.ffClient, job, repo, workflowJob, status.Status)
	if err != nil {
		logger.WithError(err).Error("failed to analyze workflow job, falling back to conclusion mapping")
		if limiter.IsAnyRateLimitError(err) {
			return nil, err
		}
		return status, nil
	}

	return &workflowStatus{
		Job:     workflowJob,
		Status:  workflowJobDetails.JobStatus,
		Details: workflowJobDetails,
	}, nil
}
