// Package jobexecutor provides functionality for executing agent jobs from the queue.
package jobexecutor

import (
	"context"
	_ "embed"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-mark"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/environmentfeatures"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	goerrors "github.com/go-errors/errors"
	gg "github.com/google/go-github/v75/github"
)

// ErrAgenticAppUserConfigError is returned when a job fails due to a configuration error that the user can fix.
var ErrAgenticAppUserConfigError = goerrors.New("agentic app user configuration error")

const (
	callbackFieldsPersistBeforeLaunchMetric   = "jobs.callback_fields_persist_before_launch"
	callbackFieldsPersistBeforeLaunchMsMetric = "jobs.callback_fields_persist_before_launch_ms"
	launchFailedAfterCallbackFieldsMetric     = "jobs.launch_failed_after_callback_fields_persisted"
)

// JobExecutor provides methods for processing and managing agent jobs.
type JobExecutor interface {
	ProcessJob(ctx context.Context, queueJob *aqueductJobs.AgentJob) error
	CancelJob(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repoOwner, repoName string) error
	GetQuotaStatus(ctx context.Context, ownerID, repoID, userID int64) (bool, int32, bool, error)
}

type jobService interface {
	GetJobQueuedForExecutionWithNonce(ctx context.Context, queueJob *aqueductJobs.AgentJob) (*jobs.Job, string, error)
	GetAssignmentByID(ctx context.Context, ownerID, repoID int64, assignmentID string) (*jobs.Assignment, error)
	GetPreviousJobContext(ctx context.Context, job *jobs.Job) (previousSessionIDs []string, previousComputeID string, previousComputeLaunchedAt int64)
	FinalizeUnexecutedJob(ctx context.Context, job *jobs.Job, status jobs.JobStatus, jobError *jobs.JobError) error
	UpdateJobForLaunched(ctx context.Context, job *jobs.Job, computeID string, launchedAt int64) (*jobs.Job, error)
}

// AgentJobExecutor executes agent jobs by launching agents and managing their lifecycle.
type AgentJobExecutor struct {
	obsv           observability.Exporters
	launchers      launcher.Builder
	ffClient       featureflags.Client
	ghTwirp        githubtwirp.ClientInterface
	ghFactory      github.ClientFactoryInterface
	service        jobService
	customAgentSvc *customagent.Service
	pluginSvc      *plugins.Service
	appProvider    *agenticapp.Provider
}

var _ JobExecutor = (*AgentJobExecutor)(nil)

