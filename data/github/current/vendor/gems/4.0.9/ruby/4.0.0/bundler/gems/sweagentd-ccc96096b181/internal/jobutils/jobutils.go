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

	runID, err := strconv.ParseInt(job.ComputeID, 10, 64)
	if err != nil {
		obsv.Statter.Counter("jobs.found_job_in_unexpected_state", obsv.TelemetryTags(ctx).Merge(stats.Tags{"reason": "invalid_compute_id"}), 1)
		return goerrors.Errorf("failed to parse compute ID for running job: %w", err)
	}

	originalWorkflowCtx, _ := requestctx.WorkflowRun(ctx)
	err = requestctx.AddWorkflowRun(ctx, &requestctx.CtxWorkflowRun{ID: runID})
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

	// Skip review request if the session was cancelled AND the skip-review-on-cancel feature flag is enabled.
	skipReviewRequest := sessionUpdate.State == capi.SessionStateCancelled && ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_skip_review_request_on_cancel", job)

	if skipReviewRequest {
		logger.Info("skipping PR review request")
	} else {
		logger.Info("requesting PR review")
		err = gh.RequestReviewers(ctx, repo.Owner.GetLogin(), repo.GetName(), job.PullRequestNumber, []string{job.ActorLogin})
		if err != nil {
			return goerrors.Errorf("failed to request reviewers: %w", err)
		}
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

	// Extract workflow details - these should always be provided by the caller
	failedSteps := workflowDetails.FailedSteps

	// Our Actions job can be marked as failed due to a failed setup step, but if
	// setup step failures are the ONLY problem, we consider the session to be successful
	hasOnlyFailedSetupSteps := len(failedSteps) > 0 && !slices.ContainsFunc(failedSteps, func(s *gg.TaskStep) bool {
		return slices.Contains(launcher.ActionsWorkflowJobKnownSteps(), s.GetName())
	})

	if hasOnlyFailedSetupSteps {
		// The job looks failed, but the agent part ran successfully, and
		// it's just a (non-required) setup step that failed.
		session.State = capi.SessionStateCompleted
		sessionUpdate := capi.SessionUpdate{State: capi.SessionStateCompleted}
		UpdateRequestContextSession(ctx, obsv, sessionUpdate) //nolint:staticcheck // temporary during migration to jobservice
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
	billingLockedError   string = "The job was not started because your account is locked due to a billing issue."
	exitCode143Error     string = "Process completed with exit code 143"
	outOfDiskSpaceError  string = "System.IO.IOException: No space left on device"
	runningTimedOutError string = "The job has exceeded the maximum execution time of"
	userCancelledError   string = "The run was canceled by @"
	waitingTimedOutError string = "The job has exceeded the maximum execution time while awaiting a runner for"
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

func logCancellationAnnotations(logger log.Logger, annotations []*gg.CheckRunAnnotation) {
	for _, annotation := range annotations {
		if annotation.Message != nil && annotation.AnnotationLevel != nil {
			logger.Warn(fmt.Sprintf("unknown cancellation annotation: (%s) %s", *annotation.AnnotationLevel, *annotation.Message))
		}
	}
}

func getUnprocessedCommentsAndReviews(
	actx *github.PullRequestContext, allJobs []*jobs.Job, pendingJob *jobs.Job, isAgentic agenticapp.IsAgenticFunc,
) (comments []github.GQLIssueComment, reviews []github.GQLPullRequestReview) {
	// TODO(colbylwilliams): Confirm this is the behavior we want for this filter.
	filterOpts := github.FilterCommentOpts{
		IncludeMinimized:                   false,
		IncludeOtherBots:                   false,
		IncludeUsersWithoutPushPermissions: false, // https://github.com/github/sweagentd/issues/623
		IncludeCopilotReviews:              true,  // must be true to include inline review comment replies
	}

	// Get filtered reviews that have not yet been processed by another job
	filteredReviews := actx.FilteredReviews(filterOpts, isAgentic)
	filteredReviews = slices.DeleteFunc(filteredReviews, func(r github.GQLPullRequestReview) bool {
		return slices.ContainsFunc(allJobs, func(j *jobs.Job) bool {
			return j.ID != pendingJob.ID && slices.Contains(j.ReviewIDs, r.GetID()) // ignore the pending job
		})
	})

	// Get filtered comments that have not yet been processed by another job
	filteredComments := actx.FilteredComments(filterOpts, isAgentic)
	filteredComments = slices.DeleteFunc(filteredComments, func(c github.GQLIssueComment) bool {
		return slices.ContainsFunc(allJobs, func(j *jobs.Job) bool {
			return j.ID != pendingJob.ID && slices.Contains(j.CommentIDs, c.GetID()) // ignore the pending job
		})
	})

	return filteredComments, filteredReviews
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
	comments, reviews := getUnprocessedCommentsAndReviews(actx, allJobs, pendingJob, isAgentic)

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
}

// ProcessPendingJob processes a pending job by updating the job with the comments/reviews that have
// not yet been processed by another job, setting the job actor to the most recent user that took
// a "triggering" action, and then launches then executes the job.
func ProcessPendingJob(ctx context.Context, gh github.ClientInterface, actx *github.PullRequestContext, allJobs []*jobs.Job, pendingJob *jobs.Job, isAgentic agenticapp.IsAgenticFunc) (*jobs.Job, error) {
	// Get all (qualifying) comments and reviews that have not yet been processed by another job
	comments, reviews := getUnprocessedCommentsAndReviews(actx, allJobs, pendingJob, isAgentic)

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
		return nil, goerrors.New("no actionable comments found to determine actor")
	}

	actor := latestActionableComment.Author

	// Set the job actor to the author of the most recent "triggering" comment/review
	pendingJob.ActorID = actor.GetID()
	pendingJob.ActorLogin = actor.GetLogin()

	return pendingJob, nil
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

			// Check for other cancellation reasons
			if annotations != nil {
				//nolint:revive,gocritic // branches are intentionally identical for documentation purposes
				if annotationContainError(annotations, "failure", userCancelledError) {
					workflowDetails.ErrorCode = joberrors.ErrUserCancelled.String()
					workflowDetails.ErrorMessage = "The session was cancelled by the user."
				} else if annotationContainError(annotations, "failure", waitingTimedOutError) {
					// Misconfigured runner label - no special error needed
				} else {
					// Unknown cancellation - this will be logged elsewhere
					obsv.Statter.Counter("dynamic_workflow_unknown_cancellation", obsv.TelemetryTags(ctx), 1)
					logCancellationAnnotations(logger, annotations)
				}
			}
		}
	case "failure":
		workflowDetails.JobStatus = jobs.JobStatusFailed

		if annotations != nil {
			//nolint:gocritic // using if-else chain because each condition is a function call that can't be a switch case
			if annotationContainError(annotations, "failure", billingLockedError) {
				workflowDetails.ErrorCode = joberrors.ErrActionsBillingLocked.String()
				workflowDetails.ErrorMessage = "The job was not started because the account is locked due to a billing issue."
			} else if annotationContainError(annotations, "failure", exitCode143Error) {
				workflowDetails.ErrorCode = joberrors.ErrActionsTerminated.String()
				workflowDetails.ErrorMessage = "The agent was terminated unexpectedly (exit code 143). This typically indicates the job was forcefully stopped."
			} else if annotationContainError(annotations, "failure", outOfDiskSpaceError) {
				workflowDetails.ErrorCode = joberrors.ErrActionsOutOfDiskSpace.String()
				workflowDetails.ErrorMessage = "Copilot had to stop work due to insufficient disk space. If you see this regularly in this repository, you may need to switch to using GitHub Actions larger runners. For more information, see https://gh.io/copilot-coding-agent-larger-runners."
			}
		}
	default:
		logger.Info("unhandled workflow job conclusion")
		workflowDetails.JobStatus = jobs.JobStatusFailed
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
