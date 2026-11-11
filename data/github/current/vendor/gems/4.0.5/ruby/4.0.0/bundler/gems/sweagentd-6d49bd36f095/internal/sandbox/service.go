// Package sandbox provides a service for creating and managing GitHub Sandbox VMs.
// It handles the full lifecycle: VM provisioning, repository setup, and CLI launch.
package sandbox

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	launchsandbox "github.com/github/launch/services/pb/sandbox"
	sandboxsdk "github.com/github/sandbox/go/sandbox"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

const (
	defaultCPU    = "4"
	defaultMemory = "8Gi"

	sandboxAgentIDLabel      = "sweagentd.agent_id"
	sandboxRepositoryIDLabel = "sweagentd.repository_id"
)

// ServiceOpts contains configuration for the sandbox Service.
type ServiceOpts struct {
	LaunchTwirpBaseURL    string
	LaunchTwirpHMACKey    string
	MissionControlBaseURL string
	UseDockerBackend      bool
	GitHubServerURL       string
	CopilotAPIURL         string
	// RequiredFirewallAllowList is the comma-separated baseline allowlist
	// (URLs, hostnames, IPs) that must always be reachable when the egress
	// firewall is enabled. Callers typically pass
	// Config.AgentFirewallRequiredAllowList — the same value the Actions
	// and Docker launchers send via COPILOT_AGENT_FIREWALL_ALLOW_LIST.
	// Sandbox internally reduces it to host-only patterns for Launch's
	// EgressPolicy. Proxima `<tenant>` placeholders must be resolved
	// upstream (Actions does this per-job via
	// replaceFirewallTenantPlaceholders).
	RequiredFirewallAllowList string
}

// CreateSandboxParams are the parameters for creating a sandbox.
type CreateSandboxParams struct {
	RepositoryID      uint64
	RepositoryOwnerID uint64
	RepositoryNWO     string
	BranchName        string
	ActorID           uint64
	AgentID           int64
	ProblemStatement  string
	CPU               string
	Memory            string
	// EnvironmentVariables are caller-provided env vars to inject into the sandbox.
	// These are merged with service-determined env vars (PATH, HOME, MC config, etc.).
	// For ccav3, this must only contain non-secret bootstrap env; runtime auth
	// secrets are delivered through StdinSecrets.
	EnvironmentVariables map[string]string
	CLIFlags             []string
	Lifecycle            *LifecycleParams
	// UseCcav3, when true, starts ccav3 (node dist-cca-v3/index.js) instead
	// of bare copilot CLI. Requires the cca-runtime sandbox image. Runtime
	// inputs are read from EventFileJSON, not EnvironmentVariables.
	UseCcav3 bool
	// EventFileJSON is the COPILOT_AGENT_INPUTS event file content to write
	// into the sandbox. Required when UseCcav3 is true because ccav3's
	// requireInput() reads from the event file, not process.env.
	EventFileJSON string
	// BeforeCLIStart runs after the sandbox is ready and configured but before
	// the agent process starts.
	BeforeCLIStart func(context.Context, string) error
	// EnvironmentFilePath points to a shell env file to source immediately
	// before launching ccav3. Used on resume to inject non-secret bootstrap env
	// into the new ccav3 process without re-creating the VM.
	EnvironmentFilePath string
	// StdinSecrets contains secrets to write to stdin for ccav3, matching the
	// Actions runtime handoff that avoids inherited process env exposure.
	StdinSecrets map[string]string
	// Firewall settings from repository configuration.
	FirewallEnabled         bool
	FirewallUseDefaultRules bool
	FirewallAllowedRules    []string
	// BillableOwnerID is the database ID of the entity that should be billed
	// for this sandbox. Forwarded to Launch as billable_owner_id.
	BillableOwnerID uint64
	// BillableOwnerType is the type of the entity that should be billed for
	// this sandbox. One of "Enterprise", "Organization", or "User". Forwarded
	// to Launch as billable_owner_type. When unset, Launch skips the
	// ConfigsD-backed access control check.
	BillableOwnerType string
}

// CreateSandboxResult is the result of creating a sandbox.
type CreateSandboxResult struct {
	SandboxID string
}

