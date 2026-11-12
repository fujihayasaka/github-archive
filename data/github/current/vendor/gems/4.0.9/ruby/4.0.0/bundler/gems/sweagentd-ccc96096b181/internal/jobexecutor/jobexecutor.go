// Package jobexecutor provides functionality for executing agent jobs from the queue.
package jobexecutor

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/go-mark"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	goerrors "github.com/go-errors/errors"
	gg "github.com/google/go-github/v75/github"
)

// JobExecutor provides methods for processing and managing agent jobs.
type JobExecutor interface {
	ProcessJob(ctx context.Context, queueJob *aqueductJobs.AgentJob) error
	CancelJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repoOwner, repoName string) error
	GetPremiumQuotaStatus(ctx context.Context, ownerID, repoID, userID int64) (bool, int32, error)
}

type jobService interface {
	GetJobQueuedForExecutionWithNonce(ctx context.Context, queueJob *aqueductJobs.AgentJob) (*jobs.Job, string, error)
	GetAssignmentByID(ctx context.Context, ownerID, repoID int64, assignmentID string) (*jobs.Assignment, error)
	GetPreviousSessionIDs(ctx context.Context, job *jobs.Job) []string
	FinalizeUnexecutedJob(ctx context.Context, job *jobs.Job, status jobs.JobStatus, jobError *jobs.JobError) error
	UpdateJobForLaunched(ctx context.Context, job *jobs.Job, computeID string, launchedAt int64) (*jobs.Job, error)
}

// AgentJobExecutor executes agent jobs by launching agents and managing their lifecycle.
type AgentJobExecutor struct {
	obsv           observability.Exporters
	launcher       launcher.AgentLauncher
	ffClient       featureflags.Client
	ghTwirp        githubtwirp.ClientInterface
	ghFactory      github.ClientFactoryInterface
	service        jobService
	customAgentSvc *customagent.Service
	appProvider    *agenticapp.Provider
}

var _ JobExecutor = (*AgentJobExecutor)(nil)

// NewAgentJobExecutor creates a new AgentJobExecutor with the provided dependencies.
func NewAgentJobExecutor(
	obsv observability.Exporters,
	launcher launcher.AgentLauncher,
	ffClient featureflags.Client,
	ghTwirp githubtwirp.ClientInterface,
	ghFactory github.ClientFactoryInterface,
	service jobService,
	customAgentSvc *customagent.Service,
	appProvider *agenticapp.Provider,
) *AgentJobExecutor {
	return &AgentJobExecutor{
		obsv:           obsv,
		launcher:       launcher,
		ffClient:       ffClient,
		ghTwirp:        ghTwirp,
		ghFactory:      ghFactory,
		service:        service,
		customAgentSvc: customAgentSvc,
		appProvider:    appProvider,
	}
}

