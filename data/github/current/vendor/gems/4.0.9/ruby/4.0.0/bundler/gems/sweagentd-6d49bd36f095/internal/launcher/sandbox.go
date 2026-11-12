package launcher

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"strings"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sandbox"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// sandboxService is the interface the launcher needs from sandbox.Service.
// Defined at the consumer per https://go.dev/wiki/CodeReviewComments#interfaces.
type sandboxService interface {
	CreateSandbox(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error)
	StopSandbox(ctx context.Context, sandboxID string, actorID uint64) error
	ResumeSandbox(ctx context.Context, sandboxID string, actorID uint64) error
	ExecCopilotCLI(ctx context.Context, sandboxID string, actorID uint64, repoNWO, problemStatement string, cliFlags []string, envVars map[string]string, eventJSON string, stdinSecrets map[string]string, useCcav3 bool) error
}

// sandboxTokenMinter mints GitHub App tokens for sandbox provisioning.
// Defined at the consumer per
// https://go.dev/wiki/CodeReviewComments#interfaces.
type sandboxTokenMinter interface {
	MintUserToServerTokenForRepo(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error)
	MintServerToServerTokenForRepo(ctx context.Context, req *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error)
}

// sandboxLaunchTokenPermissions are the GitHub App permissions requested when
// minting a user-to-server token for launching an agent in a sandbox VM.
// Mirrors the permissions used by the CreateAgentCompute Twirp endpoint.
var sandboxLaunchTokenPermissions = map[string]string{
	"contents":      "write",
	"issues":        "write",
	"pull_requests": "write",
	"workflows":     "write",
	"metadata":      "read",
	"actions":       "read",
}

// sandboxGitTokenPermissions are the permissions requested for the app
// installation token used by git clone/fetch/push inside the sandbox.
var sandboxGitTokenPermissions = map[string]string{
	"contents": "write",
	"metadata": "read",
}

const (
	// CCA runs detached after launch; without inbound VM traffic, the sandbox can
	// be considered idle by the platform even while Copilot is still working.
	sandboxAutoSuspendIdleTimeoutMin int32 = 60
	sandboxAutoDeleteAfterMin        int32 = 59
)

// SandboxLauncher implements AgentLauncher by delegating to the sandbox.Service.
// It translates launcher-domain types into sandbox-domain types, relying on the
// sandbox package for VM provisioning, repo setup, and CLI execution.
type SandboxLauncher struct {
	obsv        observability.Exporters
	ffClient    featureflags.Client
	sandboxSvc  sandboxService
	tokenMinter sandboxTokenMinter
	opts        SandboxLauncherOpts
}

// SandboxLauncherOpts contains configuration options for the SandboxLauncher.
// Embeds ExternalLauncherOpts (which itself embeds AgentLauncherOpts) so that
// GetVariables can populate the full COPILOT_AGENT_* + GitHub env var set
// when running ccav3.
type SandboxLauncherOpts struct {
	ExternalLauncherOpts
}

// Ensure SandboxLauncher implements AgentLauncher.
var _ AgentLauncher = &SandboxLauncher{}

// NewSandboxLauncher creates a new SandboxLauncher.
func NewSandboxLauncher(
	obsv observability.Exporters,
	ffClient featureflags.Client,
	sandboxSvc sandboxService,
	tokenMinter sandboxTokenMinter,
	opts SandboxLauncherOpts, //nolint:gocritic // hugeParam: while the params here are larger, passing by pointer adds risk of nil dereference
) *SandboxLauncher {
	return &SandboxLauncher{
		obsv:        obsv.WithNamedLogger("sandbox-launcher"),
		ffClient:    ffClient,
		sandboxSvc:  sandboxSvc,
		tokenMinter: tokenMinter,
		opts:        opts,
	}
}

// LauncherType returns the type of this launcher.
func (s *SandboxLauncher) LauncherType() Type {
	return TypeSandbox
}

