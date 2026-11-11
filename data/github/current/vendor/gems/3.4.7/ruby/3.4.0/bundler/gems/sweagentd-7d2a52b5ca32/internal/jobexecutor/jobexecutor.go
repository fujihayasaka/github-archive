package jobexecutor

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/go-mark"
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
	"github.com/github/sweagentd/internal/problemstatement"
	"github.com/github/sweagentd/internal/sweagentd"
)

type JobExecutor interface {
	ProcessJob(ctx context.Context, queueJob *aqueductJobs.AgentJob) error
	CancelJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job) error
	GetPremiumQuotaStatus(ctx context.Context, ownerID, repoID, userID int64) (bool, int32, error)
}

type jobService interface {
	GetJobQueuedForExecutionWithNonce(ctx context.Context, queueJob *aqueductJobs.AgentJob) (*jobs.Job, string, error)
	GetPreviousSessionIDs(ctx context.Context, job *jobs.Job) []string
	FailSession(ctx context.Context, job *jobs.Job, jobError *joberrors.JobError, errorMessage string) error
	FinalizeUnexecutedJob(ctx context.Context, job *jobs.Job, status jobs.JobStatus, errorMessage string) error
	UpdateJobForLaunched(ctx context.Context, job *jobs.Job, computeID string, launchedAt int64) (*jobs.Job, error)
}

type AgentJobExecutor struct {
	obsv      observability.Exporters
	launcher  launcher.AgentLauncher
	ffClient  featureflags.Client
	ghTwirp   githubtwirp.ClientInterface
	ghFactory github.ClientFactoryInterface
	service   jobService
}

var _ JobExecutor = (*AgentJobExecutor)(nil)

func NewAgentJobExecutor(
	obsv observability.Exporters,
	launcher launcher.AgentLauncher,
	ffClient featureflags.Client,
	ghTwirp githubtwirp.ClientInterface,
	ghFactory github.ClientFactoryInterface,
	service jobService,
) *AgentJobExecutor {
	return &AgentJobExecutor{
		obsv:      obsv,
		launcher:  launcher,
		ffClient:  ffClient,
		ghTwirp:   ghTwirp,
		ghFactory: ghFactory,
		service:   service,
	}
}

// ProcessJob processes a queued job from the aqueduct queue.
func (e *AgentJobExecutor) ProcessJob(ctx context.Context, queueJob *aqueductJobs.AgentJob) error {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.ProcessJob")
	defer span.End()

	e.obsv.LoggerWithTelemetry(ctx).Info("processing queued job")

	job, nonce, err := e.service.GetJobQueuedForExecutionWithNonce(ctx, queueJob)
	if err != nil {
		return fmt.Errorf("failed to get job queued for execution: %w", err)
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
		if err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, fmt.Sprintf("Invalid custom agent config: %s. See https://gh.io/customagents for more info.", job.CustomAgent.ConfigError)); err != nil {
			return fmt.Errorf("failed to finalize unexecuted job: %w", err)
		}
		return nil
	}

	gh, err := e.ghFactory.NewClientForRepo(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	// Only process events where the actor has write access to the repo
	permission, err := gh.GetUserPermissionsForRepositoryByID(ctx, job.RepoID, job.ActorLogin)
	if err != nil {
		return fmt.Errorf("getting user permissions for repository: %w", err)
	}

	if !permission.Push {
		e.obsv.LoggerWithTelemetry(ctx).Info("cancelling job because actor no longer has write access to the repo")
		if err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, "Actor has insufficient permissions"); err != nil {
			return fmt.Errorf("failed to finalize unexecuted job: %w", err)
		}
		return nil
	}

	if job.HasPullRequest() {
		// Check if the PR is still open
		pr, err := gh.GetPullRequest(ctx, job.RepoID, job.PullRequestNumber)
		if err != nil {
			return fmt.Errorf("failed to get pull request: %w", err)
		}

		if pr.GetState() != "open" {
			e.obsv.LoggerWithTelemetry(ctx).Info("pull request is not open, finalizing job")
			if err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, "Pull request is not open"); err != nil {
				return fmt.Errorf("failed to finalize unexecuted job: %w", err)
			}
			return nil
		}
	}

	// TODO (colbylwilliams): Consider moving this into executeJob or populating
	// the field in GetJobQueuedForExecution (specially if quota/perm checks move).
	job.PreviousSessionIDs = e.service.GetPreviousSessionIDs(ctx, job)

	e.obsv.LoggerWithTelemetry(ctx).Info("executing job from queue")
	if err := e.executeJob(ctx, gh, job, nonce); err != nil {
		return fmt.Errorf("failed to execute job from queue: %w", err)
	}

	e.obsv.LoggerWithTelemetry(ctx).Info("finished processing queued job")
	return nil
}