// Service provides sandbox lifecycle management.
type Service struct {
	obsv           observability.Exporters
	ffClient       featureflags.Client
	ghTwirp        githubtwirp.ClientInterface
	opts           ServiceOpts
	backendFactory func(actorID uint64) (sandboxBackend, error)
	requiredHosts  []*launchsandbox.HostRule
}

// NewService creates a new sandbox Service.
func NewService(obsv observability.Exporters, ffClient featureflags.Client, ghTwirp githubtwirp.ClientInterface, opts ServiceOpts) *Service {
	return &Service{
		obsv:          obsv.WithNamedLogger("sandbox-service"),
		ffClient:      ffClient,
		ghTwirp:       ghTwirp,
		opts:          opts,
		requiredHosts: buildRequiredHostRules(opts),
	}
}

// CreateSandbox provisions a sandbox VM, sets it up, and launches the Copilot CLI.
//
//nolint:maintidx // complexity is inherent to the orchestration logic
func (s *Service) CreateSandbox(ctx context.Context, params *CreateSandboxParams) (*CreateSandboxResult, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.CreateSandbox")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(kvp.Uint64("actor_id", params.ActorID))
	metricTags := s.obsv.TelemetryTags(ctx)
	launchStart := time.Now()

	envMap := s.buildEnvVars(params)
	err := validateRequiredEnvVars(envMap, params.RepositoryNWO != "", params)
	if err != nil {
		return nil, err
	}

	backend, err := s.newBackend(params.ActorID)
	if err != nil {
		return nil, goerrors.Errorf("failed to create sandbox backend: %w", err)
	}

	logger.Info("Creating sandbox VM")
	createStart := time.Now()
	sb, err := backend.createSandbox(ctx, s.buildCreateSandboxOptions(ctx, params, envMap))
	if err != nil {
		logger.WithError(err).Error("Failed to create sandbox VM")
		s.obsv.Statter.Counter("sandbox.create", metricTags.Merge(stats.Tags{"success": "false"}), 1)
		return nil, goerrors.Errorf("failed to create sandbox: %w", err)
	}

	sandboxID := sb.ID
	sandboxLogger := logger.WithFields(kvp.String("sandbox_id", sandboxID))
	s.obsv.DistributionMs(ctx, "sandbox.create_duration_ms", metricTags, time.Since(createStart))
	sandboxLogger.Info("Sandbox created",
		kvp.String("state", sb.State),
	)

	if !IsSandboxRunning(sb.State) {
		sandboxLogger.Info("Waiting for sandbox to be ready",
			kvp.String("state", sb.State),
		)
		readyStart := time.Now()
		err = s.waitForReady(ctx, backend, sandboxID)
		if err != nil {
			s.cleanupSandbox(context.WithoutCancel(ctx), backend, sandboxID, params.ActorID)
			return nil, goerrors.Errorf("sandbox failed to become ready: %w", err)
		}
		s.obsv.DistributionMs(ctx, "sandbox.ready_duration_ms", metricTags, time.Since(readyStart))
	}

	s.writeMCPConfig(ctx, backend, sb, params)

	if params.RepositoryNWO != "" && !params.UseCcav3 {
		cloneStart := time.Now()
		sandboxLogger.Info("Cloning repository")
		err = s.cloneRepository(ctx, backend, sb, params.RepositoryNWO, params.BranchName)
		if err != nil {
			if !s.opts.UseDockerBackend {
				s.cleanupSandbox(context.WithoutCancel(ctx), backend, sandboxID, params.ActorID)
			}
			return nil, goerrors.Errorf("failed to clone repository: %w", err)
		}
		s.obsv.DistributionMs(ctx, "sandbox.clone_duration_ms", metricTags, time.Since(cloneStart))
		sandboxLogger.Info("Repository cloned")
	}

	// Write the COPILOT_AGENT_INPUTS event file for ccav3.
	if params.UseCcav3 && params.EventFileJSON != "" {
		err = s.writeLaunchFiles(ctx, backend, sb, params.EventFileJSON, nil)
		if err != nil {
			s.cleanupSandbox(context.WithoutCancel(ctx), backend, sandboxID, params.ActorID)
			return nil, goerrors.Errorf("failed to write event file: %w", err)
		}
	}

	if params.BeforeCLIStart != nil {
		err = params.BeforeCLIStart(ctx, sandboxID)
		if err != nil {
			s.cleanupSandbox(context.WithoutCancel(ctx), backend, sandboxID, params.ActorID)
			return nil, goerrors.Errorf("before CLI start: %w", err)
		}
	}

	err = s.startCopilotCLI(ctx, backend, sb, params)
	if err != nil {
		sandboxLogger.WithError(err).Error("Failed to start Copilot CLI")
		s.cleanupSandbox(context.WithoutCancel(ctx), backend, sandboxID, params.ActorID)
		s.obsv.Statter.Counter("sandbox.create", metricTags.Merge(stats.Tags{"success": "false"}), 1)
		return nil, goerrors.Errorf("failed to start CLI: %w", err)
	}

	s.obsv.DistributionMs(ctx, "sandbox.launch_duration_ms", metricTags, time.Since(launchStart))
	s.obsv.Statter.Counter("sandbox.create", metricTags.Merge(stats.Tags{"success": "true"}), 1)

	return &CreateSandboxResult{SandboxID: sandboxID}, nil
}