// LaunchAgent provisions a sandbox VM and launches the Copilot CLI.
// When opts.PreviousComputeID is set, the launcher first attempts to resume
// the existing sandbox. If the resume fails (corrupted VM, ADC error, etc.)
// it falls back to provisioning a fresh sandbox.
func (s *SandboxLauncher) LaunchAgent(ctx context.Context, opts *LaunchAgentOpts) (*LaunchResult, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "SandboxLauncher.LaunchAgent")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx)

	// If we have a previous sandbox, try to resume it — unless the tokens
	// have expired (launched > 1 hour ago) or LaunchedAt is missing.
	if opts.PreviousComputeID != "" && opts.PreviousComputeLaunchedAt > 0 {
		tokenAge := time.Since(time.Unix(opts.PreviousComputeLaunchedAt, 0))
		// Tokens expire after 1h. Use 55m to allow for clock skew and
		// resume latency before the token is actually used.
		if tokenAge > 55*time.Minute {
			logger.Info(fmt.Sprintf("Previous sandbox %s tokens expired (launched %s ago), creating fresh", opts.PreviousComputeID, tokenAge.Truncate(time.Minute)))
			s.obsv.Increment(ctx, "sandbox.resume_skipped_token_expiry", stats.Tags{})
		} else {
			result, fallbackAllowed, err := s.resumeAgent(ctx, opts)
			if err == nil {
				return result, nil
			}
			if !fallbackAllowed {
				return nil, ClassifyLaunchError(err, "sandbox resume failed")
			}
			// Resume failed — fall through to fresh provisioning.
			logger.WithError(err).Warn("sandbox resume failed, falling back to fresh sandbox")
			s.obsv.Increment(ctx, "sandbox.resume_fallback", stats.Tags{})
		}
	}

	logger.Info("Launching agent via sandbox")

	setup, err := s.prepareCcav3(ctx, opts)
	if err != nil {
		return nil, ClassifyLaunchError(err, "failed to prepare ccav3")
	}

	params := &sandbox.CreateSandboxParams{
		RepositoryID:         uint64(opts.GitHubRepoID),
		RepositoryOwnerID:    uint64(opts.GitHubRepoOwnerID),
		RepositoryNWO:        opts.GitHubRepo,
		BranchName:           opts.BranchName,
		ActorID:              uint64(opts.ActorID),
		AgentID:              opts.Agent.AppID(),
		ProblemStatement:     opts.ProblemStatement,
		EnvironmentVariables: setup.bootstrapEnv,
		StdinSecrets:         setup.stdinSecrets,
		Lifecycle: &sandbox.LifecycleParams{
			AutoSuspendEnabled:        true,
			AutoSuspendIdleTimeoutMin: sandboxAutoSuspendIdleTimeoutMin,
			AutoDeleteAfterMin:        sandboxAutoDeleteAfterMin,
		},
		UseCcav3:          true,
		EventFileJSON:     setup.eventJSON,
		BeforeCLIStart:    beforeAgentStartHook(opts),
		BillableOwnerID:   uint64(opts.GitHubRepoOwnerID),
		BillableOwnerType: string(opts.OwnerType),
	}

	// Apply firewall settings from the repository configuration when available.
	if opts.RepoConfig != nil {
		params.FirewallEnabled = opts.RepoConfig.GetIsFirewallEnabled()
		params.FirewallUseDefaultRules = opts.RepoConfig.GetShouldFirewallUseDefaultRules()
		params.FirewallAllowedRules = opts.RepoConfig.GetFirewallAllowedRules()
	} else if isFirewallEnabledByDefault(ctx, s.ffClient, &s.opts.AgentLauncherOpts) {
		params.FirewallEnabled = true
		params.FirewallUseDefaultRules = true
	}

	result, err := s.sandboxSvc.CreateSandbox(ctx, params)
	if err != nil {
		return nil, ClassifyLaunchError(err, "sandbox launch failed")
	}

	logger.Info(fmt.Sprintf("Sandbox agent launched: %s", result.SandboxID))

	return &LaunchResult{
		ComputeID: result.SandboxID,
	}, nil
}

