package launcher

import (
	"context"
	"fmt"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/google/uuid"
)

const copilotSWEAgentFirewallFFName = "copilot_swe_agent_firewall_enabled_by_default"
const copilotSWEAgentOnlineEvalDisabledFFName = "copilot_swe_agent_online_evaluation_disabled"

type LauncherType string

const (
	LauncherTypeActions LauncherType = "actions"
	LauncherTypeDocker  LauncherType = "docker"
)

// AgentLauncher is an interface for launching an agent.
type AgentLauncher interface {
	LaunchAgent(ctx context.Context, opts LaunchAgentOpts) (string, error)
	TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error
	LauncherType() LauncherType
}

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
	// The issue number that the agent is responding to
	IssueNumber int `json:"issue_number"`
	// Properties related to the task being performed
	ProblemStatement  string `json:"problem_statement"`
	ContentFilterMode string `json:"content_filter_mode"`
	RunName           string `json:"run_name"`

	JobID        string `json:"job_id"`
	JobEventType string `json:"job_event_type"`
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
	// Encrypted github token or "" after the job is done
	GitHubToken string `json:"-"`
	// Number of commits to pull for PR comment fix scenarios
	CommitCount int `json:"commit_count"`
	// UseSessions reports whether the user has this feature enabled
	UseSessions bool   `json:"use_sessions"`
	SessionID   string `json:"session_id"`
	// PreviousSessionIDs are the IDs of previously completed sessions for the pull request,
	// ordered from most recent to oldest
	PreviousSessionIDs []string `json:"-"`
	// Nonce is a random value used to validate callback requests come from the right workflow run
	Nonce                       string                `json:"-"` // IGNORE: This shouldn't be persisted in the job cosmos document
	CustomAgent                 sweagentd.CustomAgent `json:"-"` // The custom agent is already persisted on the job
	Experiments                 string                `json:"experiments,omitempty"`
	ExperimentAssignmentContext string                `json:"experiment_assignment_context,omitempty"`
}

type TerminateAgentOpts struct {
	OwnerID   int64
	RepoID    int64
	RepoOwner string
	RepoName  string
	ComputeID string
	Client    github.ClientInterface
}

func generateComputeID() string {
	return fmt.Sprintf("agent-%s", uuid.NewString())
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

// NewFromConfig creates a launcher configured for the environment.
func NewFromConfig(
	cfg *config.Config,
	obsv observability.Exporters,
	ghTwirp githubtwirp.ClientInterface,
	ffClient featureflags.Client,
	githubClientFactory github.ClientFactoryInterface,
	spokes sweagentd.Spokes,
) (al AgentLauncher, err error) {
	if cfg.AgentLauncher == "" {
		if cfg.IsDevelopment() {
			cfg.AgentLauncher = config.AgentLauncherDocker
		} else {
			// Launcher config should be explicitly set in production
			return nil, fmt.Errorf("AGENT_LAUNCHER is not set and not running in development")
		}
	}

	runtimeVersion := fmt.Sprintf("runtime-%s", cfg.Sha)

	// TODO: Outbound calls need to support tenant awareness #3815
	agentLauncherOpts := AgentLauncherOpts{
		CopilotAPIURL:                        cfg.CopilotAPIURL,
		UploadsURL:                           cfg.GitHubUploadsURL,
		RuntimeVersion:                       runtimeVersion,
		DownloadsURL:                         cfg.GitHubDownloadsURL,
		AgentCallbackURL:                     cfg.AgentCallbackURL,
		GitHubCommitEmail:                    cfg.GitHubCommitEmail,
		GitHubCommitLogin:                    cfg.GitHubCommitLogin,
		ModelOverride:                        cfg.ModelOverride,
		AgentDebug:                           cfg.AgentDebug,
		AgentFirewallEnabledDefault:          cfg.AgentFirewallEnabledDefault,
		AgentFirewallRuleSetAllowListDefault: cfg.AgentFirewallRuleSetAllowListDefault,
		AgentFirewallRequiredAllowList:       cfg.AgentFirewallRequiredAllowList,
		Environment:                          cfg.EnvironmentName,
		IsDevelopmentEnvironment:             cfg.IsDevelopment(),
		IsProximaEnvironment:                 cfg.Environment == config.EnvironmentProxima,
		MCPEnabled:                           cfg.MCPEnabled,
		AgentTimeoutMin:                      cfg.AgentTimeoutMin,
	}

	externalLauncherOpts := ExternalLauncherOpts{
		AgentLauncherOpts:    agentLauncherOpts,
		GitHubServerURL:      cfg.GitHubServerURL,
		CAPIHMACKey:          cfg.CapiHMACKey,
		CopilotIntegrationID: cfg.CopilotIntegrationID,
	}

	switch cfg.AgentLauncher {
	case config.AgentLauncherActions:
		al, err = NewActionsLauncher(obsv, ffClient, githubClientFactory, ghTwirp, spokes, ActionsLauncherOpts{
			AgentLauncherOpts:          agentLauncherOpts,
			ActionsDefaultRunsOnLabels: cfg.ActionsDefaultRunsOnLabels,
		})
		if err != nil {
			return nil, fmt.Errorf("failed to create Actions launcher: %w", err)
		}
	case config.AgentLauncherDocker:
		if !cfg.IsDevelopment() {
			return nil, fmt.Errorf("docker launcher is only supported in development")
		}
		al, err = NewDockerLauncher(obsv, ffClient, DockerLauncherOpts{
			ExternalLauncherOpts:    externalLauncherOpts,
			AnthropicKeyOpts:        AnthropicKeyOpts{AnthropicAPIKey: cfg.AnthropicAPIKey},
			ContainerImage:          cfg.DockerAgentContainerImage,
			DockerAIPProxy:          cfg.DockerAIPProxy,
			DockerUseHostNetworking: cfg.DockerUseHostNetworking,
			DockerMapPort:           cfg.DockerMapPort,
		})
		if err != nil {
			return nil, fmt.Errorf("failed to create Docker launcher: %w", err)
		}

	default:
		return nil, fmt.Errorf("unknown agent launcher: %s", cfg.AgentLauncher)
	}

	return al, nil
}