// NewAgentJobExecutor creates a new AgentJobExecutor with the provided dependencies.
func NewAgentJobExecutor(
	obsv observability.Exporters,
	launchers launcher.Builder,
	ffClient featureflags.Client,
	ghTwirp githubtwirp.ClientInterface,
	ghFactory github.ClientFactoryInterface,
	service jobService,
	customAgentSvc *customagent.Service,
	pluginSvc *plugins.Service,
	appProvider *agenticapp.Provider,
) *AgentJobExecutor {
	return &AgentJobExecutor{
		obsv:           obsv,
		launchers:      launchers,
		ffClient:       ffClient,
		ghTwirp:        ghTwirp,
		ghFactory:      ghFactory,
		service:        service,
		customAgentSvc: customAgentSvc,
		pluginSvc:      pluginSvc,
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

	// Mark job as delayed if it was ever requeued due to rate or concurrency limits
	if queueJob.RequeueCount > 0 {
		job.WasDelayed = true
	}

	if !job.IsQueued() {
		// if the job is no longer queued, we can assume it was already processed,
		// cancelled, etc. and skip processing the job.
		e.obsv.LoggerWithTelemetry(ctx).Info("job is no longer queued, skipping processing")
		return nil
	}

	// Fail the job with a message that will appear in the session UX if we got a custom agent parsing error.
	if job.CustomAgent.ConfigError != "" {
		e.obsv.LoggerWithTelemetry(ctx).Error(fmt.Sprintf("cancelling due to invalid subagent config: %s", job.CustomAgent.ConfigError))
		err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrInvalidCustomAgentConfig, fmt.Sprintf("Invalid custom agent config: %s. See https://gh.io/customagents for more info.", job.CustomAgent.ConfigError)))
		if err != nil {
			return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
		}
		return nil
	}

	app, err := e.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		return goerrors.Errorf("unable to find agent from agentID: %w", err)
	}

	if e.ffClient != nil && e.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentCheckAgenticAppAuth, job.ActorID, job.RepoID) {
		needsAuth, authorizationURL, err := e.ghTwirp.IntegrationNeedsAuthorizationFromUser(ctx, job.ActorID, job.AgentID)
		if err != nil {
			return goerrors.Errorf("failed to check if integration needs authorization: %w", err)
		}
		if needsAuth {
			e.obsv.LoggerWithTelemetry(ctx).Info("cancelling job because agentic app requires user authorization")
			err := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrAgenticAppUnauthorized, fmt.Sprintf("Agentic app %s requires authorization. Please visit %s to authorize the app and try again.", app.AppName(), authorizationURL)))
			if err != nil {
				return goerrors.Errorf("failed to finalize unexecuted job: %w", err)
			}
			return nil
		}
	}

	gh, err := e.ghFactory.NewClientForRepo(ctx, app, job)
	if err != nil {
		return goerrors.Errorf("failed to create GitHub client: %w", err)
	}

	// Only process events where the actor has write access to the repo.
	// Skip for org-actor jobs — the org owns the repo and can't lose access to it.
	if !job.IsOrgActor() {
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

		cancelled, err := e.checkAdditionalRepoReadAccess(ctx, gh, job)
		if err != nil {
			return err
		}
		if cancelled {
			return nil
		}
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
	job.PreviousSessionIDs, job.PreviousComputeID, job.PreviousComputeLaunchedAt = e.service.GetPreviousJobContext(ctx, job)

	err = e.executeJob(ctx, gh, app, job, repo, nonce)
	if err != nil {
		return goerrors.Errorf("failed to execute job from queue: %w", err)
	}

	e.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", true)).Info("process queued job")
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
		// Jobs created before we started tracking the launcher have an
		// empty job.Launcher. Fall back to the environment default in
		// that case so cancels of legacy running jobs still work.
		launcherType := job.Launcher
		reason := "job_launcher"
		if launcherType == "" {
			launcherType = e.launchers.EnvironmentDefault()
			reason = "legacy_empty_launcher_environment_default"
		}
		e.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("launcher_type", string(launcherType)),
			kvp.String("reason", reason),
		).Info("selected launcher for cancel")
		al, err := e.launchers.Build(ctx, launcherType)
		if err != nil {
			return goerrors.Errorf("failed to build launcher for cancel: %w", err)
		}
		err = al.TerminateAgent(ctx, launcher.TerminateAgentOpts{
			ActorID:   job.ActorID,
			OwnerID:   job.OwnerID,
			RepoID:    job.RepoID,
			RepoName:  repoName,
			RepoOwner: repoOwner,
			ComputeID: job.ComputeID,
			AgentID:   job.AgentID,
			Client:    gh,
		})
		if errors.Is(err, github.ErrWorkflowRunAlreadyCompleted) {
			// The workflow run is already in a terminal state (409 Conflict). No new
			// workflow_run_completed event will be emitted, so we must finalize the
			// job directly to avoid leaving it stuck in "running" forever.
			e.obsv.LoggerWithTelemetry(ctx).Info("workflow run already completed, finalizing job directly")
			finalizeErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrUserCancelled, "Job was cancelled"))
			if finalizeErr != nil {
				return goerrors.Errorf("failed to finalize job after workflow already completed: %w", finalizeErr)
			}
			return nil
		}
		if err != nil {
			return joberrors.MarkExistingError(err, "failed to cancel running job")
		}

		// Sandbox VMs don't emit a workflow_run_completed event, so we
		// finalize the job synchronously right after the VM is stopped.
		if launcherType == launcher.TypeSandbox {
			e.obsv.LoggerWithTelemetry(ctx).Info("sandbox VM stopped, finalizing job directly")
			finalizeErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrUserCancelled, "Job was cancelled"))
			if finalizeErr != nil {
				return goerrors.Errorf("failed to finalize sandbox job after cancel: %w", finalizeErr)
			}
			return nil
		}

		// NOTE: For Actions, the actual job status will be updated when the
		// workflow_run_completed event arrives. Sandbox jobs are finalized
		// synchronously above since they have no equivalent callback.

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