// TerminateAgent stops a running sandbox VM. The VM is suspended (not
// deleted) so it can be resumed later. If the sandbox is already stopped
// (e.g. from a previous cancel or idle timeout), this is treated as
// success so the caller can proceed with job finalization.
func (s *SandboxLauncher) TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "SandboxLauncher.TerminateAgent")
	defer span.End()

	err := s.sandboxSvc.StopSandbox(ctx, opts.ComputeID, uint64(opts.ActorID))
	if err != nil && isSandboxNotRunning(err) {
		s.obsv.LoggerWithTelemetry(ctx).Info("sandbox already stopped, treating cancel as success")
		return nil
	}
	return err
}

// sandboxNotRunningError is the error title returned by the Sandbox platform
// when attempting to stop a sandbox that is already suspended, stopped, or
// deleted. Matched by substring because the Twirp client wraps the 409
// response as a generic internal error with the JSON body in the message.
const sandboxNotRunningError = "SandboxNotRunning"

// isSandboxNotRunning returns true when the Sandbox platform responds with a
// 409 "SandboxNotRunning" error, meaning the sandbox is already in a
// non-running state (suspended, stopped, or deleted).
func isSandboxNotRunning(err error) bool {
	return err != nil && strings.Contains(err.Error(), sandboxNotRunningError)
}

// resumeAgent resumes an existing sandbox and starts a fresh ccav3 session
// with new tokens and job context. fallbackAllowed is false once the caller's
// BeforeAgentStart hook has run, because that hook may have already persisted
// launch bookkeeping that should not be duplicated by a fresh fallback.
func (s *SandboxLauncher) resumeAgent(ctx context.Context, opts *LaunchAgentOpts) (*LaunchResult, bool, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "SandboxLauncher.resumeAgent")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx)
	logger.Info(fmt.Sprintf("Attempting to resume sandbox: %s", opts.PreviousComputeID))

	err := s.sandboxSvc.ResumeSandbox(ctx, opts.PreviousComputeID, uint64(opts.ActorID))
	if err != nil {
		return nil, true, goerrors.Errorf("resume sandbox %s failed: %w", opts.PreviousComputeID, err)
	}

	// Mint fresh tokens and build env vars + event file for the new job.
	setup, err := s.prepareCcav3(ctx, opts)
	if err != nil {
		s.stopSandboxBestEffort(ctx, opts.PreviousComputeID, opts.ActorID)
		return nil, true, goerrors.Errorf("failed to prepare ccav3 for resume: %w", err)
	}

	launchRecorded := false
	if opts.BeforeAgentStart != nil {
		err = opts.BeforeAgentStart(ctx, &LaunchResult{ComputeID: opts.PreviousComputeID})
		if err != nil {
			s.stopSandboxBestEffort(ctx, opts.PreviousComputeID, opts.ActorID)
			return nil, false, goerrors.Errorf("before agent start on resumed sandbox %s: %w", opts.PreviousComputeID, err)
		}
		launchRecorded = true
	}

	// ExecCopilotCLI writes the event file and starts ccav3 on the resumed sandbox.
	err = s.sandboxSvc.ExecCopilotCLI(ctx, opts.PreviousComputeID, uint64(opts.ActorID),
		opts.GitHubRepo, opts.ProblemStatement, nil, setup.bootstrapEnv, setup.eventJSON, setup.stdinSecrets, true)
	if err != nil {
		s.stopSandboxBestEffort(ctx, opts.PreviousComputeID, opts.ActorID)
		return nil, !launchRecorded, goerrors.Errorf("start ccav3 on resumed sandbox %s failed: %w", opts.PreviousComputeID, err)
	}

	logger.Info(fmt.Sprintf("Sandbox resumed: %s", opts.PreviousComputeID))
	s.obsv.Increment(ctx, "sandbox.resume_success", stats.Tags{})

	return &LaunchResult{
		ComputeID: opts.PreviousComputeID,
	}, false, nil
}

func beforeAgentStartHook(opts *LaunchAgentOpts) func(context.Context, string) error {
	if opts.BeforeAgentStart == nil {
		return nil
	}
	return func(ctx context.Context, sandboxID string) error {
		return opts.BeforeAgentStart(ctx, &LaunchResult{ComputeID: sandboxID})
	}
}

