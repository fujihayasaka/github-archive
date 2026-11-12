package events

import (
	"bytes"
	"context"
	_ "embed"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"text/template"
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
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
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
	var job *jobs.Job
	var workflowJob *gg.WorkflowJob
	agentSlug := "unknown"

	defer func() { h.emitWorkflowRunMetrics(ctx, job, session, run, event.AgentID, agentSlug, workflowJob) }()

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

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return fmt.Errorf("failed to find agentic app by ID: %w", err)
	}
	agentSlug = app.ComputeSlug()
	jobservice.SetCtxAgent(ctx, h.obsv, h.ffClient, app, event.AgentID)

	gh, err := h.ghFactory.NewClientFromRepo(ctx, app, event.Repo.ID, event.Repo.OwnerID)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	repo, err := gh.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		return goerrors.Errorf("failed to get repository associated with assignment: %w", err)
	}

	// Track the effective job status for downstream PR logic. When the job is
	// already terminal we use its persisted status; otherwise we determine it
	// from the workflow run and finalize the job.
	effectiveStatus := job.Status

	// If the job is already in a terminal state (e.g. from a previous processing
	// attempt of this event), skip the expensive workflow analysis and finalization
	// to avoid unnecessary API calls that amplify rate limit pressure and cause
	// requeue loops.
	if !job.IsTerminal() {
		logger.Info("processing workflow run completion for job", kvp.String("conclusion", run.Conclusion))
		workflowJobStatus, err := h.determineWorkflowJobStatus(ctx, gh, job, run)
		if err != nil {
			return fmt.Errorf("failed to determine workflow job status: %w", err)
		}
		logger.Info(fmt.Sprintf("determined workflow status is %s", workflowJobStatus.Status))

		effectiveStatus = workflowJobStatus.Status
		workflowJob = workflowJobStatus.Job

		// Notify the PR about failed custom setup steps before FinalizeJob so a
		// downstream error can't leave the job terminal with the notification
		// permanently skipped.
		h.notifyCustomSetupStepFailure(ctx, gh, app, job, repo, run, workflowJobStatus.Details)

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

		// Emit step duration metrics for well-known steps
		h.emitWorkflowStepTelemetry(ctx, workflowJobStatus.Job)
	} else {
		logger.Info("job is already in a terminal state, skipping workflow analysis and finalization")
		h.obsv.Statter.Counter("workflow_run_completed.already_terminal", h.obsv.TelemetryTags(ctx), 1)
	}

	if job.PullRequestNumber != 0 {
		err := requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{
			ID:     &job.PullRequestID,
			Number: job.PullRequestNumber,
		})
		if err != nil {
			logger.WithError(err).Error("failed to add pull request to context")
		}
		actx, err := gh.GetPullRequestContext(ctx, job.RepoNodeID, job.PullRequestNumber, h.appProvider.IsAgenticActor)
		if err != nil {
			return fmt.Errorf("failed to get pull request context: %w", err)
		}

		// Request review from the actor who triggered the job.
		// This is done here (rather than in FinalizeSessionForWorkflow) so that it
		// runs regardless of whether the job uses async or sync sessions.
		// Skip if the actor is the PR author, since GitHub rejects self-review requests.
		// Skip if the app opts out of reviewer assignment via AgenticAppReviewerAssignment.
		actorIsPRAuthor := strings.EqualFold(job.ActorLogin, actx.PullRequest.Author.GetLogin())
		appSkipsReviewers := false
		if ra, ok := app.(sweagentd.AgenticAppReviewerAssignment); ok {
			appSkipsReviewers = !ra.AssignActorAsReviewer()
		}
		skipReviewRequest := actorIsPRAuthor || appSkipsReviewers ||
			(effectiveStatus == jobs.JobStatusCancelled &&
				h.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_skip_review_request_on_cancel", job))

		if skipReviewRequest {
			logger.Info("skipping PR review request")
		} else {
			logger.Info("requesting PR review")
			if err := gh.RequestReviewers(ctx, repo.Owner.GetLogin(), repo.GetName(), job.PullRequestNumber, []string{job.ActorLogin}); err != nil {
				h.obsv.LogAndReportError(ctx, err, "failed to request reviewers")
			}
		}

		// Remove the 👀 reactions from all comments and reviews for the job
		jobutils.RemoveReactionsForJob(ctx, h.obsv, gh, actx, job, h.appProvider.IsAgenticActor)

		err = h.handlePendingJobsForAssignment(ctx, gh, job, actx)
		if err != nil {
			return fmt.Errorf("failed to handle pending jobs for assignment: %w", err)
		}
	}
	return nil
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