// launcherTypeForJob picks the launcher type to use for the given job
// and logs the choice (with the reason). Resolution order:
//  1. If job.Launcher is already set (e.g. a resume of an existing job),
//     route to the same launcher that originally provisioned the compute.
//  2. If the CopilotSWEAgentSandboxLauncher feature flag is enabled for the
//     actor / repo / owner and the job's agent is sandbox-eligible, route to
//     TypeSandbox.
//  3. Otherwise fall back to the environment default.
//
// As additional routing rules are added, each branch should log the matching
// reason so we can see in the logs why a particular launcher was chosen for
// a particular job.
//
// TODO: Sandbox jobs currently have no finalization lifecycle — there is no
// workflow_run_completed equivalent. Add a mechanism (callback, polling, or
// timeout) so sweagentd learns when a sandbox job finishes.
func (e *AgentJobExecutor) launcherTypeForJob(ctx context.Context, job *jobs.Job) launcher.Type {
	if job != nil && job.Launcher != "" {
		e.obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("launcher_type", string(job.Launcher)),
			kvp.String("reason", "job_launcher"),
		).Info("selected launcher for job")
		return job.Launcher
	}

	fallbackReason := "environment_default"
	if job != nil && e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSandboxLauncher, job) {
		if e.isSandboxLauncherEligible(job) {
			e.obsv.LoggerWithTelemetry(ctx).WithFields(
				kvp.String("launcher_type", string(launcher.TypeSandbox)),
				kvp.String("reason", "sandbox_launcher_ff"),
			).Info("selected launcher for job")
			return launcher.TypeSandbox
		}
		fallbackReason = "sandbox_launcher_ff_agent_not_allowed"
	}

	t := e.launchers.EnvironmentDefault()
	e.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("launcher_type", string(t)),
		kvp.String("reason", fallbackReason),
	).Info("selected launcher for job")
	return t
}

func (e *AgentJobExecutor) isSandboxLauncherEligible(job *jobs.Job) bool {
	if job == nil || e.appProvider == nil || job.IsTriggered {
		return false
	}
	return e.appProvider.IsCopilotCodingAgentApp(job.AgentID)
}

func (e *AgentJobExecutor) customAgentFromJob(ctx context.Context, job *jobs.Job, repo *gg.Repository, app sweagentd.AgenticApp) (sweagentd.CustomAgent, error) {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.customAgentFromJob")
	defer span.End()

	agent, err := e.customAgentSvc.FromDB(ctx, job.CustomAgent)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to launch agent")
		return nil, goerrors.Errorf("failed to get custom agent for job: %w", err)
	}

	// If the resolved agent is not copilot, return it as is.
	if _, isCopilot := agent.(*customagent.CopilotAgent); !isCopilot {
		return agent, nil
	}

	// If the app doesn't have a plugin source, return the copilot agent as is.
	if !app.HasSource() || e.pluginSvc == nil {
		return agent, nil
	}

	// Load agentic app plugin and agent, and cancel with an error if this fails due to what is likely user configuration
	pluginAgent, _, err := e.pluginSvc.GetCustomAgentForApp(ctx, app)
	if err != nil {
		msg, isUserError := plugins.GetPluginConfigValidationMessage(err)
		// Cancel job if this is classified as a user error, otherwise return an error
		if isUserError {
			e.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("invalid user config for agentic app at launch, cancelling job")
			finalizeErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrLaunchOptionsFailure, fmt.Sprintf("Failed to load agentic app configuration. %s", msg)))
			if finalizeErr != nil {
				return nil, goerrors.Errorf("failed to finalize unexecuted job: %w", finalizeErr)
			}
			return nil, goerrors.Errorf("%w: %s", ErrAgenticAppUserConfigError, msg)
		}
		return nil, goerrors.Errorf("failed to get plugin or custom agent for agentic app: %w", err)
	}
	if pluginAgent == nil {
		e.obsv.LoggerWithTelemetry(ctx).Warn("no custom agent found for agentic app at launch, cancelling job")
		finalizeErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrLaunchOptionsFailure, "Failed to load agentic app configuration. Custom agent main.agent.md not found."))
		if finalizeErr != nil {
			return nil, goerrors.Errorf("failed to finalize unexecuted job: %w", finalizeErr)
		}
		return nil, goerrors.Errorf("%w: no custom agent found for agentic app", ErrAgenticAppUserConfigError)
	}

	return pluginAgent, nil
}