func customAgentFromJob(job *jobs.Job) sweagentd.CustomAgent {
	if job.CustomAgent.Name == "" {
		return customagent.Copilot(job.OwnerID, job.RepoID, job.RepoOwner, job.RepoName)
	}
	return customagent.FromDB(job.CustomAgent)
}

func (e *AgentJobExecutor) executeJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job, nonce string) error {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.executeJob")
	defer span.End()

	// Check if the user has sufficient premium quota before launching the agent
	err := e.checkQuota(ctx, gh, job)
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
		return fmt.Errorf("failed to check quota: %w", err)
	}
	e.obsv.LoggerWithTelemetry(ctx).Info("user has sufficient quota, proceeding with job execution")

	launchOpts := e.launchOptsForJob(ctx, gh, job)
	launchOpts.Nonce = nonce

	e.obsv.LoggerWithTelemetry(ctx).Info("launching agent")
	_, err = e.launchAgent(ctx, launchOpts, job)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to launch agent")
		return fmt.Errorf("failed to launch agent: %w", err)
	}

	e.obsv.LoggerWithTelemetry(ctx).Info("finished executing job")
	return nil
}

func (e *AgentJobExecutor) launchOptsForJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job) launcher.LaunchAgentOpts {
	logger := e.obsv.Logger.Named("jobexecutor.launchOptsForJob").WithContext(ctx)

	customAgent := customAgentFromJob(job)
	if customAgent != nil {
		logger.Info("with custom agent: " + customAgent.Name())
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

	problemStatement := job.ProblemStatement.Content
	if !e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentV2CallbackAPI, job) {
		problemStatement = problemstatement.WithAgentInstructions(ctx, job.ProblemStatement.Content, customAgent.Instructions())
	}
	return launcher.LaunchAgentOpts{
		JobID:                       job.ID,
		JobEventType:                string(job.EventType),
		Action:                      string(job.Action),
		ActorLogin:                  job.ActorDisplayLogin,
		ActorID:                     job.ActorID,
		BranchName:                  job.BranchName,
		Model:                       job.Model,
		GitHubBaseCommit:            job.BaseCommit,
		GitHubRepo:                  job.RepoOwner + "/" + job.RepoName,
		GitHubRepoName:              job.RepoName,
		GitHubRepoID:                job.RepoID,
		GitHubRepoOwner:             job.RepoOwner,
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
		CustomAgent:                 customAgent,
		Experiments:                 experimentsString,
		ExperimentAssignmentContext: experimentAssignmentContext,
	}
}

var errInsufficientQuota = errors.New("insufficient premium quota")