// IsSandboxRunning reports whether a sandbox state string (as returned by
// Launch's GetSandbox / CreateSandbox responses) represents a fully booted,
// usable VM. Other states ("starting", "suspended", "stopped", "failed",
// "deleted", etc.) are treated as not-running.
func IsSandboxRunning(state string) bool {
	return strings.EqualFold(state, "running")
}

func defaultString(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

const (
	sandboxImageStable     = "cca"
	sandboxImagePrerelease = "cca-prerelease"
	sandboxImageRuntime    = "cca-runtime"
)

func validateRequiredEnvVars(envMap map[string]string, requiresGitToken bool, params *CreateSandboxParams) error {
	if params != nil && params.UseCcav3 {
		if key, ok := findCcav3SecretEnvKey(params.EnvironmentVariables); ok {
			return goerrors.Errorf("ccav3 bootstrap environment contains secret key: %s", key)
		}
		return validateRequiredCcav3StdinSecrets(params.StdinSecrets)
	}
	if envMap["GITHUB_TOKEN"] == "" {
		return goerrors.New("missing required environment variable: GITHUB_TOKEN")
	}
	if requiresGitToken && envMap["GITHUB_COPILOT_GIT_TOKEN"] == "" {
		return goerrors.New("missing required environment variable: GITHUB_COPILOT_GIT_TOKEN")
	}
	return nil
}

// DeleteSandbox tears down a sandbox VM.
func (s *Service) DeleteSandbox(ctx context.Context, sandboxID string, actorID uint64) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.DeleteSandbox")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sandboxID),
		kvp.Uint64("actor_id", actorID),
	)
	logger.Info("Deleting sandbox")

	backend, err := s.newBackend(actorID)
	if err != nil {
		return goerrors.Errorf("failed to create sandbox backend: %w", err)
	}
	return backend.deleteSandbox(ctx, sandboxID)
}

// StopSandbox stops a running sandbox VM without deleting it, so it can be resumed later.
func (s *Service) StopSandbox(ctx context.Context, sandboxID string, actorID uint64) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.StopSandbox")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sandboxID),
		kvp.Uint64("actor_id", actorID),
	)
	logger.Info("Stopping sandbox")

	backend, err := s.newBackend(actorID)
	if err != nil {
		return goerrors.Errorf("failed to create sandbox backend: %w", err)
	}
	return backend.stopSandbox(ctx, sandboxID)
}