func (e *AgentJobExecutor) executeJob(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, job *jobs.Job, repo *gg.Repository, nonce string) error {
	ctx, span := e.obsv.Tracer.Start(ctx, "jobexecutor.executeJob")
	defer span.End()

	// Check if the user has sufficient premium quota before launching the agent.
	// Apps/integrations with the check exemption flag enabled are exempt.
	if e.appProvider.IsAgentCheckExempt(ctx, e.ffClient, job.AgentID, job.RepoID) {
		e.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("allowed", true), kvp.String("reason", "agent_quota_exempt")).Info("quota check")
	} else {
		err := e.checkQuota(ctx, gh, job, repo)
		if err != nil {
			// Known errors indicating that the job cannot proceed due to quota or customer selection.
			// We've "handled" the job so we don't need to return an error here.
			// We'll also leave the job as pending (with no session ID) in the
			// database so that if a future attempt to launch the agent succeeds,
			// it will pick up any unhandled comments/reviews.
			if errors.Is(err, errInsufficientQuota) {
				e.obsv.LoggerWithTelemetry(ctx).WithFields(
					kvp.Bool("allowed", false),
					kvp.String("reason", "insufficient_quota"),
					kvp.String("detail", "user does not have sufficient quota, job will not be executed"),
				).Info("quota check")
				return nil
			}

			if errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
				e.obsv.LoggerWithTelemetry(ctx).WithFields(
					kvp.Bool("allowed", false),
					kvp.String("reason", "customer_selection_required"),
					kvp.String("detail", "user needs to select customer in settings, job will not be executed"),
				).Info("quota check")
				return nil
			}

			return goerrors.Errorf("failed to check quota: %w", err)
		}

		e.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("allowed", true)).Info("quota check")
	}

	launchOpts, err := e.launchOptsForJob(ctx, gh, app, job, repo)
	if err != nil {
		if errors.Is(err, ErrAgenticAppUserConfigError) {
			// Job was already cancelled and the related error message logged in this case, so just return
			return nil
		}
		return goerrors.Errorf("failed to create launch options for job: %w", err)
	}
	launchOpts.Nonce = nonce

	_, err = e.launchAgent(ctx, &launchOpts, job)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", false)).WithError(err).Error("launch agent")
		return goerrors.Errorf("failed to launch agent: %w", err)
	}

	// Record metric for jobs executed with custom agents for reporting - covers both initial and PR comment jobs
	if !job.CustomAgent.IsCopilot() {
		e.obsv.Increment(ctx, "job_executed_with_custom_agent", stats.Tags{})
	}

	e.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Bool("success", true)).Info("launch agent")
	return nil
}