// ProcessJob processes a queued job from the aqueduct queue.
func (e *AgentJobExecutor) ProcessJob(ctx context.Context, queueJob *aqueductJobs.AgentJob) error {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.ProcessJob")
	defer span.End()

	e.obsv.LoggerWithTelemetry(ctx).Info("processing queued job")

	job, nonce, err := e.service.GetJobQueuedForExecutionWithNonce(ctx, queueJob)
	if err != nil {
		return goerrors.Errorf("failed to get job queued for execution: %w", err)
	}

	if !job.IsQueued() {
		// if the job is no longer queued, we can assume it was already processed,
		// cancelled, etc. and skip processing the job.
		e.obsv.LoggerWithTelemetry(ctx).Info("job is no longer queued, skipping processing")
		return nil
	}

	// Fail the job with a message that will appear in the session UX if we got a custom agent parsing error.
	//
	// TODO: Rather than doing this failure check exclusively at this point, we should be able to do it earlier in the process to
	// avoid unnecessary work. However, this requires all UX surfaces to be updated which will not happen overnight, so this provides
	// a consistent fallback during the transition that behaves like other post-queue failures.
	//
	// In the future, UIs should:
	// - Display parsing errors anywhere there is a list of custom agents rather than falling through. (API updated to allow this already)
	// - During job creation, check if the issue is assigned to someone else and fail fast with a 400 and detailed parsing error.
	//
	// Changes will be required in mission control, issue assignment, mobile, VS Code and more, so it will take time. But we can then
	// consider removing this final fallback at that point.
	if job.CustomAgent.ConfigError != "" {
		e.obsv.LoggerWithTelemetry(ctx).Error(fmt.Sprintf("cancelling due to invalid subagent config: %s", job.CustomAgent.ConfigError))
		err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrInvalidCustomAgentConfig, fmt.Sprintf("Invalid custom agent config: %s. See https://gh.io/customagents for more info.", job.CustomAgent.ConfigError)))
		if err != nil {
			return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
		}
		return nil
	}

	app, err := e.appProvider.FindByID(job.AgentID)
	if err != nil {
		return goerrors.Errorf("unable to find agent from agentID: %w", err)
	}

	gh, err := e.ghFactory.NewClientForRepo(ctx, app, job)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	// Only process events where the actor has write access to the repo
	permission, err := gh.GetUserPermissionsForRepositoryByID(ctx, job.RepoID, job.ActorLogin)
	if err != nil {
		return goerrors.Errorf("getting user permissions for repository: %w", err)
	}

	if !permission.Push {
		e.obsv.LoggerWithTelemetry(ctx).Info("cancelling job because actor no longer has write access to the repo")
		err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrInsufficientPermissions, "Actor has insufficient permissions"))
		if err != nil {
			return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
		}
		return nil
	}

	if job.HasPullRequest() {
		// Check if the PR is still open
		// todo (dy-hu): We should get the PR via Twirp
		// In the case of 404 here, we should log and continue.
		pr, err := gh.GetPullRequest(ctx, job.RepoID, job.PullRequestNumber)
		if err != nil {
			// Log and continue to prevent being overly defensive
			e.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to fetch pull request for validation, continuing with job execution")
		} else if pr.GetState() != "open" {
			e.obsv.LoggerWithTelemetry(ctx).Info("pull request is not open, finalizing job")
			err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrPullRequestClosed, "Pull request is not open"))
			if err != nil {
				return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
			}
			return nil
		}
	}

	repo, err := gh.GetRepositoryByID(ctx, job.RepoID)
	if err != nil {
		return goerrors.Errorf("failed to get repository for job: %w", err)
	}

	// TODO (colbylwilliams): Consider moving this into executeJob or populating
	// the field in GetJobQueuedForExecution (specially if quota/perm checks move).
	job.PreviousSessionIDs = e.service.GetPreviousSessionIDs(ctx, job)

	e.obsv.LoggerWithTelemetry(ctx).Info("executing job from queue")
	err = e.executeJob(ctx, gh, app, job, repo, nonce)
	if err != nil {
		return goerrors.Errorf("failed to execute job from queue: %w", err)
	}

	e.obsv.LoggerWithTelemetry(ctx).Info("finished processing queued job")
	return nil
}