// ExecCopilotCLI waits for the sandbox to be ready and starts a new Copilot
// CLI session in a detached tmux session. Used after ResumeSandbox to kick
// off a new turn on a resumed VM. If eventJSON is non-empty, writes the
// event file before starting the CLI. If envVars is non-empty, writes a shell
// environment file and sources it before launching ccav3. If stdinSecrets is
// non-empty, writes those secrets to a mode-600 JSON file and redirects it into
// ccav3 stdin so resumed sessions receive fresh tokens without inherited env.
func (s *Service) ExecCopilotCLI(ctx context.Context, sandboxID string, actorID uint64, repoNWO, problemStatement string, cliFlags []string, envVars map[string]string, eventJSON string, stdinSecrets map[string]string, useCcav3 bool) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.ExecCopilotCLI")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sandboxID),
		kvp.Uint64("actor_id", actorID),
	)
	metricTags := s.obsv.TelemetryTags(ctx)

	backend, err := s.newBackend(actorID)
	if err != nil {
		return goerrors.Errorf("failed to create sandbox backend: %w", err)
	}

	logger.Info("Waiting for sandbox to be ready")
	readyStart := time.Now()
	err = s.waitForReady(ctx, backend, sandboxID)
	if err != nil {
		return goerrors.Errorf("sandbox failed to become ready: %w", err)
	}
	s.obsv.DistributionMs(ctx, "sandbox.resume_ready_duration_ms", metricTags, time.Since(readyStart))

	sb, err := backend.getSandbox(ctx, sandboxID)
	if err != nil {
		return goerrors.Errorf("failed to get sandbox: %w", err)
	}

	environmentFilePath := ""
	if len(envVars) > 0 {
		if useCcav3 {
			if key, ok := findCcav3SecretEnvKey(envVars); ok {
				return goerrors.Errorf("ccav3 environment file contains secret key: %s", key)
			}
		}
		environmentFilePath = EnvironmentFilePath
	}
	if eventJSON != "" || len(envVars) > 0 {
		err = s.writeLaunchFiles(ctx, backend, sb, eventJSON, envVars)
		if err != nil {
			return goerrors.Errorf("failed to write launch files: %w", err)
		}
	}
	return s.startCopilotCLI(ctx, backend, sb, &CreateSandboxParams{
		RepositoryNWO:       repoNWO,
		ProblemStatement:    problemStatement,
		CLIFlags:            cliFlags,
		ActorID:             actorID,
		UseCcav3:            useCcav3,
		EnvironmentFilePath: environmentFilePath,
		StdinSecrets:        stdinSecrets,
	})
}

// ResumeSandbox resumes a previously paused sandbox VM.
func (s *Service) ResumeSandbox(ctx context.Context, sandboxID string, actorID uint64) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.ResumeSandbox")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sandboxID),
		kvp.Uint64("actor_id", actorID),
	)
	logger.Info("Resuming sandbox")

	backend, err := s.newBackend(actorID)
	if err != nil {
		return goerrors.Errorf("failed to create sandbox backend: %w", err)
	}
	return backend.resumeSandbox(ctx, sandboxID)
}

// ErrSandboxLabelsMissing indicates that a sandbox is missing the
// sweagentd.repository_id or sweagentd.agent_id labels we stamp at create
// time. Callers cannot mint a fresh token without these values, so resume
// must fail rather than silently relaunching with stale credentials.
var ErrSandboxLabelsMissing = goerrors.New("sandbox is missing required sweagentd labels")

// Info carries metadata read from a sandbox VM's labels.
type Info struct {
	RepositoryID int64
	AgentID      int64
}

// GetSandboxState fetches the sandbox by ID and returns its current
// platform state string (e.g. "running", "suspended"). Use with
// [IsSandboxRunning] to decide whether a resume request is a no-op
// without paying the cost of parsing labels — labels are unnecessary
// when the VM is already running and being left alone.
func (s *Service) GetSandboxState(ctx context.Context, sandboxID string, actorID uint64) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.GetSandboxState")
	defer span.End()

	backend, err := s.newBackend(actorID)
	if err != nil {
		return "", goerrors.Errorf("failed to create sandbox backend: %w", err)
	}
	sb, err := backend.getSandbox(ctx, sandboxID)
	if err != nil {
		return "", goerrors.Errorf("failed to get sandbox: %w", err)
	}
	return sb.State, nil
}