func (e *AgentJobExecutor) launchOptsForJob(ctx context.Context, gh github.ClientInterface, app sweagentd.AgenticApp, job *jobs.Job, repo *gg.Repository) (launcher.LaunchAgentOpts, error) {
	logger := e.obsv.Logger.Named("jobexecutor.launchOptsForJob").WithContext(ctx)

	customAgent, err := e.customAgentFromJob(ctx, job, repo, app)
	if err != nil {
		return launcher.LaunchAgentOpts{}, goerrors.Errorf("failed to create launch options for job: %w", err)
	}

	// Build features from the job. A separate type is used in places like launcher.go
	// that are outside of job-related packages to avoid circular dependencies.
	agentFeatures := environmentfeatures.New()
	if job.Features.CopilotSetupSteps != nil {
		agentFeatures.CopilotSetupSteps = &environmentfeatures.CopilotSetupSteps{
			Skip:    job.Features.CopilotSetupSteps.Skip,
			Exclude: job.Features.CopilotSetupSteps.Exclude,
			Only:    job.Features.CopilotSetupSteps.Only,
		}
	}
	if job.Features.Branch != nil {
		agentFeatures.Branch = &environmentfeatures.Branch{
			Name:    job.Features.Branch.Name,
			BaseRef: job.Features.Branch.BaseRef,
		}
	}
	if job.Features.PullRequest != nil {
		agentFeatures.PullRequest = &environmentfeatures.PullRequest{
			BaseRef: job.Features.PullRequest.BaseRef,
			HeadRef: job.Features.PullRequest.HeadRef,
		}
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

	push := job.HasBranch() || job.RequiresBranch()
	defaultBranch := repo.GetDefaultBranch()

	// For branchless jobs, use the default branch as the workflow ref
	branchName := job.BranchName
	if branchName == "" {
		branchName = defaultBranch
	}

	var snippyBlockingMode sweagentdTwirp.SnippyBlockingMode
	// Default validation tool settings to true (enabled) to match DB defaults
	useCodeQL, useCCR, useSecretScanning, useDependencyVulnChecks := true, true, true, true
	_, configResult, err := e.ghTwirp.IsAgentEnabled(ctx, job.AgentID, job.ActorID, job.RepoID)
	switch {
	case err != nil:
		logger.WithError(err).Warn("failed to get repository configuration for snippy blocking mode, defaulting to blocked")
		tags := e.obsv.TelemetryTags(ctx)
		e.obsv.Increment(ctx, "snippy_blocking_mode_fallback_to_blocked", tags)
		snippyBlockingMode = sweagentdTwirp.SnippyBlockingMode_SNIPPY_BLOCKING_MODE_BLOCKED
	case configResult != nil:
		snippyBlockingMode = configResult.SnippyBlockingMode
		tags := e.obsv.TelemetryTags(ctx).Merge(stats.Tags{"mode": snippyBlockingMode.String()})
		e.obsv.Increment(ctx, "snippy_blocking_mode_resolved", tags)
		useCodeQL = configResult.GetUseCodeql()
		useCCR = configResult.GetUseCcr()
		useSecretScanning = configResult.GetUseSecretScanning()
		useDependencyVulnChecks = configResult.GetUseDependencyVulnChecks()
	default:
		logger.Warn("repository configuration returned nil for snippy blocking mode, defaulting to blocked")
		tags := e.obsv.TelemetryTags(ctx)
		e.obsv.Increment(ctx, "snippy_blocking_mode_config_nil", tags)
		snippyBlockingMode = sweagentdTwirp.SnippyBlockingMode_SNIPPY_BLOCKING_MODE_BLOCKED
	}

	problemStatement := job.ProblemStatement.Content

	// For org-billed jobs, ActorID refers to the org rather than a user.
	// Keep sessions enabled for these jobs instead of gating on a per-user flag.
	useSessions := true
	if !job.IsOrgActor() {
		useSessions = e.ffClient.IsEnabledForUser(ctx, capi.CopilotAPIAgentSessions, job.ActorID)
	}

	ownerType := sweagentd.OwnerType(repo.Owner.GetType())
	if ownerType != sweagentd.OwnerTypeUser && ownerType != sweagentd.OwnerTypeOrganization {
		logger.Warn("Unknown owner type", kvp.String("owner_type", string(ownerType)))
	}

	additionalRepos, err := e.resolveAdditionalRepositories(ctx, gh, job)
	if err != nil {
		return launcher.LaunchAgentOpts{}, err
	}

	return launcher.LaunchAgentOpts{
		JobID:                       job.ID,
		JobEventType:                string(job.EventType),
		IsTriggered:                 job.IsTriggered,
		Action:                      string(job.Action),
		ActorLogin:                  job.ActorDisplayLogin,
		ActorID:                     job.ActorID,
		ActorType:                   string(job.ActorType),
		OwnerType:                   ownerType,
		BranchName:                  branchName,
		Model:                       job.Model,
		GitHubBaseCommit:            job.BaseCommit,
		GitHubRepo:                  repoOwner + "/" + repoName,
		GitHubRepoName:              repoName,
		GitHubRepoID:                job.RepoID,
		GitHubRepoOwner:             repoOwner,
		GitHubRepoOwnerID:           job.OwnerID,
		AdditionalRepositories:      additionalRepos,
		IssueNumber:                 job.IssueNumber,
		PRNumber:                    job.PullRequestNumber,
		ProblemStatement:            problemStatement,
		ContentFilterMode:           string(job.ProblemStatement.ContentFilterMode),
		RunName:                     job.RunOptions.RunName,
		Push:                        push,
		CommitCount:                 job.ProblemStatement.CommitCount,
		SessionID:                   job.SessionID,
		PreviousSessionIDs:          job.PreviousSessionIDs,
		ResumeSessionID:             job.ResumeSessionID,
		GitHubToken:                 gh.Token(),
		UseSessions:                 useSessions,
		UseAsyncSessions:            useAsyncSessions,
		CustomAgent:                 customAgent,
		Features:                    agentFeatures,
		Experiments:                 experimentsString,
		ExperimentAssignmentContext: experimentAssignmentContext,
		IsAutoMode:                  job.IsAutoMode,
		SnippyBlockingMode:          snippyBlockingMode,
		UseCodeQL:                   useCodeQL,
		UseCCR:                      useCCR,
		UseSecretScanning:           useSecretScanning,
		UseDependencyVulnCheck:      useDependencyVulnChecks,
		RepoConfig:                  configResult,
		SignCommits:                 job.RequireSignedCommits,
		PreviousComputeID:           job.PreviousComputeID,
		PreviousComputeLaunchedAt:   job.PreviousComputeLaunchedAt,
		CanWriteWorkflows:           job.CanWriteWorkflows,
		Agent:                       app,
	}, nil
}

// checkAdditionalRepoReadAccess verifies that the actor has at least read
// access (contents:read) to each additional repository when the
// copilot_swe_agent_multi_repo_read feature flag is enabled. Returns
// (true, nil) if the job was cancelled due to insufficient permissions.
//
// THIS IS DESIGNED TO BE TEMPORARY CODE.
// In addition to not batching requests, we also need to check trust policies
// between repositories, something this function does not do.  However, to
// unblock the runtime feature work, which requires a token minting for
// all repositories, we use this temporary permission check so that we at
// least don't grant a user a token with permissions they wouldn't normally
// have access to.
//
// See https://github.com/github/sweagentd/issues/11971 for the proper logic
// that will replace this.
func (e *AgentJobExecutor) checkAdditionalRepoReadAccess(ctx context.Context, gh github.ClientInterface, job *jobs.Job) (bool, error) {
	if len(job.AdditionalRepositories) == 0 {
		return false, nil
	}
	if !e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentMultiRepoRead, job) {
		return false, nil
	}

	for _, ref := range job.AdditionalRepositories {
		perm, err := gh.GetUserPermissionsForRepositoryByID(ctx, ref.RepoID, job.ActorLogin)
		if err != nil {
			return false, goerrors.Errorf("getting user permissions for additional repository %d: %w", ref.RepoID, err)
		}
		if !perm.Pull {
			e.obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("cancelling job because actor lacks read access to additional repository %d", ref.RepoID))
			err = e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusCancelled, jobs.CreateJobErrorWithMessage(joberrors.ErrInsufficientPermissions, "Actor does not have read access to all additional repositories"))
			if err != nil {
				return false, goerrors.Errorf("failed to finalize unexecuted job: %w", err)
			}
			return true, nil
		}
	}
	return false, nil
}