func (h *Handler) emitWorkflowRunMetrics(ctx context.Context, job *jobs.Job, session *capi.Session, run *WorkflowRun, agentID int64, agentSlug string, workflowJob *gg.WorkflowJob) {
	// Prefer job.Error: it's populated locally by agentcallback.handleError for
	// both sync and async sessions and produces the same service:code string as
	// session.Error.Code. session.Error is unavailable locally for async (CMC
	// owns the session and the synchronous read races its write), so reading
	// from the job avoids that race. Fall back to session.Error.Code for safety.
	var sessionErrorCode string
	switch {
	case job != nil && job.Error != nil && job.Error.Summary() != "":
		sessionErrorCode = job.Error.Summary()
	case session != nil && session.Error != nil && session.Error.Code != "":
		sessionErrorCode = session.Error.Code
	}

	tags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"workflow_run_conclusion":       run.Conclusion,
		"session_error_code":            sessionErrorCode,
		"agent_id":                      strconv.FormatInt(agentID, 10),
		"agent_slug":                    agentSlug,
		"processing_request_conclusion": processingRequestConclusion(workflowJob),
	})
	h.obsv.Statter.DistributionMs("dynamic_workflow_completed", tags, time.Duration(run.UsageMs)*time.Millisecond)
}

// processingRequestConclusion returns the conclusion of the agent's "Processing
// Request" step in the dynamic workflow. This lets monitors distinguish failures
// in the agent itself (where Processing Request actually ran and failed) from
// failures in user-defined workflow steps that ran before/after it.
//
// Returns:
//   - "not_reached": the workflow job is unavailable, or both Linux/Windows
//     variants of Processing Request were skipped (wrong runner OS or an
//     earlier step failed). In all cases, the agent never ran.
//   - Otherwise: the GitHub-reported step conclusion verbatim. In practice this
//     is one of "success", "failure", "cancelled", or "timed_out", though
//     GitHub may also report "neutral", "action_required", or "stale". For
//     success-rate monitors, treat any non-"success" value as a failure.
func processingRequestConclusion(workflowJob *gg.WorkflowJob) string {
	const notReached = "not_reached"
	if workflowJob == nil {
		return notReached
	}
	for _, step := range workflowJob.Steps {
		if step == nil {
			continue
		}
		name := step.GetName()
		if name != "Processing Request (Linux)" && name != "Processing Request (Windows)" {
			continue
		}
		conclusion := step.GetConclusion()
		// Linux/Windows variants are mutually exclusive via runner.os checks; the
		// non-matching variant always reports "skipped". Only return when we find
		// the variant that actually executed.
		if conclusion != "" && conclusion != "skipped" {
			return conclusion
		}
	}
	return notReached
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

	// Make sure the PR is still open
	if pr.IsClosed() {
		logger.Info("Not processing pending jobs because PR is closed")
		return nil
	}

	pendingJob, err = jobutils.ProcessPendingJob(ctx, h.obsv, gh, actx, allJobs, pendingJob, h.appProvider.IsAgenticActor)
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

// ccrSetupStepFailureTelemetryKey is the telemetry key embedded in the PR
// comment so the body matches joberrors.IsCopilotErrorComment and
// CreateErrorComment doesn't append a generic marker on top.
const ccrSetupStepFailureTelemetryKey = "ccr-setup-step-failure"

//go:embed ccr_setup_step_failure_comment.md
var ccrSetupStepFailureCommentTemplate string

// notifyCustomSetupStepFailure posts a PR comment listing failed custom setup
// steps when the agentic app opts in via AgenticAppSetupStepFailureNotifier.
// CCR opts in; CCA does not. See github/copilot-code-review#2166.
//
// Errors are logged and swallowed so they cannot derail the rest of the
// workflow-run completion flow.
func (h *Handler) notifyCustomSetupStepFailure(
	ctx context.Context,
	gh github.ClientInterface,
	app sweagentd.AgenticApp,
	job *jobs.Job,
	repo *gg.Repository,
	run *WorkflowRun,
	details *jobutils.WorkflowJobDetails,
) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	if details == nil {
		return
	}
	if job.PullRequestNumber == 0 {
		return
	}

	notifier, ok := app.(sweagentd.AgenticAppSetupStepFailureNotifier)
	if !ok || !notifier.NotifyOnSetupStepFailure() {
		return
	}

	rawNames := collectFailedUserSetupStepNames(details.WorkflowJob)
	if len(rawNames) == 0 {
		return
	}

	failedStepNames := make([]string, len(rawNames))
	for i, name := range rawNames {
		failedStepNames[i] = sanitizeCCRSetupStepName(name)
	}

	body, err := renderCCRSetupStepFailureComment(failedStepNames, ccrSetupStepFailureRunURL(repo, run))
	if err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to render CCR setup step failure comment")
		return
	}

	if err := joberrors.CreateErrorComment(ctx, h.obsv, gh, job.RepoID, job.PullRequestNumber, body); err != nil {
		h.obsv.LogAndReportError(ctx, err, "failed to create CCR setup step failure PR comment")
		return
	}

	logger.Info("posted CCR setup step failure PR comment",
		kvp.Int("failed_step_count", len(failedStepNames)),
	)
	h.obsv.Statter.Counter("ccrSetupStepFailureComment.posted", h.obsv.TelemetryTags(ctx), 1)
}