// GetSandboxInfo fetches the sandbox by ID and returns the repository_id
// and agent_id stamped on its labels by sandboxScopeLabels at create time.
// Returns ErrSandboxLabelsMissing when either label is absent or
// unparseable so callers can fail-fast on a sandbox that cannot be safely
// resumed.
func (s *Service) GetSandboxInfo(ctx context.Context, sandboxID string, actorID uint64) (*Info, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.GetSandboxInfo")
	defer span.End()

	backend, err := s.newBackend(actorID)
	if err != nil {
		return nil, goerrors.Errorf("failed to create sandbox backend: %w", err)
	}
	sb, err := backend.getSandbox(ctx, sandboxID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get sandbox: %w", err)
	}
	repoStr := sb.Labels[sandboxRepositoryIDLabel]
	agentStr := sb.Labels[sandboxAgentIDLabel]
	if repoStr == "" || agentStr == "" {
		return nil, goerrors.Errorf("%w (sandbox=%s)", ErrSandboxLabelsMissing, sandboxID)
	}
	repoID, err := strconv.ParseInt(repoStr, 10, 64)
	if err != nil {
		return nil, goerrors.Errorf("%w: invalid repository_id %q (sandbox=%s)", ErrSandboxLabelsMissing, repoStr, sandboxID)
	}
	agentID, err := strconv.ParseInt(agentStr, 10, 64)
	if err != nil {
		return nil, goerrors.Errorf("%w: invalid agent_id %q (sandbox=%s)", ErrSandboxLabelsMissing, agentStr, sandboxID)
	}
	return &Info{RepositoryID: repoID, AgentID: agentID}, nil
}

// ResumeCopilotCLI is the post-ResumeSandbox half of the CLI-sandbox resume
// flow. It waits for the resumed VM to become ready, kills any pre-existing
// tmux server (which holds the previous, possibly-expired tokens), and
// starts a fresh detached tmux session running `copilot --remote --continue`
// whose environment carries freshEnv.
//
// freshEnv is passed via ExecCommandRequest.Environment — the ADC-native
// per-exec env channel — rather than embedded in the command string. This
// mirrors how CLI sandbox creation hands credentials to the VM (platform
// env injection), keeps secret bytes out of command arguments, telemetry
// tags, and error messages, and never writes a file to disk. The fresh
// env is inherited through the wrapper `sh` → `tmux new-session` → copilot
// chain.
func (s *Service) ResumeCopilotCLI(ctx context.Context, sandboxID string, actorID uint64, repoNWO string, freshEnv map[string]string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.ResumeCopilotCLI")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sandboxID),
		kvp.Uint64("actor_id", actorID),
	)
	metricTags := s.obsv.TelemetryTags(ctx)

	err := validateCLIResumeEnv(freshEnv)
	if err != nil {
		return err
	}

	backend, err := s.newBackend(actorID)
	if err != nil {
		return goerrors.Errorf("failed to create sandbox backend: %w", err)
	}

	logger.Info("Waiting for resumed sandbox to be ready")
	readyStart := time.Now()
	err = s.waitForReady(ctx, backend, sandboxID)
	if err != nil {
		s.obsv.Increment(ctx, "sandbox.cli_resume_relaunch_error", metricTags.Merge(stats.Tags{"kind": "wait_ready"}))
		return goerrors.Errorf("resumed sandbox failed to become ready: %w", err)
	}
	s.obsv.DistributionMs(ctx, "sandbox.resume_ready_duration_ms", metricTags, time.Since(readyStart))

	sb, err := backend.getSandbox(ctx, sandboxID)
	if err != nil {
		return goerrors.Errorf("failed to get sandbox: %w", err)
	}

	workDir := RepositoryWorkDir(repoNWO)
	if repoNWO == "" {
		workDir = "/root"
	}
	wrapper := buildCLIResumeWrapperCommand(workDir, "copilot --remote --continue")

	launchCtx, cancel := context.WithTimeout(ctx, cliResumeLaunchTimeout)
	defer cancel()

	launchStart := time.Now()
	result, err := backend.executeCommand(launchCtx, sb, &sandboxsdk.ExecCommandRequest{
		Command:     "sh",
		Args:        []string{"-c", wrapper},
		Environment: freshEnv,
	})
	s.obsv.DistributionMs(ctx, "sandbox.cli_resume_launch_duration_ms", metricTags, time.Since(launchStart))

	if err != nil {
		s.obsv.Increment(ctx, "sandbox.cli_resume_relaunch_error", metricTags.Merge(stats.Tags{"kind": "transport"}))
		return goerrors.Errorf("CLI resume launch error in sandbox %s: %w", sb.ID, err)
	}
	if result != nil && result.ExitCode != 0 {
		s.obsv.Increment(ctx, "sandbox.cli_resume_relaunch_error", metricTags.Merge(stats.Tags{"kind": "nonzero_exit"}))
		return goerrors.Errorf("CLI resume launch exited %d in sandbox %s: %s: %w", result.ExitCode, sb.ID, result.Stderr, ErrCLIExitFailure)
	}

	logger.Info("Copilot CLI resumed with --continue")
	s.obsv.Increment(ctx, "sandbox.cli_resume_success", metricTags)
	return nil
}