// resolveAdditionalRepositories maps Job.AdditionalRepositories to launcher
// AdditionalRepository entries, fetching repository metadata (NWO, owner
// login) from GitHub. The fetch also serves as a validation that each
// additional repository still exists and is accessible to the agent's
// installation token at launch time -- repositories may be deleted or have
// access revoked between job creation and execution.
//
// The lookup is gated behind the copilot_swe_agent_multi_repo_read feature
// flag; when the flag is disabled the function returns nil without making any
// API calls so the launch behavior is identical to the single-repo path.
func (e *AgentJobExecutor) resolveAdditionalRepositories(ctx context.Context, gh github.ClientInterface, job *jobs.Job) ([]launcher.AdditionalRepository, error) {
	if len(job.AdditionalRepositories) == 0 {
		return nil, nil
	}
	if !e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentMultiRepoRead, job) {
		return nil, nil
	}

	result := make([]launcher.AdditionalRepository, 0, len(job.AdditionalRepositories))
	for _, ref := range job.AdditionalRepositories {
		ghRepo, err := gh.GetRepositoryByID(ctx, ref.RepoID)
		if err != nil {
			// Surface the failure so we don't silently launch a multi-repo job
			// without one of the requested repositories. The caller will fail
			// the job, which is the right behavior since the agent prompt was
			// constructed assuming all additional repos are available.
			return nil, goerrors.Errorf("failed to fetch additional repository %d: %w", ref.RepoID, err)
		}
		owner := ghRepo.Owner.GetLogin()
		name := ghRepo.GetName()
		if owner == "" || name == "" {
			return nil, goerrors.Errorf("additional repository %d returned incomplete metadata (owner=%q, name=%q)", ref.RepoID, owner, name)
		}
		result = append(result, launcher.AdditionalRepository{
			GitHubRepo:        owner + "/" + name,
			GitHubRepoID:      ghRepo.GetID(),
			GitHubRepoOwner:   owner,
			GitHubRepoOwnerID: ghRepo.Owner.GetID(),
		})
	}
	return result, nil
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