// stopSandboxBestEffort attempts to stop a sandbox, logging any failure.
func (s *SandboxLauncher) stopSandboxBestEffort(ctx context.Context, sandboxID string, actorID int64) {
	stopErr := s.sandboxSvc.StopSandbox(ctx, sandboxID, uint64(actorID))
	if stopErr != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(stopErr).Warn("failed to stop sandbox after resume failure")
	}
}

// mintUserToken mints a user-to-server token for the given actor/repo/agent with
// the requested permissions.
func (s *SandboxLauncher) mintUserToken(ctx context.Context, actorID, repoID, agentID int64, permissions map[string]string) (string, error) {
	resp, err := s.tokenMinter.MintUserToServerTokenForRepo(ctx, &sweagentdTwirp.MintUserToServerTokenForRepoRequest{
		UserId:       uint64(actorID),
		RepositoryId: uint64(repoID),
		AgentId:      agentID,
		Permissions:  permissions,
	})
	if err != nil {
		return "", err
	}
	if resp == nil || resp.Token == "" {
		return "", goerrors.New("empty user-to-server token")
	}
	return resp.Token, nil
}

// mintServerToken mints a server-to-server installation token for the given
// repo/agent with the requested permissions.
func (s *SandboxLauncher) mintServerToken(ctx context.Context, repoID, agentID int64, permissions map[string]string) (string, error) {
	resp, err := s.tokenMinter.MintServerToServerTokenForRepo(ctx, &sweagentdTwirp.MintServerToServerTokenForRepoRequest{
		RepositoryId: uint64(repoID),
		AgentId:      agentID,
		Permissions:  permissions,
	})
	if err != nil {
		return "", err
	}
	if resp == nil || resp.Token == "" {
		return "", goerrors.New("empty server-to-server token")
	}
	return resp.Token, nil
}

// buildEventFileJSON constructs the synthetic event JSON that ccav3's
// requireInput/readAgentInputs reads from GITHUB_EVENT_PATH. Same format
// as the Docker launcher's writeAgentInputsEventFile.
func buildEventFileJSON(envVars map[string]string) (string, error) {
	inputsJSON, err := json.Marshal(envVars)
	if err != nil {
		return "", goerrors.Errorf("failed to marshal agent inputs: %w", err)
	}
	event := map[string]any{
		"inputs": map[string]string{
			"COPILOT_AGENT_INPUTS": string(inputsJSON),
		},
	}
	eventJSON, err := json.Marshal(event)
	if err != nil {
		return "", goerrors.Errorf("failed to marshal event file: %w", err)
	}
	return string(eventJSON), nil
}

// ccav3Setup holds the artifacts needed to start a ccav3 session.
type ccav3Setup struct {
	bootstrapEnv map[string]string
	eventJSON    string
	stdinSecrets map[string]string
}