func validateCLIResumeEnv(envVars map[string]string) error {
	if len(envVars) == 0 {
		return goerrors.New("ResumeCopilotCLI requires at least one env var")
	}
	for k := range envVars {
		if !isShellIdentifier(k) {
			return goerrors.Errorf("invalid env var name: %s", k)
		}
	}
	return nil
}

// buildCLIResumeWrapperCommand returns the wrapper command run via `sh -c`
// inside the sandbox during CLI resume.
//
// The wrapper:
//  1. Kills the entire tmux server, not just the `copilot` session. tmux
//     servers persist across `new-session` calls and inherit the
//     environment of the first process that started them; subsequent
//     `tmux new-session` invocations are forwarded to the existing server
//     rather than starting a fresh one, so they reuse that stale env
//     regardless of what the calling shell exports. `kill-session -t
//     copilot` would leave the server alive holding the previous tokens
//     and silently re-launch copilot with them. `kill-server` forces the
//     next `new-session` to spawn a brand-new server as a child of our
//     wrapper `sh`, inheriting the fresh tokens ADC injected via
//     ExecCommandRequest.Environment. The wider blast radius is safe
//     here: the CLI sandbox VM only ever runs the single `copilot`
//     session that create-time setup spawned.
//  2. Starts a detached `tmux new-session -d -s copilot` running the given
//     copilot invocation in workDir.
func buildCLIResumeWrapperCommand(workDir, copilotInvocation string) string {
	tmuxCmd := fmt.Sprintf("cd %s && exec %s", shellQuote(workDir), copilotInvocation)
	return fmt.Sprintf("tmux kill-server 2>/dev/null || true; tmux new-session -d -s copilot %s", shellQuote(tmuxCmd))
}

func (s *Service) sandboxSourceRef(ctx context.Context, params *CreateSandboxParams) *launchsandbox.CreateSandboxSourceRef {
	imageName := sandboxImageStable
	if params.UseCcav3 {
		imageName = sandboxImageRuntime
	} else if s.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentSandboxPrereleaseImage, int64(params.ActorID), int64(params.RepositoryID)) {
		imageName = sandboxImagePrerelease
	}
	return &launchsandbox.CreateSandboxSourceRef{
		Image: &launchsandbox.DiskImageRef{Name: imageName, IsPublic: true},
	}
}

func (s *Service) buildCreateSandboxOptions(ctx context.Context, params *CreateSandboxParams, envMap map[string]string) *createSandboxOptions {
	return &createSandboxOptions{
		SourceRef: s.sandboxSourceRef(ctx, params),
		Resources: &sandboxResources{
			CPU:    defaultString(params.CPU, defaultCPU),
			Memory: defaultString(params.Memory, defaultMemory),
		},
		Labels:               sandboxScopeLabels(params.RepositoryID, params.AgentID),
		EnvironmentVariables: envMap,
		EgressPolicy:         s.buildEgressPolicy(params),
		Lifecycle:            s.buildLifecyclePolicy(params),
		Repositories:         buildSandboxRepositoryConfiguration(params.RepositoryNWO),
		BillableOwnerID:      params.BillableOwnerID,
		BillableOwnerType:    params.BillableOwnerType,
	}
}

func buildSandboxRepositoryConfiguration(repoNWO string) map[string]*launchsandbox.Repositories {
	// TODO: Re-enable selecting the repository's agent secrets once we have
	// credential isolation, to prevent the agent from having direct access to
	// those secrets.
	// if repoNWO == "" {
	// 	return nil
	// }
	// return map[string]*launchsandbox.Repositories{
	// 	repoNWO: {
	// 		Secrets: map[string]*launchsandbox.Secrets{
	// 			"Agents": {},
	// 		},
	// 	},
	// }
	_ = repoNWO
	return nil
}