// CancelJob cancels a job by terminating the agent if it's running or finalizing it if pending/queued.
func (e *AgentJobExecutor) CancelJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repoOwner, repoName string) error {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.CancelJob")
	defer span.End()

	e.obsv.LoggerWithTelemetry(ctx).Info("cancelling job")
	switch {
	case job.IsTerminal():
		// If the job is already terminal, we can't cancel it.
		e.obsv.LoggerWithTelemetry(ctx).Info("job is already terminal, cannot cancel")
		return mark.With(mark.ErrAlreadyExists, goerrors.Errorf("cannot cancel a job that is %s", job.Status))

	case job.IsRunning():
		// If the job is running, we need to cancel the workflow run
		e.obsv.LoggerWithTelemetry(ctx).Info("job is running, cancelling job")
		err := e.launcher.TerminateAgent(ctx, launcher.TerminateAgentOpts{
			OwnerID:   job.OwnerID,
			RepoID:    job.RepoID,
			RepoName:  repoName,
			RepoOwner: repoOwner,
			ComputeID: job.ComputeID,
			AgentID:   job.AgentID,
			Client:    gh,
		})
		if err != nil {
			return joberrors.MarkExistingError(err, "failed to cancel running job")
		}

		// NOTE: The actual job status will be updated based on the job event coming
		// 		 back from actions, which also ensures any pending jobs that remain
		// 		 in the database will pick up as expected.

		// TODO (colbylwilliams):
		// There will be a delay between the job being cancelled and the workflow
		// job event coming back from actions where the job status is updated.
		//
		// We should consider adding transitional statuses like "cancelling" to
		// the job to indicate that the job is in the process of being cancelled.
		//
		// 1. This allows us to handle additional events (like another cancel request)
		//    gracefully while the job is in the process of being cancelled.
		// 2. It provides an opportunity for better visibility into the job's state
		//    for users (e.g. showing a "Cancelling..." status in the UI).

		return nil

	case job.IsPending() || job.IsQueued():
		// If the job is pending or queued, we haven't launched the agent yet, so we can
		// just cancel the job in the database and finalize the session if it exists.
		err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrUserCancelled, "Job was cancelled"))
		if err != nil {
			return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
		}

		return nil

	default:
		// This should never happen, but just in case we have an unknown job status.
		e.obsv.LogAndReportError(ctx, goerrors.Errorf("unknown job status: %s", job.Status), "failed to cancel job")
		return goerrors.Errorf("unknown job status: %s", job.Status)
	}
}

func (e *AgentJobExecutor) customAgentFromJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repo *gg.Repository) (sweagentd.CustomAgent, error) {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.customAgentFromJob")
	defer span.End()

	if job.CustomAgent.Name == "" {
		return customagent.Copilot(job.OwnerID, job.RepoID, repo.Owner.GetLogin(), repo.GetName()), nil
	}

	if e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentPermissions, job) {
		customAgent, err := e.customAgentSvc.FromDB(ctx, job.CustomAgent)
		if err != nil {
			e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to launch agent")
			return nil, goerrors.Errorf("failed to get custom agent for job: %w", err)
		}
		return customAgent, nil
	}

	return customagent.FromDB(job.CustomAgent), nil
}

func (e *AgentJobExecutor) executeJob(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, job *jobs.Job, repo *gg.Repository, nonce string) error {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.executeJob")
	defer span.End()

	// Check if the user has sufficient premium quota before launching the agent
	err := e.checkQuota(ctx, gh, job, repo)
	if err != nil {
		// Known errors indicating that the job cannot proceed due to quota or customer selection.
		// We've "handled" the job so we don't need to return an error here.
		// We'll also leave the job as pending (with no session ID) in the
		// database so that if a future attempt to launch the agent succeeds,
		// it will pick up any unhandled comments/reviews.
		if errors.Is(err, errInsufficientQuota) {
			e.obsv.LoggerWithTelemetry(ctx).Info("user does not have sufficient quota, job will not be executed")

			return nil
		}

		if errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
			e.obsv.LoggerWithTelemetry(ctx).Info("user needs to select customer in settings, job will not be executed")

			return nil
		}

		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to check quota")
		return goerrors.Errorf("failed to check quota: %w", err)
	}
	e.obsv.LoggerWithTelemetry(ctx).Info("user has sufficient quota, proceeding with job execution")

	launchOpts, err := e.launchOptsForJob(ctx, gh, app, job, repo)
	if err != nil {
		return goerrors.Errorf("failed to create launch options for job: %w", err)
	}
	launchOpts.Nonce = nonce

	e.obsv.LoggerWithTelemetry(ctx).Info("launching agent")
	_, err = e.launchAgent(ctx, &launchOpts, job)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to launch agent")
		return goerrors.Errorf("failed to launch agent: %w", err)
	}

	// Record metric for jobs executed with custom agents for reporting - covers both initial and PR comment jobs
	if !job.CustomAgent.IsCopilot() {
		e.obsv.Increment(ctx, "job_executed_with_custom_agent", stats.Tags{})
	}

	e.obsv.LoggerWithTelemetry(ctx).Info("finished executing job")
	return nil
}