// prepareCcav3 mints fresh tokens and builds the three handoff surfaces used
// by the Actions ccav3 entrypoint: non-secret bootstrap env, event-file inputs,
// and stdin-delivered secrets.
func (s *SandboxLauncher) prepareCcav3(ctx context.Context, opts *LaunchAgentOpts) (*ccav3Setup, error) {
	apiToken, err := s.mintUserToken(ctx, opts.ActorID, opts.GitHubRepoID, opts.Agent.AppID(), sandboxLaunchTokenPermissions)
	if err != nil {
		return nil, goerrors.Errorf("failed to mint sandbox launch token: %w", err)
	}
	gitToken, err := s.mintServerToken(ctx, opts.GitHubRepoID, opts.Agent.AppID(), sandboxGitTokenPermissions)
	if err != nil {
		return nil, goerrors.Errorf("failed to mint sandbox git token: %w", err)
	}

	vars := GetVariables(ctx, s.ffClient, s.opts, opts, nil)

	eventInputs := make(map[string]string, len(vars))
	bootstrapEnv := make(map[string]string, len(vars)+8)
	for k, v := range vars {
		if v.Secure && !isAllowedSecureCcav3EventInput(k) {
			continue
		}
		eventInputs[k] = v.Value
		if !v.Secure {
			bootstrapEnv[k] = v.Value
		}
	}
	eventJSON, err := buildEventFileJSON(eventInputs)
	if err != nil {
		return nil, goerrors.Errorf("failed to build event file: %w", err)
	}

	// Run ccav3 with StandaloneRunner semantics. GITHUB_EVENT_PATH remains a
	// temporary compatibility shim for ccav3's current readAgentInputs path.
	// ccav3 owns the repository clone so it can report clone/setup progress.
	//
	// We deliberately do NOT set GITHUB_WORKSPACE here. With
	// COPILOT_CCA_V3_USE_EXISTING_WORKSPACE=false the runtime SDK-clones the
	// repo itself (to /tmp/workspace/<owner>/<repo>) rather than reusing
	// sandbox.RepositoryWorkDir (/workspaces/<repo>), so that path never exists
	// on the sandbox. The runtime's local MCP config processor defaults each MCP
	// server's cwd to GITHUB_WORKSPACE when set; pointing it at the bogus path
	// caused "spawn node/npx ENOENT" failures for the MCP servers. Leaving
	// GITHUB_WORKSPACE unset makes the MCP children inherit the CLI process's
	// working directory (the real checkout), so they spawn with a valid cwd.
	maps.Copy(bootstrapEnv, map[string]string{
		"COPILOT_CCA_V3_USE_EXISTING_WORKSPACE": "false",
		"GITHUB_EVENT_PATH":                     sandbox.EventFilePath,
		"COPILOT_AGENT_RUNNER_TYPE":             "STANDALONE",
	})
	if opts.GitHubRepo != "" {
		bootstrapEnv["GITHUB_REPOSITORY"] = opts.GitHubRepo
	}
	if opts.GitHubRepoID != 0 {
		bootstrapEnv["GITHUB_REPOSITORY_ID"] = fmt.Sprintf("%d", opts.GitHubRepoID)
	}
	if opts.GitHubRepoOwner != "" {
		bootstrapEnv["GITHUB_REPOSITORY_OWNER"] = opts.GitHubRepoOwner
	}
	if opts.GitHubRepoOwnerID != 0 {
		bootstrapEnv["GITHUB_REPOSITORY_OWNER_ID"] = fmt.Sprintf("%d", opts.GitHubRepoOwnerID)
	}
	if s.opts.GitHubServerURL != "" {
		bootstrapEnv["GITHUB_SERVER_URL"] = s.opts.GitHubServerURL
	}
	if additionalRepositories := addAdditionalRepositoryVariables(opts); additionalRepositories != "" {
		bootstrapEnv["ADDITIONAL_GITHUB_REPOSITORIES"] = additionalRepositories
	}

	githubCopilotGitHubToken := apiToken
	if getGitHubTokenSecretNames(ctx, s.ffClient, opts).Shell == "GITHUB_COPILOT_GITHUB_TOKEN" {
		githubCopilotGitHubToken = gitToken
	}
	stdinSecrets := map[string]string{
		"GITHUB_TOKEN":                    gitToken,
		"GITHUB_COPILOT_GITHUB_TOKEN":     githubCopilotGitHubToken,
		"GITHUB_COPILOT_API_TOKEN":        apiToken,
		"GITHUB_COPILOT_INTEGRATION_ID":   s.opts.CopilotIntegrationID,
		"COPILOT_INTEGRATION_ID_OVERRIDE": "",
		"CAPI_HMAC_KEY_OVERRIDE":          "",
		"COPILOT_JOB_NONCE":               opts.Nonce,
		"GITHUB_VERIFICATION_TOKEN":       opts.Nonce,
	}

	return &ccav3Setup{
		bootstrapEnv: bootstrapEnv,
		eventJSON:    eventJSON,
		stdinSecrets: stdinSecrets,
	}, nil
}

func isAllowedSecureCcav3EventInput(key string) bool {
	switch key {
	case "COPILOT_JOB_NONCE":
		// ccav3 still requires this through readAgentInputs(); #12657 tracks
		// removing nonce/signing secrets from file-backed launch inputs.
		return true
	default:
		return false
	}
}