func sandboxScopeLabels(repositoryID uint64, agentID int64) map[string]string {
	return map[string]string{
		sandboxAgentIDLabel:      strconv.FormatInt(agentID, 10),
		sandboxRepositoryIDLabel: strconv.FormatUint(repositoryID, 10),
	}
}

func (s *Service) buildCopilotCommand(params *CreateSandboxParams) string {
	if params.UseCcav3 {
		return s.buildCcav3Command(params)
	}

	workDir := RepositoryWorkDir(params.RepositoryNWO)
	if params.RepositoryNWO == "" {
		workDir = "/root"
	}

	argParts := []string{"--remote"}
	argParts = append(argParts, params.CLIFlags...)
	if params.ProblemStatement != "" {
		argParts = append(argParts, "-i", shellQuote(params.ProblemStatement))
	}
	return fmt.Sprintf("cd %s && copilot %s", shellQuote(workDir), strings.Join(argParts, " "))
}

const (
	ccav3Dir = "/opt/copilot-runtime/copilot-developer-action-main"
	// ccav3StdinReadyMarker is emitted after the TTY has echo disabled so the
	// launcher can safely send stdin secrets without the TTY echoing them.
	ccav3StdinReadyMarker = "__SWEAGENTD_CCAV3_STDIN_READY__"
	// EventFilePath is where the COPILOT_AGENT_INPUTS event file is written
	// inside the sandbox VM. ccav3's requireInput() reads from this path.
	EventFilePath = "/tmp/copilot-event.json"
	// EnvironmentFilePath is sourced before launching ccav3 on resumed VMs so
	// the process sees freshly minted non-secret bootstrap env.
	EnvironmentFilePath = "/tmp/copilot-env.sh"
)

// Ccav3SecretEnvKeys are the secret-bearing env var names that must not remain
// inherited by the node runtime. They mirror the Actions stdin handoff, plus
// defensive cleanup for legacy git-token env names.
var Ccav3SecretEnvKeys = []string{
	"GITHUB_TOKEN",
	"GITHUB_COPILOT_GITHUB_TOKEN",
	"GITHUB_COPILOT_API_TOKEN",
	"GITHUB_COPILOT_GIT_TOKEN",
	"GITHUB_COPILOT_INTEGRATION_ID",
	"COPILOT_INTEGRATION_ID_OVERRIDE",
	"CAPI_HMAC_KEY_OVERRIDE",
	"COPILOT_JOB_NONCE",
	"GITHUB_VERIFICATION_TOKEN",
}

var ccav3RequiredStdinSecretKeys = []string{
	"GITHUB_COPILOT_API_TOKEN",
	"GITHUB_TOKEN",
}

// buildCcav3Command builds the shell command used to start ccav3 directly.
// The caller attaches stdin with executeCommandWithStdin; this command only
// sources non-secret bootstrap env, removes that temp file, unsets inherited
// secret names, then hands one stdin-delivered secret line to a detached node
// process without writing the secret payload to disk.
func (s *Service) buildCcav3Command(params *CreateSandboxParams) string {
	command := fmt.Sprintf("node %s/dist-cca-v3/index.js /var/log", ccav3Dir)
	var parts []string
	var cleanupPaths []string
	if params.EnvironmentFilePath != "" {
		cleanupPaths = append(cleanupPaths, shellQuote(params.EnvironmentFilePath))
	}
	if len(cleanupPaths) > 0 {
		parts = append(parts, fmt.Sprintf("trap %s EXIT", shellQuote("rm -f "+strings.Join(cleanupPaths, " "))))
	}
	if params.EnvironmentFilePath != "" {
		envFilePath := shellQuote(params.EnvironmentFilePath)
		parts = append(parts, fmt.Sprintf("set -a && . %s && set +a && rm -f %s", envFilePath, envFilePath))
	}
	parts = append(parts, buildUnsetSecretEnvKeysCommand())
	if len(cleanupPaths) > 0 {
		parts = append(parts, "trap - EXIT")
	}
	parts = append(parts, buildCcav3StdinPipeCommand(command))
	return strings.Join(parts, " && ")
}

