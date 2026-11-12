package jobutils

import (
	"cmp"
	"context"
	"fmt"
	"slices"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	gg "github.com/google/go-github/v75/github"
)

// DefaultSessionErrorMessage is the default error message shown when Copilot encounters an unspecified error.
const DefaultSessionErrorMessage string = "Copilot has encountered an error. See logs for additional details."

type jobService interface {
	GetSessionForJob(ctx context.Context, job *jobs.Job) (*capi.Session, error)
	GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error)
	UpdateSession(ctx context.Context, job *jobs.Job, update capi.SessionUpdate) error
	FinalizeJob(ctx context.Context, job *jobs.Job, jobStatus jobs.JobStatus, jobError *jobs.JobError, completedAt int64) error
}

// JobsForAssignment returns all jobs for a assignment, as well as the pending job (if any).
// If there are multiple pending jobs, an error is returned.
func JobsForAssignment(ctx context.Context, obsv observability.Exporters, service jobService, gh github.ClientInterface, ffClient featureflags.Client, assignment *jobs.Assignment, repo *gg.Repository) (all []*jobs.Job, pending *jobs.Job, err error) {
	var pendingJob *jobs.Job

	allJobs, err := service.GetJobsForAssignment(ctx, assignment)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get jobs for assignment: %w", err)
	}

	for _, job := range allJobs {
		if job.IsPending() {
			if pendingJob != nil {
				// There should only ever be one pending job for an assignment.
				return nil, nil, goerrors.Errorf("multiple pending jobs found for assignment %s", assignment.ID)
			}
			pendingJob = job
		}
		if job.IsRunning() {
			// If the job status running, confirm that it is actually still running
			// and not stuck in a inaccurate state because of a failed action run
			err := confirmRunningJob(ctx, obsv, service, gh, ffClient, job, repo)
			if err != nil {
				return nil, nil, goerrors.Errorf("failed to confirm running job: %w", err)
			}
		}
	}

	return allJobs, pendingJob, nil
}