// checkQuota checks if the user has sufficient quota to launch the agent.
// If they have quota, it simply returns nil.
// If they do not have quota, it updates the session (if applicable) to failed
// and requests reviewers on the pull request, then returns errInsufficientQuota.
func (e *AgentJobExecutor) checkQuota(ctx context.Context, gh github.ClientInterface, job *jobs.Job, repo *gg.Repository) error {
	e.obsv.LoggerWithTelemetry(ctx).Info("checking user quota for agent launch")
	hasSufficientQuota, totalQuota, tokenBasedBilling, err := e.GetQuotaStatus(ctx, job.OwnerID, job.RepoID, job.ActorID)
	if err != nil {
		// If the error is a transient failure and fail-open is enabled,
		// allow the job to proceed rather than blocking the user.
		if githubtwirp.ShouldFailOpenOnQuotaError(ctx, err, e.ffClient, e.obsv, job, "quota_check") {
			return nil
		}
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

	quotaMessage := e.insufficientQuotaMessage(totalQuota, tokenBasedBilling)

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
	launcherType := e.launcherTypeForJob(ctx, job)
	if launcherType != "" {
		telemetryErr := requestctx.SetJobLauncherType(ctx, string(launcherType))
		if telemetryErr != nil {
			e.obsv.LoggerWithTelemetry(ctx).WithError(telemetryErr).Error("failed to set launcher type in request context")
		}
	}
	al, err := e.launchers.Build(ctx, launcherType)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to build launcher")
		innerErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrActionsLaunchFailure, "Failed to launch agent"))
		if innerErr != nil {
			e.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after build failure")
			return nil, goerrors.Errorf("failed to build launcher: %w", err)
		}
		return nil, nil
	}

	agentLauncherType := al.LauncherType()
	persistSandboxCallbackFieldsBeforeCLIExec := agentLauncherType == launcher.TypeSandbox &&
		e.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSandboxPersistCallbackFieldsBeforeCLIExec, job)
	launchPersistedBeforeAgentStart := false
	if persistSandboxCallbackFieldsBeforeCLIExec {
		job.Args = *launchOpts
		job.Launcher = agentLauncherType
		launchOpts.BeforeAgentStart = func(ctx context.Context, result *launcher.LaunchResult) error {
			updatedJob, updateErr := e.updateSandboxLaunchBeforeAgentStart(ctx, job, result, launchTime)
			if updateErr != nil {
				return updateErr
			}
			job = updatedJob
			launchPersistedBeforeAgentStart = true
			return nil
		}
	}

	result, err := al.LaunchAgent(ctx, launchOpts)
	if err != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to launch agent")

		if launchPersistedBeforeAgentStart {
			e.obsv.Increment(ctx, launchFailedAfterCallbackFieldsMetric, stats.Tags{
				"launcher_type": job.ComputeType(),
			})
			innerErr := e.service.FinalizeUnexecutedJob(ctx, job, jobs.JobStatusFailed, jobs.CreateJobErrorWithMessage(joberrors.ErrActionsLaunchFailure, "Failed to launch agent"))
			if innerErr != nil {
				e.obsv.LogAndReportError(ctx, innerErr, "failed to finalize unexecuted job after launch failure")
				return nil, goerrors.Errorf("failed to launch agent: %w", err)
			}
			return nil, nil
		}

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

	if result.ComputeID != "" {
		telemetryErr := requestctx.SetJobComputeID(ctx, result.ComputeID)
		if telemetryErr != nil {
			e.obsv.LoggerWithTelemetry(ctx).WithError(telemetryErr).Error("failed to set compute ID in request context")
		}
	}

	if !persistSandboxCallbackFieldsBeforeCLIExec {
		job.Args = *launchOpts
		job.Launcher = agentLauncherType
	}
	job.CustomSetupStepsUsed = result.CustomSetupSteps
	job.RunsOn = result.RunsOn

	if launchPersistedBeforeAgentStart {
		return job, nil
	}

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