func buildCcav3StdinPipeCommand(command string) string {
	detachedScript := shellQuote(fmt.Sprintf("exec %s < \"$1\"", command))
	// ADC TTY stdin delivers the newline-terminated secret payload, but does not
	// give node normal pipe EOF semantics. Read exactly one line in the wrapper,
	// then hand it to a detached node process through a private FIFO: the parent
	// blocks only until node opens and consumes the FIFO, then the exec stream can
	// return while ccav3 keeps running in the sandbox.
	//
	// The detached node's stdout/stderr are redirected to a per-launch log file
	// in /tmp so that startup failures (missing secrets, fatal env validation,
	// crashes before ccav3's own logger initializes) are diagnosable
	// post-mortem. Without this the detach swallows all output silently and
	// "Copilot CLI launched" can be reported while ccav3 actually exited.
	//
	// We also best-effort reap any leftover ccav3 node process from a prior
	// turn before relaunching. A stale instance could hold log/lock paths and
	// cause the new launch to silently exit on resume.
	//
	// `setsid` puts node in a brand-new session with no controlling TTY so it
	// is not a member of the wrapper's PTY session. ADC's executeCommandWithStdin
	// allocates a PTY (tty: true) for the wrapper; when the wrapper exits, ADC
	// tears down that session and any descendant processes still in it are
	// killed regardless of `nohup` (`nohup` only ignores SIGHUP). Empirically
	// this is what was killing ccav3 between turns on resumed sandboxes: the
	// wrapper completed faster than ccav3 could escape on its own and the
	// session teardown reaped node. `</dev/null` keeps fd 0 from pointing at
	// the closed FIFO writer after the parent's printf returns, which is
	// belt-and-suspenders against unexpected SIGPIPE.
	parts := []string{
		"ccav3_stdin_dir=$(mktemp -d /tmp/copilot-stdin.XXXXXX) || exit 1",
		`ccav3_stdin_fifo="$ccav3_stdin_dir/stdin"`,
		`mkfifo -m 600 "$ccav3_stdin_fifo" || exit 1`,
		`cleanup_ccav3_stdin() { if [ -t 0 ]; then stty echo 2>/dev/null || true; fi; rm -f "$ccav3_stdin_fifo"; rmdir "$ccav3_stdin_dir" 2>/dev/null || true; }`,
		"trap cleanup_ccav3_stdin EXIT",
		`for ccav3_stale_pid in $(ps -eo pid,args 2>/dev/null | awk '/dist-cca-v3\/index\.js/ && !/awk/ {print $1}'); do kill "$ccav3_stale_pid" 2>/dev/null || true; done`,
		`ccav3_launch_log="/tmp/cca-launch-$(date +%s)-$$.log"`,
		fmt.Sprintf("if [ -t 0 ]; then stty -echo 2>/dev/null && printf '%%s\\n' %s; fi", shellQuote(ccav3StdinReadyMarker)),
		"IFS= read -r ccav3_stdin_secrets || exit 1",
		"if [ -t 0 ]; then stty echo 2>/dev/null || true; fi",
		fmt.Sprintf(`nohup setsid sh -c %s sh "$ccav3_stdin_fifo" </dev/null >"$ccav3_launch_log" 2>&1 &`, detachedScript),
		`printf '%s' "$ccav3_stdin_secrets" > "$ccav3_stdin_fifo"`,
	}
	parts[len(parts)-2] = parts[len(parts)-2] + " " + parts[len(parts)-1]
	parts = parts[:len(parts)-1]
	return "{ " + strings.Join(parts, "; ") + "; }"
}

func buildUnsetSecretEnvKeysCommand() string {
	return "unset " + strings.Join(Ccav3SecretEnvKeys, " ")
}

func findCcav3SecretEnvKey(envVars map[string]string) (string, bool) {
	for _, key := range Ccav3SecretEnvKeys {
		if _, ok := envVars[key]; ok {
			return key, true
		}
	}
	return "", false
}

func validateRequiredCcav3StdinSecrets(secrets map[string]string) error {
	for _, key := range ccav3RequiredStdinSecretKeys {
		if secrets[key] == "" {
			return goerrors.Errorf("missing required stdin secret: %s", key)
		}
	}
	return nil
}
