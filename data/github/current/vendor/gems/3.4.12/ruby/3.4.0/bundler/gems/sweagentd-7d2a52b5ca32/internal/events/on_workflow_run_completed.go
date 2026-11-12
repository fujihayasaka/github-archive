package events

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	gg "github.com/google/go-github/v75/github"
)

func (h *Handler) OnWorkflowRunCompleted(ctx context.Context, event WorkflowRunCompletedEvent) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.OnWorkflowRunCompleted")
	defer span.End()

	logger := h.obsv.LoggerWithTelemetry(ctx)

	repo := event.Repo
	run := event.WorkflowRun
	var session *capi.Session

	defer func() { h.emitWorkflowRunMetrics(ctx, session, run) }()

	// short circuit if the workflow run is not for the copilot-swe-agent
	if !strings.HasPrefix(run.Path, "dynamic/copilot-swe-agent/") {
		h.obsv.LoggerWithTelemetry(ctx).Info("Ignoring workflow run because it is not for the copilot-swe-agent")
		return nil
	}

	computeID := strconv.FormatInt(run.ID, 10)
	job, err := h.jobsStore.GetJobForComputeID(ctx, repo.OwnerID, repo.ID, computeID)
	if err != nil {
		return fmt.Errorf("getting job for workflow run %w", err)
	}

	// We should always have a job for dynamic/copilot-swe-agent workflows runs
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

	gh, err := h.ghFactory.NewClientFromRepo(ctx, event.Repo.ID, event.Repo.OwnerID)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	logger.Info("processing workflow run completion for job", kvp.String("conclusion", run.Conclusion))
	workflowJobStatus, err := h.determineWorkflowJobStatus(ctx, gh, job, run)
	if err != nil {
		return fmt.Errorf("failed to determine workflow job status: %w", err)
	}
	logger.Info(fmt.Sprintf("determined workflow status is %s", workflowJobStatus.Status))

	// Finalize the job with the determined status
	err = h.jobService.FinalizeJob(ctx, job, workflowJobStatus.Status, run.CompletedAt) //nolint:staticcheck // temporary during migration to jobservice
	if err != nil {
		return fmt.Errorf("failed to finalize job: %w", err)
	}

	session, err = h.updateSessionFromWorkflow(ctx, gh, job, workflowJobStatus.Details)
	if err != nil {
		return fmt.Errorf("failed to update session from workflow: %w", err)
	}

	actx, err := gh.GetPullRequestContext(ctx, job.RepoNodeID, job.PullRequestNumber)
	if err != nil {
		return fmt.Errorf("failed to get pull request context: %w", err)
	}

	// Remove the 👀 reactions from all comments and reviews for the job
	jobutils.RemoveReactionsForJob(ctx, h.obsv, gh, actx, job)

	return h.handlePendingJobsForAssignment(ctx, gh, job, actx)
}

func (h *Handler) updateSessionFromWorkflow(ctx context.Context, gh github.ClientInterface, job *jobs.Job, details *jobutils.WorkflowJobDetails) (*capi.Session, error) {
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
	if err := jobutils.FinalizeSessionForWorkflow(ctx, h.obsv, gh, h.ffClient, h.jobService, job, *sessionUpdate); err != nil {
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

func (h *Handler) handlePendingJobsForAssignment(ctx context.Context, gh github.ClientInterface, job *jobs.Job, actx *github.PullRequestContext) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.handlePendingJobsForAssignment")
	defer span.End()

	assignment, err := h.jobsStore.GetAssignment(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		return fmt.Errorf("failed to get assignment: %w", err)
	}

	logger := h.obsv.LoggerWithTelemetry(ctx)

	allJobs, pendingJob, err := jobutils.JobsForAssignment(ctx, h.obsv, h.jobService, gh, h.ffClient, assignment)
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
		actx, err = gh.GetPullRequestContext(ctx, job.RepoNodeID, job.PullRequestNumber)
		if err != nil {
			return fmt.Errorf("failed to get pull request context: %w", err)
		}
	}

	pr := actx.PullRequest

	// Make sure the PR is still open and the author is Copilot
	if pr.IsClosed() || !pr.Author.IsCopilot(gh) {
		logger.Info("Not processing pending jobs because PR is closed or not authored by Copilot")
		return nil
	}

	pendingJob, err = jobutils.ProcessPendingJob(ctx, gh, actx, allJobs, pendingJob)
	if err != nil {
		return fmt.Errorf("failed to process pending job: %w", err)
	}

	// Reload the logger with any job fields that may have changed
	jobutils.UpdateRequestContextJob(ctx, h.obsv, pendingJob) //nolint:staticcheck // temporary during migration to jobservice
	logger = h.obsv.LoggerWithTelemetry(ctx)

	logger.Info("Processing pending job for pull request")

	problemStatement, err := problemstatement.NewPullRequestBuilder(h.obsv, gh, actx, pendingJob, githubtwirp.NewAuthorResolver(h.obsv, h.ghTwirp, h.ffClient), h.ffClient).Build(ctx)
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

	// If the run doesn't have a Job ID, it's because the workflow never started
	if run.JobID == nil {
		logger.Warn("workflow run has no job ID, falling back to conclusion mapping")
		return status, nil
	}

	workflowJob, err := gh.GetWorkflowJobByID(ctx, job.RepoOwner, job.RepoName, *run.JobID)
	if err != nil {
		logger.WithError(err).Error("failed to get workflow job by ID, falling back to conclusion mapping")
		if limiter.IsAnyRateLimitError(err) {
			return nil, err
		}
		return status, nil
	}

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
		return status, nil
	}

	// Perform comprehensive analysis (job status, errors, failed steps)
	workflowJobDetails, err := jobutils.GetWorkflowDetails(ctx, h.obsv, gh, job, workflowJob, status.Status)
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