// checkQuota checks if the user has sufficient premium quota to launch the agent.
// If they have quota, it simply returns nil.
// If they do not have quota, it updates the session (if applicable) to failed
// and requests reviewers on the pull request, then returns errInsufficientQuota.
func (e *AgentJobExecutor) checkQuota(ctx context.Context, gh github.ClientInterface, job *jobs.Job) error {
	hasSufficientQuota, totalPremiumQuota, err := e.GetPremiumQuotaStatus(ctx, job.OwnerID, job.RepoID, job.ActorID)
	if err != nil {
		// Check if this is the "customer not selected" error
		if errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
			customerSelectionError := e.customerNotSelectedMessage()

			// Check if the feature flag is enabled to determine behavior
			if e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSelectCustomerError, job) {
				// Feature flag enabled: fail the session and return error
				e.obsv.LoggerWithTelemetry(ctx).Info("user needs to select customer in Copilot settings, updating session to failed")
				sessionErr := e.service.FailSession(ctx, job, joberrors.ErrorCAPIPaymentRequired, customerSelectionError)
				if sessionErr != nil {
					return fmt.Errorf("failed to update session: %w", sessionErr)
				}

				requestErr := gh.RequestReviewers(ctx, job.RepoOwner, job.RepoName, job.PullRequestNumber, []string{job.ActorLogin})
				if requestErr != nil {
					// Log and report the error but don't return it so we don't add
					// an additional error comment to the pull request.
					e.obsv.LogAndReportError(ctx, requestErr, "failed to request reviewers")
					if limiter.IsAnyRateLimitError(requestErr) {
						return requestErr
					}
				}

				return githubtwirp.ErrCustomerSelectionRequired
			} else {
				// Feature flag disabled: log error but allow session to continue
				e.obsv.LoggerWithTelemetry(ctx).Info("user needs to select customer in Copilot settings, but continuing session due to feature flag")
				return nil
			}
		}
		return fmt.Errorf("failed to confirm quota availability: %w", err)
	}
	if hasSufficientQuota {
		// We have sufficient quota, so we can proceed with launching the agent.
		return nil
	}

	quotaMessage := e.insufficientQuotaMessage(totalPremiumQuota)

	e.obsv.LoggerWithTelemetry(ctx).Info("user does not have sufficient quota, updating session to failed")
	err = e.service.FailSession(ctx, job, joberrors.ErrorCAPIPaymentRequired, quotaMessage)
	if err != nil {
		return fmt.Errorf("failed to update session: %w", err)
	}

	err = gh.RequestReviewers(ctx, job.RepoOwner, job.RepoName, job.PullRequestNumber, []string{job.ActorLogin})
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

func (e *AgentJobExecutor) launchAgent(ctx context.Context, launchOpts launcher.LaunchAgentOpts, job *jobs.Job) (*jobs.Job, error) {
	launchTime := time.Now().Unix()
	computeID, err := e.launcher.LaunchAgent(ctx, launchOpts)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to launch agent")
		if innerErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusFailed, "Failed to launch agent"); innerErr != nil {
			e.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after launch failure")
		}
		return nil, fmt.Errorf("failed to launch agent: %w", err)
	}

	job.Args = launchOpts
	job.Launcher = e.launcher.LauncherType()

	// if UpdateJobForLaunched fails, job will be nil, so keep a copy of the job
	// to use in the FinalizeUnexecutedJob call below if needed.
	originalJob := job

	// we don't set the computeID, launchTime, or status on the job here, those
	// values will be set by UpdateJobForLaunched below as it takes care of job
	// start and other telemetry and hydro events.
	job, err = e.service.UpdateJobForLaunched(ctx, job, computeID, launchTime)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update job for launch")
		if innerErr := e.service.FinalizeUnexecutedJob(ctx, originalJob, jobs.JobStatusFailed, "Failed to update job for launch"); innerErr != nil {
			e.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after launch failure")
		}
		return nil, fmt.Errorf("failed to update job for launch: %w", err)
	}

	return job, nil
}

func (e *AgentJobExecutor) CancelJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job) error {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.CancelJob")
	defer span.End()

	e.obsv.LoggerWithTelemetry(ctx).Info("cancelling job")
	switch {
	case job.IsTerminal():
		// If the job is already terminal, we can't cancel it.
		e.obsv.LoggerWithTelemetry(ctx).Info("job is already terminal, cannot cancel")
		return mark.With(mark.ErrAlreadyExists, fmt.Errorf("cannot cancel a job that is %s", job.Status))

	case job.IsRunning():
		// If the job is running, we need to cancel the workflow run
		e.obsv.LoggerWithTelemetry(ctx).Info("job is running, cancelling job")
		if err := e.launcher.TerminateAgent(ctx, launcher.TerminateAgentOpts{
			OwnerID:   job.OwnerID,
			RepoID:    job.RepoID,
			RepoName:  job.RepoName,
			RepoOwner: job.RepoOwner,
			ComputeID: job.ComputeID,
			Client:    gh,
		}); err != nil {
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
		err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, "Job was cancelled")
		if err != nil {
			return fmt.Errorf("failed to finalize unexecuted job: %w", err)
		}

		return nil

	default:
		// This should never happen, but just in case we have an unknown job status.
		e.obsv.LogAndReportError(ctx, fmt.Errorf("unknown job status: %s", job.Status), "failed to cancel job")
		return fmt.Errorf("unknown job status: %s", job.Status)
	}
}