func (e *AgentJobExecutor) updateSandboxLaunchBeforeAgentStart(ctx context.Context, job *jobs.Job, result *launcher.LaunchResult, launchTime int64) (*jobs.Job, error) {
	// Sandbox callbacks can start as soon as the CLI executes, so the callback
	// routing/auth fields must be durable before this hook returns.
	if result == nil || result.ComputeID == "" {
		e.recordCallbackFieldsPersistBeforeLaunch(ctx, job, "pre_agent_update", "failure", 0)
		return nil, goerrors.New("missing sandbox compute ID before agent start")
	}
	if job.NonceHash == "" {
		e.recordCallbackFieldsPersistBeforeLaunch(ctx, job, "pre_agent_update", "failure", 0)
		return nil, goerrors.New("missing nonce hash before sandbox agent start")
	}

	persistStart := time.Now()
	launchJob := *job
	updatedJob, err := e.service.UpdateJobForLaunched(ctx, &launchJob, result.ComputeID, launchTime)
	if err != nil {
		e.recordCallbackFieldsPersistBeforeLaunch(ctx, job, "pre_agent_update", "failure", time.Since(persistStart))
		return nil, goerrors.Errorf("failed to persist launch state before agent start: %w", err)
	}
	e.recordCallbackFieldsPersistBeforeLaunch(ctx, updatedJob, "pre_agent_update", "success", time.Since(persistStart))

	telemetryErr := requestctx.SetJobComputeID(ctx, result.ComputeID)
	if telemetryErr != nil {
		e.obsv.LoggerWithTelemetry(ctx).WithError(telemetryErr).Error("failed to set compute ID in request context")
	}
	return updatedJob, nil
}

func (e *AgentJobExecutor) recordCallbackFieldsPersistBeforeLaunch(ctx context.Context, job *jobs.Job, strategy, result string, duration time.Duration) {
	tags := stats.Tags{
		"result":   result,
		"strategy": strategy,
	}
	if job != nil {
		tags["launcher_type"] = job.ComputeType()
	}
	e.obsv.Increment(ctx, callbackFieldsPersistBeforeLaunchMetric, tags)
	e.obsv.DistributionMs(ctx, callbackFieldsPersistBeforeLaunchMsMetric, tags, duration)
}