func (e *AgentJobExecutor) launchOptsForJob(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, job *jobs.Job, repo *gg.Repository) (launcher.LaunchAgentOpts, error) {
	logger := e.obsv.Logger.Named("jobexecutor.launchOptsForJob").WithContext(ctx)

	customAgent, err := e.customAgentFromJob(ctx, gh, job, repo)
	if err != nil {
		return launcher.LaunchAgentOpts{}, goerrors.Errorf("failed to create launch options for job: %w", err)
	}

	if _, isCopilot := customAgent.(*customagent.CopilotAgent); !isCopilot {
		logger.Info("with custom agent: " + customAgent.Name())
	}

	// Fetch assignment to get UseAsyncSessions flag
	useAsyncSessions := false
	assignment, err := e.service.GetAssignmentByID(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		logger.WithError(err).Warn("failed to get assignment for UseAsyncSessions flag, defaulting to false")
	} else if assignment != nil {
		useAsyncSessions = assignment.UseAsyncSessions
	}

	experimentPairs := []string{}
	experimentAssignmentContext := ""
	if job.Experiments != nil {
		experimentAssignmentContext = job.Experiments.AssignmentContext
		for k, v := range job.Experiments.Variations {
			experimentPairs = append(experimentPairs, fmt.Sprintf("%s:%s", k, v))
		}
	}
	experimentsString := strings.Join(experimentPairs, ",")

	repoOwner := repo.Owner.GetLogin()
	repoName := repo.GetName()

	problemStatement := job.ProblemStatement.Content
	return launcher.LaunchAgentOpts{
		JobID:                       job.ID,
		JobEventType:                string(job.EventType),
		Action:                      string(job.Action),
		ActorLogin:                  job.ActorDisplayLogin,
		ActorID:                     job.ActorID,
		BranchName:                  job.BranchName,
		Model:                       job.Model,
		GitHubBaseCommit:            job.BaseCommit,
		GitHubRepo:                  repoOwner + "/" + repoName,
		GitHubRepoName:              repoName,
		GitHubRepoID:                job.RepoID,
		GitHubRepoOwner:             repoOwner,
		GitHubRepoOwnerID:           job.OwnerID,
		IssueNumber:                 job.IssueNumber,
		PRNumber:                    job.PullRequestNumber,
		ProblemStatement:            problemStatement,
		ContentFilterMode:           string(job.ProblemStatement.ContentFilterMode),
		RunName:                     job.RunOptions.RunName,
		Push:                        true, // this is always true for agent jobs
		CommitCount:                 job.ProblemStatement.CommitCount,
		SessionID:                   job.SessionID,
		PreviousSessionIDs:          job.PreviousSessionIDs,
		GitHubToken:                 gh.Token(),
		UseSessions:                 e.ffClient.IsEnabledForUser(ctx, capi.CopilotAPIAgentSessions, job.ActorID),
		UseAsyncSessions:            useAsyncSessions,
		CustomAgent:                 customAgent,
		Experiments:                 experimentsString,
		ExperimentAssignmentContext: experimentAssignmentContext,
		Agent:                       app,
	}, nil
}

var errInsufficientQuota = errors.New("insufficient premium quota")

// handleCustomerSelectionError handles the case where customer selection is required.
func (e *AgentJobExecutor) handleCustomerSelectionError(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repo *gg.Repository) error {
	customerSelectionError := e.customerNotSelectedMessage()

	// Check if the feature flag is enabled to determine behavior
	if !e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSelectCustomerError, job) {
		// Feature flag disabled: log error but allow session to continue
		e.obsv.LoggerWithTelemetry(ctx).Info("user needs to select customer in Copilot settings, but continuing session due to feature flag")
		return nil
	}

	// Feature flag enabled: fail the session and return error
	e.obsv.LoggerWithTelemetry(ctx).Info("user needs to select customer in Copilot settings, updating session to failed")

	// Finalize the job as failed, this will also finalize the session
	err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrCAPICustomerNotSelected, customerSelectionError))
	if err != nil {
		return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
	}

	requestErr := gh.RequestReviewers(ctx, repo.Owner.GetLogin(), repo.GetName(), job.PullRequestNumber, []string{job.ActorLogin})
	if requestErr != nil {
		// Log and report the error but don't return it so we don't add
		// an additional error comment to the pull request.
		e.obsv.LogAndReportError(ctx, requestErr, "failed to request reviewers")
		if limiter.IsAnyRateLimitError(requestErr) {
			return requestErr
		}
	}

	return githubtwirp.ErrCustomerSelectionRequired
}