// sanitizeCCRSetupStepName scrubs a user-controlled step name so it cannot
// break out of the surrounding Markdown fenced code block.
func sanitizeCCRSetupStepName(name string) string {
	// A triple backtick on its own line would terminate the fence.
	return strings.ReplaceAll(strings.TrimSpace(name), "```", "")
}

// collectFailedUserSetupStepNames returns the trimmed display names of failed
// steps that fall between sweagentd's user-step wrapper markers in the workflow
// job timeline. Each inlined step from the user's copilot-setup-steps.yml is
// bracketed by a "Starting User Configured Setup Step (Linux|Windows)" pair
// before it and a matching "Finished..." pair after it (see
// launcher.sessionLogStepLinux / launcher.sessionLogStepWindows). Steps that
// fall outside any wrapper pair (dynamic-workflow framework steps,
// runner-injected steps like "Set up job" or self-hosted runner job hooks)
// are excluded by construction.
//
// Region scoping and failure detection happen in a single pass so this
// function does not depend on jobutils.getFailedSteps continuing to preserve
// *gg.TaskStep pointer identity between WorkflowJob.Steps and FailedSteps.
// Conclusion comparison uses the same "failure" sentinel that getFailedSteps
// uses, so behavior matches the long-standing convention for what counts as
// a failed step.
//
// Names returned are in timeline order and trimmed of surrounding whitespace,
// but are NOT sanitized for Markdown - callers MUST apply
// sanitizeCCRSetupStepName before embedding them in user-visible output. The
// iteration uses a single boolean toggle, which is sufficient for the
// emitted shape (matched Start/Finish pairs, one per user step). An orphan
// Start with no Finish would cause every subsequent failed step to be
// collected; an orphan Finish before any Start is a no-op.
func collectFailedUserSetupStepNames(workflowJob *gg.WorkflowJob) []string {
	if workflowJob == nil {
		return nil
	}
	var names []string
	inside := false
	for _, step := range workflowJob.Steps {
		if step == nil {
			continue
		}
		name := strings.TrimSpace(step.GetName())
		switch name {
		case launcher.UserSetupStepStartLinuxName, launcher.UserSetupStepStartWindowsName:
			inside = true
		case launcher.UserSetupStepFinishLinuxName, launcher.UserSetupStepFinishWindowsName:
			inside = false
		default:
			if !inside || name == "" {
				continue
			}
			if step.GetConclusion() != "failure" {
				continue
			}
			names = append(names, name)
		}
	}
	return names
}

// renderCCRSetupStepFailureComment builds the PR comment body. Step names must
// already be sanitised via sanitizeCCRSetupStepName.
func renderCCRSetupStepFailureComment(failedStepNames []string, runURL string) (string, error) {
	tmpl, err := template.New("ccr_setup_step_failure_comment").Parse(ccrSetupStepFailureCommentTemplate)
	if err != nil {
		return "", goerrors.Errorf("failed to parse template: %w", err)
	}

	var buf bytes.Buffer
	err = tmpl.Execute(&buf, &struct {
		FailedSteps []string
		Plural      bool
		RunURL      string
		Telemetry   string
	}{
		FailedSteps: failedStepNames,
		Plural:      len(failedStepNames) > 1,
		RunURL:      runURL,
		Telemetry:   joberrors.GetTelemetryHTMLComment(ccrSetupStepFailureTelemetryKey),
	})
	if err != nil {
		return "", goerrors.Errorf("failed to execute template: %w", err)
	}
	body := buf.String()
	if body == "" {
		return "", goerrors.New("rendered comment body is empty")
	}
	return body, nil
}

// ccrSetupStepFailureRunURL returns the HTML URL of the workflow run, or an
// empty string when we can't build one.
func ccrSetupStepFailureRunURL(repo *gg.Repository, run *WorkflowRun) string {
	if repo == nil || run == nil {
		return ""
	}
	repoURL := repo.GetHTMLURL()
	if repoURL == "" {
		return ""
	}
	return fmt.Sprintf("%s/actions/runs/%d", repoURL, run.ID)
}