// confirmRunningJob confirms that a job is still running by querying the workflow
// run and updates the job status if it is not.
//
// Today this is Actions-specific: it lists workflow jobs and checks their
// conclusion. As other launchers (e.g., Sandbox) gain their own finalization
// lifecycle, this should be refactored into a launcher interface method like
// AgentLauncher.ConfirmCompute so each launcher can check health and report
// completion through its own backend.
//
// TODO: Add a ConfirmCompute method to the AgentLauncher interface so sandbox
// jobs get their own health check instead of being silently skipped.
func confirmRunningJob(ctx context.Context, obsv observability.Exporters, service jobService, gh github.ClientInterface, ffClient featureflags.Client, job *jobs.Job, repo *gg.Repository) error {
	// ignore jobs that aren't running
	if job.Status != jobs.JobStatusRunning {
		return nil
	}

	// ignore jobs that aren't running on Actions
	// (or those created before we started tracking the launcher)
	if job.Launcher != "" && job.Launcher != launcher.TypeActions {
		return nil
	}

	UpdateRequestContextJob(ctx, obsv, job) //nolint:staticcheck // temporary during migration to jobservice
	obsv.LoggerWithTelemetry(ctx).Info("confirming running job status")

	// If the job is in a 'running' state, and there is no compute ID, it almost
	// certainly means something went wrong when we tried to launch the job.
	if job.ComputeID == "" {
		obsv.Statter.Counter("jobs.found_job_in_unexpected_state", obsv.TelemetryTags(ctx).Merge(stats.Tags{"reason": "empty_compute_id"}), 1)
		return goerrors.Errorf("found no compute ID for running job %s", job.ID)
	}

	runID, ok := job.WorkflowRunID()
	if !ok {
		obsv.Statter.Counter("jobs.found_job_in_unexpected_state", obsv.TelemetryTags(ctx).Merge(stats.Tags{"reason": "invalid_compute_id"}), 1)
		return goerrors.Errorf("failed to parse compute ID %q for running job %s", job.ComputeID, job.ID)
	}

	originalWorkflowCtx, _ := requestctx.WorkflowRun(ctx)
	err := requestctx.AddWorkflowRun(ctx, &requestctx.CtxWorkflowRun{ID: runID})
	if err != nil {
		obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add workflow run to context")
	}

	workflowJobs, err := gh.ListWorkflowJobs(ctx, repo.GetOwner().GetLogin(), repo.GetName(), runID)
	if err != nil {
		return goerrors.Errorf("failed to list workflow jobs for running job: %w", err)
	}

	// Bots (including ours) can comment on PR creation, workflow start, etc. so
	// there's a small, but non-zero chance that the workflow run has no jobs yet.
	// If this happens, we assume it's not an error or unexpected state, and just
	// return nil. We'll get another chance to confirm the job status later.
	if len(workflowJobs) == 0 {
		return nil
	}

	// This, on the other hand, is an error. We expect exactly one job (today).
	if len(workflowJobs) != 1 {
		return goerrors.New("unexpected number of workflow jobs found for running job")
	}

	workflowJob := workflowJobs[0]

	// only workflow runs in a final state will have a conclusion
	conclusion := workflowJob.GetConclusion()
	if conclusion == "" {
		obsv.LoggerWithTelemetry(ctx).Info("confirmed job is still running")

		// clean up the context
		UpdateRequestContextJob(ctx, obsv, nil) //nolint:staticcheck // temporary during migration to jobservice
		err = requestctx.AddWorkflowRun(ctx, originalWorkflowCtx)
		if err != nil {
			obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add workflow run to context")
		}

		return nil // still running
	}

	obsv.LoggerWithTelemetry(ctx).Info("workflow job concluded, finalizing job")

	// Perform comprehensive analysis of the workflow job (job status, errors, failed steps)
	workflowDetails, err := GetWorkflowDetails(ctx, obsv, gh, ffClient, job, repo, workflowJob, jobs.JobStatusFailed)
	if err != nil {
		return goerrors.Errorf("failed to get workflow details: %w", err)
	}

	jobError := workflowDetails.ToJobError()
	err = service.FinalizeJob(ctx, job, workflowDetails.JobStatus, jobError, workflowJob.GetCompletedAt().Unix())
	if err != nil {
		return goerrors.Errorf("failed to finalize job: %w", err)
	}

	// When UseAsyncSessions is true, sessions are no longer managed by sweagentd.
	if !job.UseAsyncSessions {
		if job.SessionID == "" {
			obsv.LoggerWithTelemetry(ctx).Info("no session ID found for job, skipping session finalization")
			// clean up the context
			UpdateRequestContextJob(ctx, obsv, nil)
			err = requestctx.AddWorkflowRun(ctx, originalWorkflowCtx)
			if err != nil {
				obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add workflow run to context")
			}
			return nil
		}

		session, err := service.GetSessionForJob(ctx, job)
		if err != nil {
			return goerrors.Errorf("failed to get session for job: %w", err)
		}

		sessionUpdate, err := GetSessionUpdateForWorkflowRun(ctx, obsv, service, gh, job, session, workflowDetails)
		if err != nil {
			return goerrors.Errorf("failed to get session update for workflow run: %w", err)
		}
		err = FinalizeSessionForWorkflow(ctx, obsv, gh, ffClient, service, job, repo, *sessionUpdate)
		if err != nil {
			return goerrors.Errorf("failed to finalize job session: %w", err)
		}
	}

	// Request review from the actor who triggered the job.
	// This runs regardless of session type (sync or async).
	// Skip if the actor is the PR author, since GitHub rejects self-review requests.
	if job.PullRequestNumber != 0 {
		actorIsPRAuthor := false
		pr, prErr := gh.GetPullRequest(ctx, job.RepoID, job.PullRequestNumber)
		if prErr != nil {
			obsv.LogAndReportError(ctx, prErr, "failed to get pull request for review request check")
		} else {
			actorIsPRAuthor = strings.EqualFold(job.ActorLogin, pr.GetUser().GetLogin())
		}

		skipReviewRequest := actorIsPRAuthor ||
			(workflowDetails.JobStatus == jobs.JobStatusCancelled &&
				ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_skip_review_request_on_cancel", job))

		if skipReviewRequest {
			obsv.LoggerWithTelemetry(ctx).Info("skipping PR review request")
		} else {
			obsv.LoggerWithTelemetry(ctx).Info("requesting PR review")
			err = gh.RequestReviewers(ctx, repo.Owner.GetLogin(), repo.GetName(), job.PullRequestNumber, []string{job.ActorLogin})
			if err != nil {
				obsv.LogAndReportError(ctx, err, "failed to request reviewers")
			}
		}
	}

	// clean up the context
	UpdateRequestContextJob(ctx, obsv, nil) //nolint:staticcheck // temporary during migration to jobservice
	err = requestctx.AddWorkflowRun(ctx, originalWorkflowCtx)
	if err != nil {
		obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add workflow run to context")
	}

	return nil
}

// FinalizeSessionForWorkflow finalizes the session associated with a workflow run/job.
//
// TODO (colbylwilliams): move this to on_workflow_run_completed.go
func FinalizeSessionForWorkflow(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, ffClient featureflags.Client, service jobService, job *jobs.Job, repo *gg.Repository, sessionUpdate capi.SessionUpdate) error {
	logger := obsv.LoggerWithTelemetry(ctx)
	logger.Info("finalizing session for workflow run")

	if job == nil {
		return goerrors.New("parameter Job is nil")
	}

	if !sessionUpdate.HasUpdate() {
		return nil // nothing to update
	}

	_ = requestctx.AddSession(ctx, &requestctx.CtxSession{
		ResourceType: string(capi.ResourceTypePullRequest),
		ResourceID:   job.PullRequestID,
		EventType:    string(job.EventType),
		HeadRef:      job.BranchName,
		BaseRef:      job.BaseCommit,
	})

	if !job.IsTerminal() {
		logger.Info("job is not in a terminal state, nothing to do")
		return nil
	}

	if job.SessionID == "" {
		logger.Info("no session ID found for job")
		return nil
	}

	err := service.UpdateSession(ctx, job, sessionUpdate)
	if err != nil {
		return goerrors.Errorf("failed to update session: %w", err)
	}

	if sessionUpdate.State == "" {
		logger.Info("finalized job session")
	} else {
		logger.Info(fmt.Sprintf("finalized job session to state %s", sessionUpdate.State))
	}

	return nil
}

// GetSessionUpdateForWorkflowRun returns a SessionUpdate based on the workflow run details and job status.
//
// TODO (colbylwilliams): move this to on_workflow_run_completed.go
func GetSessionUpdateForWorkflowRun(ctx context.Context, obsv observability.Exporters, service jobService, gh github.ClientInterface, job *jobs.Job, session *capi.Session, workflowDetails *WorkflowJobDetails) (*capi.SessionUpdate, error) {
	logger := obsv.LoggerWithTelemetry(ctx)

	if job == nil {
		return nil, goerrors.New("parameter job is nil")
	}
	if capi.IsFinalState(session.State) {
		// Session is already in a final state, nothing to do
		logger.Info("session is already in a final state")
		return &capi.SessionUpdate{}, nil
	}

	newState := capi.MapJobStatusToSessionState(job.Status)
	if newState == "" {
		logger.Error("failed to map job status to session state", kvp.String("job.status", string(job.Status)))
		return &capi.SessionUpdate{}, nil
	}
	session.State = newState
	sessionUpdate := capi.SessionUpdate{State: newState}

	// There's no workflow details to get a deeper understanding on
	if workflowDetails == nil {
		// Only log if the session is failed and there's no existing error
		hasError := session.Error != nil && session.Error.Message != ""
		if session.State == capi.SessionStateFailed && !hasError {
			logger.Info("session is failed but no error info is provided")
		}
		return &sessionUpdate, nil
	}

	// If the job failed, and the session doesn't already have an error message,
	// use the workflow job details to create a useful error
	hasError := session.Error != nil && session.Error.Message != ""
	if (session.State == capi.SessionStateFailed || session.State == capi.SessionStateCancelled || session.State == capi.SessionStateTimedOut) && !hasError {
		var errorCode string
		var errorMessage string

		if workflowDetails.ErrorCode != "" || workflowDetails.ErrorMessage != "" {
			errorCode = workflowDetails.ErrorCode
			errorMessage = workflowDetails.ErrorMessage
		}

		// If we have an error message, set it on the session
		if errorCode != "" || errorMessage != "" {
			session.Error = &capi.SessionError{Code: errorCode, Message: errorMessage}
		} else {
			session.Error = &capi.SessionError{Code: joberrors.ErrInternalError.String(), Message: DefaultSessionErrorMessage}
		}
		sessionUpdate.Error = session.Error
	}

	UpdateRequestContextSession(ctx, obsv, sessionUpdate) //nolint:staticcheck // temporary during migration to jobservice
	return &sessionUpdate, nil
}

// getFailedSteps returns all failed steps from the workflow job and optionally an error message for custom setup steps
func getFailedSteps(workflowJob *gg.WorkflowJob) (steps []*gg.TaskStep, errorCode, errorMessage string) {
	steps = make([]*gg.TaskStep, 0)

	if workflowJob == nil {
		return steps, "", ""
	}

	// Get all failed steps
	for _, step := range workflowJob.Steps {
		if step.GetConclusion() == "failure" {
			steps = append(steps, step)
		}
	}

	const failure string = "failure"
	var failedStep *gg.TaskStep

	if workflowJob.Conclusion == nil || *workflowJob.Conclusion != failure {
		return steps, errorCode, errorMessage
	}

	// Find first failed step for error message
	for _, step := range workflowJob.Steps {
		if step.Conclusion != nil && *step.Conclusion == failure {
			failedStep = step
			break
		}
	}

	if failedStep != nil && failedStep.Name != nil {
		// If the step is a "known" step (part of our dynamic workflow), we don't
		// want to include a custom error message with the failed step name.
		if !slices.Contains(launcher.ActionsWorkflowJobKnownSteps(), failedStep.GetName()) {
			errorCode = joberrors.ErrActionsSetupSteps.String()
			errorMessage = fmt.Sprintf("The %q custom setup step from your .github/workflows/copilot-setup-steps.yml file failed.", *failedStep.Name)
		} else {
			notSupportedMap := launcher.ActionsWorkflowNotSupportedStepsWithErrorMessage()
			if message, exists := notSupportedMap[failedStep.GetName()]; exists {
				errorCode = joberrors.ErrActionsNotSupported.String()
				errorMessage = message
			}
		}
	}

	return steps, errorCode, errorMessage
}

// It is unfortunate we have to resort to these arbitrary annotation strings to identify specific issues.
// But at the time of writing, Actions API doesn't always reveal the correct info (e.g. conclusion being cancelled for timed-out workflows).
const (
	billingLockedError         string = "The job was not started because your account is locked due to a billing issue."
	paymentFailedError         string = "The job was not started because recent account payments have failed or your spending limit needs to be increased."
	actionsBudgetError         string = "The job was not started because an Actions budget is preventing further use."
	exitCode137Error           string = "Process completed with exit code 137"
	exitCode143Error           string = "Process completed with exit code 143"
	outOfDiskSpaceError        string = "No space left on device"
	runningTimedOutError       string = "The job has exceeded the maximum execution time of"
	userCancelledError         string = "The run was canceled by @"
	waitingTimedOutError       string = "The job has exceeded the maximum execution time while awaiting a runner for"
	selfHostedRunnerLostError  string = "The self-hosted runner lost communication with the server"
	billingOwnerDestroyedError string = "billing owner destroyed"
	exitCode6Error             string = "Process completed with exit code 6"
	operationCancelledError    string = "The operation was canceled"
	repositoryArchivedError    string = "repository archived"
	repositoryTransferredError string = "repository transferred"
	runnerNotAcquiredError     string = "The job was not acquired by Runner"
	actionsDisabledError       string = "GitHub Actions hosted runners are disabled for this repository"
)

func annotationContainError(annotations []*gg.CheckRunAnnotation, level, errorMessage string) bool {
	for _, annotation := range annotations {
		if annotation.AnnotationLevel != nil && *annotation.AnnotationLevel == level {
			if annotation.Message != nil && strings.Contains(*annotation.Message, errorMessage) {
				return true
			}
		}
	}

	return false
}

func logUnknownAnnotations(logger log.Logger, annotations []*gg.CheckRunAnnotation, conclusion string) {
	for _, annotation := range annotations {
		if annotation.Message != nil && annotation.AnnotationLevel != nil {
			logger.Warn(fmt.Sprintf("unknown %s annotation: (%s) %s", conclusion, *annotation.AnnotationLevel, *annotation.Message))
		}
	}
}

// setFailureErrorFromAnnotations checks failure annotations and sets the appropriate error code and message.
// Returns true if an error was detected and set.
func setFailureErrorFromAnnotations(annotations []*gg.CheckRunAnnotation, workflowDetails *WorkflowJobDetails) bool {
	if annotations == nil {
		return false
	}

	switch {
	case annotationContainError(annotations, "failure", billingLockedError):
		workflowDetails.ErrorCode = joberrors.ErrActionsBillingLocked.String()
		workflowDetails.ErrorMessage = "The job was not started because the account is locked due to a billing issue."
	case annotationContainError(annotations, "failure", paymentFailedError):
		workflowDetails.ErrorCode = joberrors.ErrActionsBillingLocked.String()
		workflowDetails.ErrorMessage = "The job was not started because recent GitHub Actions payments have failed or your spending limit needs to be increased."
	case annotationContainError(annotations, "failure", actionsBudgetError):
		workflowDetails.ErrorCode = joberrors.ErrActionsBillingLocked.String()
		workflowDetails.ErrorMessage = "The job was not started because a GitHub Actions budget is preventing further Actions use."
	case annotationContainError(annotations, "failure", exitCode137Error):
		workflowDetails.ErrorCode = joberrors.ErrActionsOutOfMemory.String()
		workflowDetails.ErrorMessage = "Copilot had to stop work because it ran out of memory. If you see this regularly in this repository, you may need to switch to using GitHub Actions larger runners. For more information, see https://gh.io/copilot-coding-agent-larger-runners."
	case annotationContainError(annotations, "failure", exitCode143Error):
		workflowDetails.ErrorCode = joberrors.ErrActionsTerminated.String()
		workflowDetails.ErrorMessage = "The agent was terminated unexpectedly (exit code 143). This typically indicates the job was forcefully stopped."
	case annotationContainError(annotations, "failure", selfHostedRunnerLostError):
		workflowDetails.ErrorCode = joberrors.ErrActionsSelfHostedRunnerLost.String()
		workflowDetails.ErrorMessage = "The job stopped because the GitHub Actions self-hosted runner lost connection to the server."
	case annotationContainError(annotations, "failure", outOfDiskSpaceError):
		workflowDetails.ErrorCode = joberrors.ErrActionsOutOfDiskSpace.String()
		workflowDetails.ErrorMessage = "Copilot had to stop work due to insufficient disk space. If you see this regularly in this repository, you may need to switch to using GitHub Actions larger runners. For more information, see https://gh.io/copilot-coding-agent-larger-runners."
	case annotationContainError(annotations, "failure", actionsDisabledError):
		workflowDetails.ErrorCode = joberrors.ErrActionsDisabled.String()
		workflowDetails.ErrorMessage = "The job failed because GitHub Actions hosted runners are disabled for this repository."
	default:
		return false
	}
	return true
}

// setCancelledErrorFromAnnotations checks cancellation annotations and sets the appropriate error code and message.
// Returns true if a cancellation reason was detected and set.
func setCancelledErrorFromAnnotations(annotations []*gg.CheckRunAnnotation, workflowDetails *WorkflowJobDetails) bool {
	if annotations == nil {
		return false
	}

	switch {
	case annotationContainError(annotations, "failure", userCancelledError):
		workflowDetails.ErrorCode = joberrors.ErrUserCancelled.String()
		workflowDetails.ErrorMessage = "The session was cancelled by the user."
	case annotationContainError(annotations, "failure", waitingTimedOutError):
		workflowDetails.ErrorCode = joberrors.ErrActionsWaitingTimedOut.String()
		workflowDetails.ErrorMessage = "The job timed out while waiting for a runner."
	case annotationContainError(annotations, "failure", billingOwnerDestroyedError):
		workflowDetails.ErrorCode = joberrors.ErrActionsBillingOwnerDestroyed.String()
		workflowDetails.ErrorMessage = "The job was cancelled because the billing owner account has been deleted."
	case annotationContainError(annotations, "failure", runnerNotAcquiredError):
		workflowDetails.ErrorCode = joberrors.ErrActionsRunnerNotAcquired.String()
		workflowDetails.ErrorMessage = "The job was not acquired by a runner even after multiple attempts."
	case annotationContainError(annotations, "failure", operationCancelledError):
		workflowDetails.ErrorCode = joberrors.ErrActionsOperationCancelled.String()
		workflowDetails.ErrorMessage = "The operation was cancelled."
	case annotationContainError(annotations, "failure", exitCode6Error):
		workflowDetails.ErrorCode = joberrors.ErrActionsExitCode6.String()
		workflowDetails.ErrorMessage = "The operation terminated unexpectedly (exit code 6)."
	case annotationContainError(annotations, "failure", repositoryTransferredError):
		workflowDetails.ErrorCode = joberrors.ErrActionsRepositoryTransferred.String()
		workflowDetails.ErrorMessage = "The job was cancelled because the repository was transferred."
	case annotationContainError(annotations, "failure", repositoryArchivedError):
		workflowDetails.ErrorCode = joberrors.ErrActionsRepositoryArchived.String()
		workflowDetails.ErrorMessage = "The job was cancelled because the repository was archived."
	default:
		return false
	}
	return true
}

// unprocessedCommentsResult holds the output of getUnprocessedCommentsAndReviews
// along with intermediate counts from each filtering stage for diagnostics.
type unprocessedCommentsResult struct {
	comments []github.GQLIssueComment
	reviews  []github.GQLPullRequestReview
	// filteredCommentsCount/filteredReviewsCount are the counts after
	// FilteredComments/FilteredReviews (minimized, bots, and users without
	// push permissions removed) but before removing already-claimed items.
	filteredCommentsCount int
	filteredReviewsCount  int
}

func getUnprocessedCommentsAndReviews(
	actx *github.PullRequestContext, allJobs []*jobs.Job, pendingJob *jobs.Job, isAgentic agenticapp.IsAgenticFunc,
) unprocessedCommentsResult {
	// TODO(colbylwilliams): Confirm this is the behavior we want for this filter.
	filterOpts := github.FilterCommentOpts{
		IncludeMinimized:                   false,
		IncludeOtherBots:                   false,
		IncludeUsersWithoutPushPermissions: false, // https://github.com/github/sweagentd/issues/623
		IncludeCopilotReviews:              true,  // must be true to include inline review comment replies
	}

	// Get filtered reviews that have not yet been processed by another job
	filteredReviews := actx.FilteredReviews(filterOpts, isAgentic)
	filteredReviewsCount := len(filteredReviews)
	filteredReviews = slices.DeleteFunc(filteredReviews, func(r github.GQLPullRequestReview) bool {
		return slices.ContainsFunc(allJobs, func(j *jobs.Job) bool {
			return j.ID != pendingJob.ID && slices.Contains(j.ReviewIDs, r.GetID()) // ignore the pending job
		})
	})

	// Get filtered comments that have not yet been processed by another job
	filteredComments := actx.FilteredComments(filterOpts, isAgentic)
	filteredCommentsCount := len(filteredComments)
	filteredComments = slices.DeleteFunc(filteredComments, func(c github.GQLIssueComment) bool {
		return slices.ContainsFunc(allJobs, func(j *jobs.Job) bool {
			return j.ID != pendingJob.ID && slices.Contains(j.CommentIDs, c.GetID()) // ignore the pending job
		})
	})

	return unprocessedCommentsResult{
		comments:              filteredComments,
		reviews:               filteredReviews,
		filteredCommentsCount: filteredCommentsCount,
		filteredReviewsCount:  filteredReviewsCount,
	}
}

// getLatestActionableComment returns the most recent comment/review that can trigger
// the agent to start a job. It's used to determine the last actor to trigger the job.
func getLatestActionableComment(actx *github.PullRequestContext, comments []github.GQLIssueComment, reviews []github.GQLPullRequestReview, isAgentic agenticapp.IsAgenticFunc) *github.GQLComment {
	// Add all the comments and reviews to a single slice, sorted most recent first
	all := []*github.GQLComment{}
	for i := range comments {
		all = append(all, &comments[i].GQLComment)
	}
	for i := range reviews {
		all = append(all, &reviews[i].GQLComment)
	}

	slices.SortStableFunc(all, func(a, b *github.GQLComment) int {
		// reverse b and a to get the most recent first
		return cmp.Compare(b.PublishedAt.Unix(), a.PublishedAt.Unix())
	})

	// TODO(colbylwilliams): Do we nee need to consider if the associated review/
	// comment is "actionable" (i.e. the LLM returned that we should process it)
	// when determining which user to use as the actor for a job? If so, we need
	// to persist that with the review/comment ids on the job.
	var lastActionable *github.GQLComment

	for _, comment := range all {
		// TODO(colbylwilliams):
		// This logic is duplicated in several places, refactor to make it reusable.
		author := comment.GetAuthor()

		// Ignore comment/review authored by Copilot or other bots
		_, isAgenticAuthor := isAgentic(author)
		if isAgenticAuthor || author.IsBot() {
			continue
		}

		// Only process events where the actor has write access to the repo
		if !actx.PermissionsFor(author).Push {
			continue
		}

		lastActionable = comment
		break
	}

	return lastActionable
}

// AddUnprocessedCommentsAndReviewsToJob updates the pending job ReviewIDs and CommentIDs to include
// the comments/reviews in the pull request that have not yet been processed by another job.
func AddUnprocessedCommentsAndReviewsToJob(gh github.ClientInterface, actx *github.PullRequestContext, allJobs []*jobs.Job, pendingJob *jobs.Job, isAgentic agenticapp.IsAgenticFunc) {
	// Get all (qualifying) comments and reviews that have not yet been processed by another job
	result := getUnprocessedCommentsAndReviews(actx, allJobs, pendingJob, isAgentic)

	// Add the filtered, unprocessed comment ids to the pending job
	for i := range result.comments {
		if !slices.Contains(pendingJob.CommentIDs, result.comments[i].GetID()) {
			pendingJob.CommentIDs = append(pendingJob.CommentIDs, result.comments[i].GetID())
		}
	}

	// Add the filtered, unprocessed review ids to the pending job
	for i := range result.reviews {
		if !slices.Contains(pendingJob.ReviewIDs, result.reviews[i].GetID()) {
			pendingJob.ReviewIDs = append(pendingJob.ReviewIDs, result.reviews[i].GetID())
		}
	}
}

// ProcessPendingJob processes a pending job by updating the job with the comments/reviews that have
// not yet been processed by another job, setting the job actor to the most recent user that took
// a "triggering" action, and then launches then executes the job.
func ProcessPendingJob(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, actx *github.PullRequestContext, allJobs []*jobs.Job, pendingJob *jobs.Job, isAgentic agenticapp.IsAgenticFunc) (*jobs.Job, error) {
	// Get all (qualifying) comments and reviews that have not yet been processed by another job
	result := getUnprocessedCommentsAndReviews(actx, allJobs, pendingJob, isAgentic)
	comments := result.comments
	reviews := result.reviews

	// Add the filtered, unprocessed comment ids to the pending job
	for i := range comments {
		if !slices.Contains(pendingJob.CommentIDs, comments[i].GetID()) {
			pendingJob.CommentIDs = append(pendingJob.CommentIDs, comments[i].GetID())
		}
	}

	// Add the filtered, unprocessed review ids to the pending job
	for i := range reviews {
		if !slices.Contains(pendingJob.ReviewIDs, reviews[i].GetID()) {
			pendingJob.ReviewIDs = append(pendingJob.ReviewIDs, reviews[i].GetID())
		}
	}

	// Get the most recent comment/review that's considered actionable to determine the actor
	latestActionableComment := getLatestActionableComment(actx, comments, reviews, isAgentic)
	if latestActionableComment == nil {
		logNoActionableComments(ctx, obsv, actx, allJobs, pendingJob, result)
		return nil, goerrors.New("no actionable comments found to determine actor")
	}

	actor := latestActionableComment.Author

	// Set the job actor to the author of the most recent "triggering" comment/review
	pendingJob.ActorID = actor.GetID()
	pendingJob.ActorLogin = actor.GetLogin()

	return pendingJob, nil
}

// logNoActionableComments emits structured diagnostics when ProcessPendingJob
// cannot find an actionable comment author. It logs per-stage counts to help
// identify which layer of the filtering pipeline is dropping all candidates.
func logNoActionableComments(
	ctx context.Context,
	obsv observability.Exporters,
	actx *github.PullRequestContext,
	allJobs []*jobs.Job,
	pendingJob *jobs.Job,
	result unprocessedCommentsResult,
) {
	totalComments := actx.PullRequest.Comments.TotalCount
	totalReviews := actx.PullRequest.Reviews.TotalCount
	fetchedComments := len(actx.PullRequest.Comments.Nodes)
	fetchedReviews := len(actx.PullRequest.Reviews.Nodes)
	commentsTruncated := totalComments > fetchedComments

	obsv.LoggerWithTelemetry(ctx).Warn("no actionable comments found to determine actor",
		kvp.Int("total_comments", totalComments),
		kvp.Int("fetched_comments", fetchedComments),
		kvp.Int("total_reviews", totalReviews),
		kvp.Int("fetched_reviews", fetchedReviews),
		kvp.Int("filtered_comments", result.filteredCommentsCount),
		kvp.Int("filtered_reviews", result.filteredReviewsCount),
		kvp.Int("unprocessed_comments", len(result.comments)),
		kvp.Int("unprocessed_reviews", len(result.reviews)),
		kvp.Bool("comments_truncated", commentsTruncated),
		kvp.Int("total_jobs", len(allJobs)),
		kvp.String("event_type", string(pendingJob.EventType)),
	)

	obsv.Statter.Counter("jobs.no_actionable_comment",
		obsv.TelemetryTags(ctx).Merge(stats.Tags{
			"comments_truncated": strconv.FormatBool(commentsTruncated),
		}), 1)
}

// WorkflowJobDetails contains comprehensive details of a workflow job
type WorkflowJobDetails struct {
	WorkflowJob  *gg.WorkflowJob
	JobStatus    jobs.JobStatus
	Reason       string
	FailedSteps  []*gg.TaskStep
	ErrorCode    string
	ErrorMessage string
}

// ToJobError creates a JobError from the workflow details.
// Returns nil if wd is nil or there is no error code or error message.
func (wd *WorkflowJobDetails) ToJobError() *jobs.JobError {
	if wd == nil {
		return nil
	}
	if wd.ErrorCode == "" && wd.ErrorMessage == "" {
		return nil
	}

	// Parse service and code from ErrorCode (format: "service:code")
	var service, code string
	if wd.ErrorCode != "" {
		parts := strings.SplitN(wd.ErrorCode, ":", 2)
		if len(parts) == 2 {
			service = parts[0]
			code = parts[1]
		} else {
			code = wd.ErrorCode
		}
	}

	message := wd.ErrorMessage
	if message == "" {
		message = DefaultSessionErrorMessage
	}

	return &jobs.JobError{
		Service:            service,
		ResponseStatusCode: code,
		Message:            message,
	}
}

// GetWorkflowDetails performs comprehensive analysis of a workflow job, including status determination,
// failed step analysis, and error detection.
func GetWorkflowDetails(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, ffClient featureflags.Client, job *jobs.Job, repo *gg.Repository, workflowJob *gg.WorkflowJob, fallbackStatus jobs.JobStatus) (*WorkflowJobDetails, error) {
	logFields := []kvp.Field{}
	if workflowJob.ID != nil {
		logFields = append(logFields, kvp.Int64("workflowJobID", *workflowJob.ID))
	} else {
		logFields = append(logFields, kvp.String("workflowJobID", "nil"))
	}
	if workflowJob.Conclusion != nil {
		logFields = append(logFields, kvp.String("workflowJobConclusion", *workflowJob.Conclusion))
	} else {
		logFields = append(logFields, kvp.String("workflowJobConclusion", "nil"))
	}

	logger := obsv.LoggerWithTelemetry(ctx).WithFields(logFields...)
	logger.Info("analyzing workflow job details")

	workflowDetails := &WorkflowJobDetails{
		WorkflowJob: workflowJob,
		JobStatus:   fallbackStatus,
	}

	conclusion := *workflowJob.Conclusion

	// Get failed steps
	workflowDetails.FailedSteps, workflowDetails.ErrorCode, workflowDetails.ErrorMessage = getFailedSteps(workflowJob)

	// Get annotations once for comprehensive error analysis
	var annotations []*gg.CheckRunAnnotation
	var err error
	if workflowJob.ID != nil {
		annotations, err = gh.ListCheckRunAnnotations(ctx, repo.GetOwner().GetLogin(), repo.GetName(), *workflowJob.ID)
		if err != nil {
			logger.WithError(err).Error("failed to list checkrun annotations", kvp.String("workflowJobID", strconv.FormatInt(*workflowJob.ID, 10)))
			if limiter.IsAnyRateLimitError(err) {
				return nil, err
			}
		}
	}

	// Analyze conclusion and annotations for job status and errors
	switch conclusion {
	case "success":
		workflowDetails.JobStatus = jobs.JobStatusCompleted
	case "cancelled":
		// Check for timeout first
		if annotations != nil && annotationContainError(annotations, "failure", runningTimedOutError) {
			workflowDetails.JobStatus = jobs.JobStatusTimedOut
			workflowDetails.ErrorCode = joberrors.ErrActionsTimedOut.String()
			workflowDetails.ErrorMessage = "Copilot had to stop work due to a timeout."
		} else {
			workflowDetails.JobStatus = jobs.JobStatusCancelled

			if annotations != nil && !setCancelledErrorFromAnnotations(annotations, workflowDetails) {
				// Unknown cancellation
				obsv.Statter.Counter("dynamic_workflow_unknown_cancellation", obsv.TelemetryTags(ctx), 1)
				logUnknownAnnotations(logger, annotations, "cancellation")
			}
		}
	case "failure":
		workflowDetails.JobStatus = jobs.JobStatusFailed
		if annotations != nil && !setFailureErrorFromAnnotations(annotations, workflowDetails) && workflowDetails.ErrorCode == "" && workflowDetails.ErrorMessage == "" {
			// Only log unknown failure annotations if no error classification has been set yet
			logUnknownAnnotations(logger, annotations, "failure")
		}
	default:
		logger.Info("unhandled workflow job conclusion")
		workflowDetails.JobStatus = jobs.JobStatusFailed
	}

	// If no error was found from existing annotation parsing, check for fallback error annotations
	// emitted by the runtime when it couldn't report errors via callback
	if workflowDetails.ErrorCode == "" && workflowDetails.ErrorMessage == "" {
		if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentErrorAnnotations, job) {
			if fallbackErr := findFallbackErrorAnnotation(annotations); fallbackErr != nil {
				workflowDetails.ErrorCode = fallbackErr.Service + ":" + fallbackErr.ResponseStatusCode
				workflowDetails.ErrorMessage = fallbackErr.Message
				logger.Info("found fallback error annotation",
					kvp.String("service", fallbackErr.Service),
					kvp.String("code", fallbackErr.ResponseStatusCode))
			}
		}
	}

	// If the workflow failed but the only failed steps are custom setup steps
	// (not part of our dynamic workflow), the agent itself ran successfully.
	// Don't mark the job as failed in this case.
	if workflowDetails.JobStatus == jobs.JobStatusFailed && len(workflowDetails.FailedSteps) > 0 {
		hasOnlyFailedSetupSteps := !slices.ContainsFunc(workflowDetails.FailedSteps, func(s *gg.TaskStep) bool {
			return slices.Contains(launcher.ActionsWorkflowJobKnownSteps(), s.GetName())
		})
		if hasOnlyFailedSetupSteps {
			logger.Info("only custom setup steps failed, marking job as completed")
			workflowDetails.JobStatus = jobs.JobStatusCompleted
			workflowDetails.ErrorCode = ""
			workflowDetails.ErrorMessage = ""
		}
	}

	return workflowDetails, nil
}

// MapConclusionToJobStatus maps workflow conclusion strings to job statuses.
func MapConclusionToJobStatus(conclusion string) jobs.JobStatus {
	switch conclusion {
	case "success":
		return jobs.JobStatusCompleted
	case "cancelled":
		return jobs.JobStatusCancelled
	default:
		// "failure" and any unknown conclusion are treated as failed
		return jobs.JobStatusFailed
	}
}