// checkQuota checks if the user has sufficient premium quota to launch the agent.
// If they have quota, it simply returns nil.
// If they do not have quota, it updates the session (if applicable) to failed
// and requests reviewers on the pull request, then returns errInsufficientQuota.
func (e *AgentJobExecutor) checkQuota(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repo *gg.Repository) error {
	hasSufficientQuota, totalPremiumQuota, err := e.GetPremiumQuotaStatus(ctx, job.OwnerID, job.RepoID, job.ActorID)
	if err != nil {
		// Check if this is the "customer not selected" error
		if errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
			return e.handleCustomerSelectionError(ctx, gh, job, repo)
		}
		return goerrors.Errorf("failed to confirm quota availability: %w", err)
	}
	if hasSufficientQuota {
		// We have sufficient quota, so we can proceed with launching the agent.
		return nil
	}

	quotaMessage := e.insufficientQuotaMessage(totalPremiumQuota)

	e.obsv.LoggerWithTelemetry(ctx).Info("user does not have sufficient quota, updating session to failed")

	// Finalize the job as failed, this will also finalize the session
	err = e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrCAPIPaymentRequired, quotaMessage))
	if err != nil {
		return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
	}

	err = gh.RequestReviewers(ctx, repo.Owner.GetLogin(), repo.GetName(), job.PullRequestNumber, []string{job.ActorLogin})
	if err != nil {
		// Log and report the error but don't return it so we don't add
		// an additional error comment to the pull request.
		e.obsv.LogAndReportError(ctx, err, "failed to request reviewers")
		if limiter.IsAnyRateLimitError(err) {
			return err
		}
	}

	return errInsufficientQuota
}

func (e *AgentJobExecutor) launchAgent(ctx context.Context, launchOpts *launcher.LaunchAgentOpts, job *jobs.Job) (*jobs.Job, error) {
	launchTime := time.Now().Unix()
	result, err := e.launcher.LaunchAgent(ctx, launchOpts)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to launch agent")

		// Check if this is a retriable error - if so, return the error to allow Aqueduct to retry
		if launcher.IsRetriableLaunchError(err) {
			e.obsv.LoggerWithTelemetry(ctx).Info("launch error is retriable, returning error to allow retry")
			return nil, goerrors.Errorf("failed to launch agent (retriable): %w", err)
		}

		// Non-retriable error - finalize the job as failed and return nil to prevent retries
		innerErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrActionsLaunchFailure, "Failed to launch agent"))
		if innerErr != nil {
			e.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after launch failure")
			return nil, goerrors.Errorf("failed to launch agent: %w", err)
		}
		// Job was successfully finalized as failed, return nil to prevent retries
		return nil, nil
	}

	job.Args = *launchOpts
	job.Launcher = e.launcher.LauncherType()
	job.CustomSetupStepsUsed = result.CustomSetupSteps
	job.RunsOn = result.RunsOn

	// if UpdateJobForLaunched fails, job will be nil, so keep a copy of the job
	// to use in the FinalizeUnexecutedJob call below if needed.
	originalJob := job

	// we don't set the computeID, launchTime, or status on the job here, those
	// values will be set by UpdateJobForLaunched below as it takes care of job
	// start and other telemetry and hydro events.
	job, err = e.service.UpdateJobForLaunched(ctx, job, result.ComputeID, launchTime)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update job for launch")
		innerErr := e.service.FinalizeUnexecutedJob(ctx, originalJob, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrActionsLaunchFailure, "Failed to update job for launch"))
		if innerErr != nil {
			e.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after launch failure")
		}
		return nil, goerrors.Errorf("failed to update job for launch: %w", err)
	}

	return job, nil
}
