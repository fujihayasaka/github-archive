// Package launcher provides functionality to launch and manage agents in different
// environments.
package launcher

import (
	"context"

	"github.com/github/sweagentd/internal/environmentfeatures"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

const (
	copilotSWEAgentFirewallFFName           = "copilot_swe_agent_firewall_enabled_by_default"
	copilotSWEAgentOnlineEvalDisabledFFName = "copilot_swe_agent_online_evaluation_disabled"
)

// Type represents the type of launcher being used.
type Type string

const (
	// TypeActions represents the GitHub Actions launcher.
	TypeActions Type = "actions"
	// TypeDocker represents the Docker launcher.
	TypeDocker Type = "docker"
	// TypeSandbox represents the Sandbox VM launcher.
	TypeSandbox Type = "sandbox"
)

// LaunchResult is the result of a successful agent launch.
type LaunchResult struct {
	// ComputeID is the identifier for the compute instance (e.g., workflow run ID).
	ComputeID string
	// CustomSetupSteps indicates whether custom setup steps were successfully applied.
	CustomSetupSteps bool
	// RunsOn contains the actual runs-on value from setup steps, or empty string if not specified.
	RunsOn string
}

// AgentLauncher is an interface for launching an agent.
//
// Compute lifecycle:
//   - LaunchAgent provisions compute and starts the agent.
//   - TerminateAgent stops the agent. For Actions, this cancels the workflow
//     run. For Sandbox, this suspends the VM so it can be resumed later.
//     The compute itself is preserved.
type AgentLauncher interface {
	LaunchAgent(ctx context.Context, opts *LaunchAgentOpts) (*LaunchResult, error)
	TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error
	LauncherType() Type
}

// AdditionalRepository identifies a non-primary repository that the agent has
// access to in a multi-repo job. The fields mirror the primary repository
// fields on LaunchAgentOpts so the runtime can clone and navigate the repo.
type AdditionalRepository struct {
	// GitHubRepo is the repository in the form of `owner/repository`.
	GitHubRepo string `json:"github_repo"`
	// GitHubRepoID is the repository's global database ID.
	GitHubRepoID int64 `json:"github_repo_id"`
	// GitHubRepoOwner is the repository owner's login.
	GitHubRepoOwner string `json:"github_owner"`
	// GitHubRepoOwnerID is the repository owner's database ID.
	GitHubRepoOwnerID int64 `json:"github_owner_id"`
}

// LaunchAgentOpts contains options for launching an agent.
type LaunchAgentOpts struct {
	// The GitHub repository in the form of `owner/repository`
	GitHubRepo string `json:"github_repo"`
	// The GitHub repository global ID
	GitHubRepoID   int64  `json:"github_repo_id"`
	GitHubRepoName string `json:"github_repo_name"`
	// The GitHub repository owner login
	GitHubRepoOwner   string `json:"github_repo_owner"`
	GitHubRepoOwnerID int64  `json:"github_repo_owner_id"`
	GitHubBaseCommit  string `json:"github_base_commit"`

	// AdditionalRepositories is the list of additional repositories that the
	// agent has access to beyond the primary repository identified by the
	// GitHubRepo* fields above. Used to support multi-repo jobs where the agent
	// needs context from more than one repository.
	//
	// This field is gated behind the copilot_swe_agent_multi_repo_read feature
	// flag and is populated by the job executor when the flag is enabled.
	AdditionalRepositories []AdditionalRepository `json:"additional_repositories,omitempty"`
	// The issue number that the agent is responding to
	IssueNumber int `json:"issue_number"`
	// Properties related to the task being performed
	ProblemStatement  string `json:"problem_statement"`
	ContentFilterMode string `json:"content_filter_mode"`
	RunName           string `json:"run_name"`

	JobID        string `json:"job_id"`
	JobEventType string `json:"job_event_type"`
	IsTriggered  bool   `json:"is_triggered,omitempty"`
	Action       string `json:"action"`
	Push         bool   `json:"push"`
	Model        string `json:"model"`
	PRNumber     int    `json:"pr_number"`
	BranchName   string `json:"branch_name"`
	// ActorID is the ID of the GitHub user that triggered the copilot agent job.
	// This is the actor that will be attributed to API calls made by the agent
	// as well as git commits made by the agent. Thus, the actor must have the
	// necessary permissions to perform the required actions.
	ActorID int64 `json:"actor_id"`
	// ActorLogin is the login of the GitHub user that triggered the copilot agent
	// job. This is the actor that will be attributed to API calls made by the
	// agent as well as git commits made by the agent. Thus, the actor must have
	// the necessary permissions to perform the required actions.
	ActorLogin string `json:"actor_login"`

	// ActorType indicates whether the actor is a user or an organization.
	// When "org", ActorID is the org ID and billing is routed to the org's seat pool.
	// Passed to the runtime as COPILOT_AGENT_ACTOR_TYPE for the monolith secrets provider.
	ActorType string `json:"actor_type,omitempty"`

	// OwnerType indicates whether the repository owner is a user or an organization.
	OwnerType sweagentd.OwnerType `json:"owner_type,omitempty"`

	// Encrypted github token or "" after the job is done
	GitHubToken string `json:"-"`
	// Number of commits to pull for PR comment fix scenarios
	CommitCount int `json:"commit_count"`
	// UseSessions reports whether the user has this feature enabled
	UseSessions bool `json:"use_sessions"`
	// UseAsyncSessions indicates whether the assignment uses async sessions
	UseAsyncSessions bool   `json:"use_async_sessions"`
	SessionID        string `json:"session_id"`
	// PreviousSessionIDs are the IDs of previously completed sessions for the pull request,
	// ordered from most recent to oldest
	PreviousSessionIDs []string `json:"-"`
	// ResumeSessionID, when non-empty, identifies a session this job should
	// resume. Forwarded to the runtime container as
	// COPILOT_AGENT_RESUME_SESSION_ID so the runtime can scope its
	// session-history snapshot lookup to this session and call
	// client.resumeSession with it.
	ResumeSessionID string `json:"resume_session_id,omitempty"`
	// Nonce is a random value used to validate callback requests come from the right workflow run
	Nonce                       string                `json:"-"` // IGNORE: This shouldn't be persisted in the job cosmos document
	CustomAgent                 sweagentd.CustomAgent `json:"-"` // The custom agent is already persisted on the job
	Experiments                 string                `json:"experiments,omitempty"`
	ExperimentAssignmentContext string                `json:"experiment_assignment_context,omitempty"`

	// Features describes the features configured for the job environment.
	// This is a top-level property matching the twirp API structure.
	Features environmentfeatures.Features `json:"-"`

	// SnippyBlockingMode indicates how the agent should handle code that matches public code.
	SnippyBlockingMode sweagentdTwirp.SnippyBlockingMode `json:"snippy_blocking_mode,omitempty"`

	// IsAutoMode indicates whether auto model selection was used for this job.
	IsAutoMode bool `json:"is_auto_mode,omitempty"`

	// ValidationToolSettings contains per-tool validation settings for the repository.
	UseCodeQL              bool `json:"use_codeql,omitempty"`
	UseCCR                 bool `json:"use_ccr,omitempty"`
	UseSecretScanning      bool `json:"use_secret_scanning,omitempty"`
	UseDependencyVulnCheck bool `json:"use_dependency_vuln_checks,omitempty"`

	// RepoConfig is the repository configuration returned by IsAgentEnabled.
	// It is threaded through from the job executor to avoid redundant Twirp calls.
	RepoConfig *sweagentdTwirp.ConfigurationForRepositoryResponse `json:"-"`

	// SignCommits indicates whether the repository requires signed commits
	// based on branch protection rules or repository rulesets.
	SignCommits bool `json:"sign_commits,omitempty"`

	// PreviousComputeID, when non-empty, identifies a compute instance from a
	// previous job that the launcher should try to resume instead of provisioning
	// fresh compute. If the resume attempt fails, the launcher falls back to
	// creating a new compute instance. Only meaningful for launcher types that
	// support suspend/resume (e.g., Sandbox).
	PreviousComputeID string `json:"-"`
	// PreviousComputeLaunchedAt is the Unix timestamp when the previous job
	// that owns PreviousComputeID was launched. Used to skip resume when
	// tokens have expired (>1 hour).
	PreviousComputeLaunchedAt int64 `json:"-"`

	// BeforeAgentStart is called synchronously after compute exists but before
	// the agent process starts. Launchers that can split provisioning from
	// agent startup use this hook to let callers persist ComputeID before
	// callbacks are possible. Once the hook succeeds, launchers must not fall
	// back to a second compute target because callers may have recorded
	// non-idempotent launch bookkeeping for this compute.
	BeforeAgentStart func(context.Context, *LaunchResult) error `json:"-"`

	// CanWriteWorkflows records whether the triggering credential had
	// workflows:write at job creation. Tri-state: nil ⇒ not checked (FF off
	// or out-of-scope path); &true ⇒ allowed; &false ⇒ denied.
	CanWriteWorkflows *bool `json:"can_write_workflows,omitempty"`

	Agent sweagentd.AgenticApp `json:"-"`
}

// TerminateAgentOpts contains options for terminating an agent.
type TerminateAgentOpts struct {
	ActorID   int64
	OwnerID   int64
	RepoID    int64
	RepoOwner string
	RepoName  string
	ComputeID string
	AgentID   int64
	Client    github.ClientInterface
}

// GetActorID returns the actor ID associated with the launch options.
// This method satisfies the sweagentd.Actor interface for LaunchAgentOpts.
func (o *LaunchAgentOpts) GetActorID() int64 {
	return o.ActorID
}

// GetRepositoryID returns the repository ID associated with the launch options.
// This method satisfies the sweagentd.Repository interface for LaunchAgentOpts.
func (o *LaunchAgentOpts) GetRepositoryID() int64 {
	return o.GitHubRepoID
}

// GetOwnerID returns the owner ID associated with the launch options.
// This method satisfies the sweagentd.Repository interface for LaunchAgentOpts.
func (o *LaunchAgentOpts) GetOwnerID() int64 {
	return o.GitHubRepoOwnerID
}
