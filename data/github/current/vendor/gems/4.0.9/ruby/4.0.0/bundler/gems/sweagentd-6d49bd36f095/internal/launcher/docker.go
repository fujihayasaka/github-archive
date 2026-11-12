package launcher

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/api/types/mount"
	docker "github.com/docker/docker/client"
	"github.com/docker/go-connections/nat"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/permissions"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/joho/godotenv"
)

// DockerLauncher is an implementation of AgentLauncher that uses Docker to run agents.
type DockerLauncher struct {
	obsv        observability.Exporters
	ffClient    featureflags.Client
	ghTwirp     githubtwirp.ClientInterface
	appProvider *agenticapp.Provider
	opts        DockerLauncherOpts
	client      *docker.Client
}

// Ensure that DockerLauncher implements AgentLauncher
var _ AgentLauncher = &DockerLauncher{}

// Token for allowing agent to use AI Platform proxy to access experimental models
var aipToken azcore.AccessToken = azcore.AccessToken{}

// WorkflowRunCompletedHandler is the interface for handling workflow run completion events.
// This allows the Docker launcher to trigger the same finalization flow as GitHub Actions workflows.
type WorkflowRunCompletedHandler interface {
	OnWorkflowRunCompleted(ctx context.Context, event WorkflowRunCompletedEvent) error
}

// WorkflowRunCompletedEvent represents a workflow run completion event.
// This is a minimal interface to avoid importing the events package.
type WorkflowRunCompletedEvent interface {
	GetActorID() int64
	GetRepositoryID() int64
	GetOwnerID() int64
	// GetWorkflowRunID returns the workflow run ID (used as computeID)
	GetWorkflowRunID() int64
	// GetWorkflowPath returns the workflow path
	GetWorkflowPath() string
	// GetConclusion returns the workflow conclusion (success, failure, etc.)
	GetConclusion() string
	// GetCompletedAt returns the completion timestamp
	GetCompletedAt() int64
}

// WorkflowRepository represents a GitHub repository for workflow events
type WorkflowRepository struct {
	ID      int64
	OwnerID int64
}

// WorkflowRun represents a GitHub Actions workflow run
type WorkflowRun struct {
	ID          int64
	Path        string
	UserID      int64
	Status      string
	Conclusion  string
	CompletedAt int64
}

// dockerWorkflowRunCompletedEvent is a local implementation of WorkflowRunCompletedEvent
type dockerWorkflowRunCompletedEvent struct {
	Repo        *WorkflowRepository
	WorkflowRun *WorkflowRun
	Timestamp   time.Time
}

func (e *dockerWorkflowRunCompletedEvent) GetActorID() int64 {
	return e.WorkflowRun.UserID
}

func (e *dockerWorkflowRunCompletedEvent) GetRepositoryID() int64 {
	return e.Repo.ID
}

func (e *dockerWorkflowRunCompletedEvent) GetOwnerID() int64 {
	return e.Repo.OwnerID
}

func (e *dockerWorkflowRunCompletedEvent) GetWorkflowRunID() int64 {
	return e.WorkflowRun.ID
}

func (e *dockerWorkflowRunCompletedEvent) GetWorkflowPath() string {
	return e.WorkflowRun.Path
}

func (e *dockerWorkflowRunCompletedEvent) GetConclusion() string {
	return e.WorkflowRun.Conclusion
}

func (e *dockerWorkflowRunCompletedEvent) GetCompletedAt() int64 {
	return e.WorkflowRun.CompletedAt
}

// DockerLauncherOpts contains configuration options for the DockerLauncher.
type DockerLauncherOpts struct {
	ExternalLauncherOpts

	AnthropicKeyOpts

	ContainerImage          string
	DockerAIPProxy          bool
	DockerUseHostNetworking bool
	DockerMapPort           int
	// EnginePath is the local filesystem path to an engine project directory.
	// When set, the engine's dist/ is mounted into the container and used as
	// the entry point instead of the built-in runtime.
	EnginePath string
	// EngineInferenceToken is a token for calling production inference APIs.
	// Only used in engine mode.
	EngineInferenceToken string
	// WorkflowCompletedHandler is called when the container finishes running, allowing
	// for session finalization through the same flow as GitHub Actions workflows
	WorkflowCompletedHandler WorkflowRunCompletedHandler
}

// NewDockerLauncher creates a new DockerLauncher with the given options.
func NewDockerLauncher(obsv observability.Exporters, ffClient featureflags.Client, ghTwirp githubtwirp.ClientInterface, appProvider *agenticapp.Provider, opts *DockerLauncherOpts) (*DockerLauncher, error) {
	client, err := docker.NewClientWithOpts(docker.FromEnv)
	if err != nil {
		return nil, err
	}
	return &DockerLauncher{
		obsv:        obsv,
		ffClient:    ffClient,
		ghTwirp:     ghTwirp,
		appProvider: appProvider,
		client:      client,
		opts:        *opts,
	}, nil
}

// SetWorkflowCompletedHandler sets the handler for workflow completion events.
// This allows the handler to be set after the launcher is created to avoid initialization order dependencies.
func (d *DockerLauncher) SetWorkflowCompletedHandler(handler WorkflowRunCompletedHandler) {
	d.opts.WorkflowCompletedHandler = handler
}

// LauncherType returns the type of the launcher.
func (d *DockerLauncher) LauncherType() Type {
	return TypeDocker
}

// LaunchAgent launches a new Docker container for the agent with the given options.
//
//nolint:maintidx // This function is complex due to the many configuration options needed for Docker containers.
func (d *DockerLauncher) LaunchAgent(ctx context.Context, opts *LaunchAgentOpts) (*LaunchResult, error) {
	privileged := false
	networkMode := container.NetworkMode("default")
	pidMode := container.PidMode("")
	cgroupNS := container.CgroupnsModeEmpty
	userNS := container.UsernsMode("")
	mounts := []mount.Mount{}

	computeID := generateComputeID()

	vars := GetVariables(ctx, d.ffClient, d.opts, opts, nil)

	var err error
	envVars := GetVariablesStrings(ctx, d.ffClient, d.opts, opts, &vars)
	if d.opts.AgentDebug {
		envVars = append(envVars, fmt.Sprintf("COPILOT_AGENT_DEBUG=%s", "true"))
	}

	envVars = append(envVars,
		// Set MCP debug logs path - this directory will be mounted to persist logs after container exits
		"COPILOT_AGENT_MCP_DEBUG_LOGS_PATH=/tmp/cca-mcp-debug-logs",
		// Set runtime tools log file for MCP server logging (used by runtime-tools.ts)
		"RUNTIME_TOOLS_LOG_FILE=/tmp/cca-mcp-debug-logs/runtime-tools.log",
		fmt.Sprintf("GITHUB_COPILOT_API_TOKEN=%s", d.opts.GitHubCopilotAPIToken),
		fmt.Sprintf("COPILOT_INTEGRATION_ID=%s", d.opts.CopilotIntegrationID),
		fmt.Sprintf("CAPI_HMAC_KEY=%s", d.opts.CAPIHMACKey))

	// Allow overriding the GitHub MCP URL for testing against a locally running GitHub MCP server w/o proxying through CAPI.
	if d.opts.GitHubMCPURLOverride != "" {
		envVars = append(envVars, fmt.Sprintf("GITHUB_MCP_URL_OVERRIDE=%s", d.opts.GitHubMCPURLOverride))
	}

	isCopilotCodingAgent := d.appProvider != nil && d.appProvider.IsCopilotCodingAgentApp(opts.Agent.AppID())
	flags, err := getFeatureFlags(ctx, d.ffClient, opts, isCopilotCodingAgent)
	if err != nil {
		// These errors should be transient if they occur
		return nil, RetriableLaunchError(err)
	}
	if len(flags) > 0 {
		envVars = append(envVars, fmt.Sprintf("COPILOT_FEATURE_FLAGS=%s", strings.Join(flags, ",")))
	}

	// Add traceparent for distributed tracing if enabled
	if traceParent := getCopilotTraceParent(ctx, d.ffClient, opts, d.opts.TraceParentPropagator); traceParent != "" {
		envVars = append(envVars, fmt.Sprintf("COPILOT_TRACE_PARENT=%s", traceParent))
	}

	// Inject a local user token that has access to the Azure AI Platform team's model proxy if enabled
	if d.opts.DockerAIPProxy {
		token, err := d.getAIPToken(ctx)
		if err != nil {
			return nil, NonRetriableLaunchError(goerrors.Errorf("failed to get AIP token: %w", err))
		}
		envVars = append(envVars, fmt.Sprintf("AIP_SWE_AGENT_TOKEN=%s", token))
	}

	if d.opts.MCPEnabled {
		mcpEnvVars, err := d.applyMCPSettings(ctx, opts)
		if err != nil {
			return nil, ClassifyLaunchError(err, "failed to apply MCP settings")
		}
		envVars = append(envVars, mcpEnvVars...)

		// Load additional MCP secrets from .env.mcp-dev if present (local development only).
		mcpDevEnvVars, err := loadMCPDevEnv()
		if err != nil {
			d.obsv.LoggerWithTelemetry(ctx).Warn(fmt.Sprintf("failed to load .env.mcp-dev: %v", err))
		}
		envVars = append(envVars, mcpDevEnvVars...)
	}

	// Need to check feature flags for firewall enablement at this point rather than in main since it can change at any time
	firewallEnabledByDefault := isFirewallEnabledByDefault(ctx, d.ffClient, &d.opts.AgentLauncherOpts)
	// Inject firewall settings if needed
	if firewallEnabledByDefault {
		// For Actions, we need to also check the related secret for the copilot environment variable to see if we should use
		// this default instead but Docker needs to work independently, so we'll just assume the default is correct for now
		firewallAllowList := d.opts.AgentFirewallRequiredAllowList

		// Replace repo-specific placeholders
		if opts.GitHubRepoOwner != "" && opts.GitHubRepoName != "" {
			firewallAllowList = replaceFirewallRepoPlaceholders(firewallAllowList, opts.GitHubRepoOwner, opts.GitHubRepoName)
		}

		envVars = append(envVars,
			fmt.Sprintf("COPILOT_AGENT_FIREWALL_ENABLED=%s", "true"),
			fmt.Sprintf("COPILOT_AGENT_FIREWALL_ALLOW_LIST=%s", firewallAllowList),
			fmt.Sprintf("COPILOT_AGENT_FIREWALL_RULE_SET_ALLOW_LIST=%s", d.opts.AgentFirewallRuleSetAllowListDefault))
		privileged = true
		networkMode = container.NetworkMode("host")
		pidMode = container.PidMode("host")
		cgroupNS = container.CgroupnsModeHost
		userNS = container.UsernsMode("")
		mounts = []mount.Mount{
			{
				Type:   mount.TypeBind,
				Source: "/sys/fs/cgroup",
				Target: "/sys/fs/cgroup",
			},
		}
	}

	err = d.pullImage(ctx)
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to pull docker image: %w", err))
	}

	// Set the network mode to host if DOCKER_USE_HOST_NETWORKING is true
	if d.opts.DockerUseHostNetworking {
		networkMode = container.NetworkMode("host")
	}

	// Determine entry point and env vars: engine mode overrides the built-in runtime
	var entryPoint string
	var eventFilePath string // host-side temp file to clean up after container exits
	if d.isEngineMode() {
		d.obsv.Logger.Info(fmt.Sprintf("Engine mode enabled, mounting engine from %s", d.opts.EnginePath))
		entryPoint = "/engine/dist/index.js"
		envVars = getEngineVariables(&d.opts, opts)
		mounts = append(mounts, mount.Mount{
			Type:     mount.TypeBind,
			Source:   d.opts.EnginePath,
			Target:   "/engine",
			ReadOnly: true,
		})
	} else {
		entryPoint = d.getRuntimeEntryPoint(ctx, opts)

		// cca-v3 reads required inputs (e.g. COPILOT_AGENT_JOB_ID) from the
		// GitHub Actions event file via readAgentInputs(), not from plain env
		// vars. Write a synthetic event file so the runtime can find them.
		eventFilePath, err = writeAgentInputsEventFile(vars)
		if err != nil {
			return nil, NonRetriableLaunchError(goerrors.Errorf("failed to write agent inputs event file: %w", err))
		}

		const containerEventPath = "/tmp/copilot-event.json"
		envVars = append(envVars,
			fmt.Sprintf("GITHUB_EVENT_PATH=%s", containerEventPath),
			"GITHUB_EVENT_NAME=dynamic",
		)
		mounts = append(mounts, mount.Mount{
			Type:     mount.TypeBind,
			Source:   eventFilePath,
			Target:   containerEventPath,
			ReadOnly: true,
		})
	}

	containerConfig := &container.Config{
		Image: d.opts.ContainerImage,
		Tty:   true,
		Env:   envVars,
	}

	// Note: The runtime image always has /opt/ebpf/launch.sh as ENTRYPOINT, which expects
	// the full command as a single string in $1, so we use the same format regardless
	containerConfig.Cmd = []string{fmt.Sprintf("node %s", entryPoint), "/var/log"}

	// cleanupEventFile removes the host-side temp event file (contains secrets).
	cleanupEventFile := func() {
		if eventFilePath != "" {
			_ = os.Remove(eventFilePath)
		}
	}

	// Create playwright logs directory if it doesn't exist
	playwrightLogsDir := "/tmp/playwright-logs"
	err = os.MkdirAll(playwrightLogsDir, 0o755) //nolint:gosec // Directory permissions are acceptable here
	if err != nil {
		cleanupEventFile()
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to create playwright logs directory: %w", err))
	}

	// Add playwright logs mount
	mounts = append(mounts, mount.Mount{
		Type:   mount.TypeBind,
		Source: "/tmp/playwright-logs",
		Target: "/tmp/playwright-logs",
	})

	// Create MCP debug logs directory if it doesn't exist
	mcpDebugLogsDir := "/tmp/cca-mcp-debug-logs"
	err = os.MkdirAll(mcpDebugLogsDir, 0o755) //nolint:gosec // Directory permissions are acceptable here
	if err != nil {
		cleanupEventFile()
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to create MCP debug logs directory: %w", err))
	}

	// Add MCP debug logs mount so logs persist after container exits
	mounts = append(mounts, mount.Mount{
		Type:   mount.TypeBind,
		Source: "/tmp/cca-mcp-debug-logs",
		Target: "/tmp/cca-mcp-debug-logs",
	})

	// Mount local runtime dist folders for rapid iteration without rebuilding Docker image
	// Set DOCKER_DEV_MOUNT_RUNTIME to the base runtime folder (e.g., /workspaces/sweagentd/runtime)
	// This only mounts folders that exist locally (ones that have been built with `npm run build:codex` or similar)
	// Missing folders use the Docker image's bundled version
	if devRuntimePath := os.Getenv("DOCKER_DEV_MOUNT_RUNTIME"); devRuntimePath != "" {
		devMounts := []struct {
			source string
			target string
		}{
			{"/dist", "/usr/src/app/dist"},
			{"/dist-cca", "/usr/src/app/dist-cca"},
			{"/dist-cca-v3", "/usr/src/app/dist-cca-v3"},
			{"/dist-claude", "/usr/src/app/dist-claude"},
			{"/dist-codex", "/usr/src/app/dist-codex"},
			{"/dist-mcp-client", "/usr/src/app/mcp/dist"},
		}
		for _, m := range devMounts {
			sourcePath := devRuntimePath + m.source
			_, statErr := os.Stat(sourcePath)
			if statErr == nil {
				mounts = append(mounts, mount.Mount{
					Type:   mount.TypeBind,
					Source: sourcePath,
					Target: m.target,
				})
			}
		}
	}

	hostConfig := &container.HostConfig{
		NetworkMode:  networkMode,
		Privileged:   privileged,
		PidMode:      pidMode,
		CgroupnsMode: cgroupNS,
		UsernsMode:   userNS,
		Mounts:       mounts,
	}

	if d.opts.DockerMapPort > 0 {
		port := nat.Port(fmt.Sprintf("%d/tcp", d.opts.DockerMapPort))
		containerConfig.ExposedPorts = nat.PortSet{
			port: struct{}{},
		}
		hostConfig.PortBindings = nat.PortMap{
			port: []nat.PortBinding{
				{
					HostIP:   "0.0.0.0",
					HostPort: fmt.Sprintf("%d", d.opts.DockerMapPort),
				},
			},
		}
	}

	c, err := d.client.ContainerCreate(ctx, containerConfig, hostConfig, nil, nil, computeID)
	if err != nil {
		cleanupEventFile()
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to create docker container: %w", err))
	}

	err = d.client.ContainerStart(ctx, c.ID, container.StartOptions{})
	if err != nil {
		cleanupEventFile()
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to start docker container: %w", err))
	}

	// Copy container logs into a file in runtime-logs folder and wait for container completion in a non-blocking manner
	go func() {
		defer cleanupEventFile()
		bgCtx := context.WithoutCancel(ctx)

		// Create runtime-logs directory if it doesn't exist
		logDir := "runtime-logs"
		err = os.MkdirAll(logDir, 0o755) //nolint:gosec // Directory permissions are acceptable here
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Error creating runtime-logs directory: %v\n", err)
			return
		}

		// Create log file for this specific container, prefixed with JobID
		logFileName := fmt.Sprintf("%s-%s.log", opts.JobID, computeID)
		logFilePath := filepath.Join(logDir, logFileName)
		logFile, err := os.Create(logFilePath)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Error creating log file %s: %v\n", logFilePath, err)
			return
		}
		defer logFile.Close()

		d.obsv.Logger.Info(fmt.Sprintf("Container logs for %s will be written to: %s", computeID, logFilePath))

		r, err := d.client.ContainerLogs(bgCtx, c.ID, container.LogsOptions{Follow: true, ShowStdout: true, ShowStderr: true})
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Error getting container logs: %v\n", err)
			return
		}
		defer r.Close()

		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			_, err := fmt.Fprintln(logFile, scanner.Text())
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "Error writing to log file: %v\n", err)
				return
			}
		}
		err = scanner.Err()
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "Error reading container logs: %v\n", err)
		}

		// Wait for the container to finish
		d.obsv.Logger.Info(fmt.Sprintf("Waiting for container %s to finish", computeID))
		statusCh, errCh := d.client.ContainerWait(bgCtx, c.ID, container.WaitConditionNotRunning)
		select {
		case err := <-errCh:
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "Error waiting for container: %v\n", err)
				return
			}
		case status := <-statusCh:
			d.obsv.Logger.Info(fmt.Sprintf("Container %s finished with exit code: %d", computeID, status.StatusCode))

			// Call the completion handler if one is set
			if d.opts.WorkflowCompletedHandler != nil {
				// Map container exit code to workflow conclusion
				conclusion := "success"
				if status.StatusCode != 0 {
					conclusion = "failure"
				}

				// Parse computeID back to int64 for the workflow run ID
				runID, err := strconv.ParseInt(computeID, 10, 64)
				if err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "Error parsing computeID: %v\n", err)
					return
				}

				// Construct a synthetic WorkflowRunCompletedEvent
				event := &dockerWorkflowRunCompletedEvent{
					Repo: &WorkflowRepository{
						ID:      opts.GitHubRepoID,
						OwnerID: opts.GitHubRepoOwnerID,
					},
					WorkflowRun: &WorkflowRun{
						ID:          runID,
						Path:        "dynamic/copilot-swe-agent/docker",
						UserID:      opts.ActorID,
						Status:      "completed",
						Conclusion:  conclusion,
						CompletedAt: time.Now().Unix(),
					},
					Timestamp: time.Now(),
				}

				err = d.opts.WorkflowCompletedHandler.OnWorkflowRunCompleted(bgCtx, event)
				if err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "Error in workflow completion handler: %v\n", err)
				}
			}
		}
	}()

	// Docker launcher doesn't support custom setup steps
	return &LaunchResult{
		ComputeID:        computeID,
		CustomSetupSteps: false,
		RunsOn:           "",
	}, nil
}

// TerminateAgent stops and removes the Docker container with the given compute ID.
func (d *DockerLauncher) TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error {
	return d.client.ContainerKill(ctx, opts.ComputeID, "SIGKILL")
}

func (d *DockerLauncher) getRuntimeEntryPoint(ctx context.Context, opts *LaunchAgentOpts) string {
	// Copilot and third-party apps run on the Copilot runtime path. Partner
	// agents define their own entry point via SetupCompute.
	if !usesCopilotRuntimeVariants(opts) {
		var probe entryPointProbe
		opts.Agent.SetupCompute(&probe)
		if probe.entryPoint != "" {
			return probe.entryPoint
		}
		return copilotRuntimeEntrypoint
	}

	return selectRuntime(ctx, d.ffClient, opts).entryPoint
}

// isEngineMode returns true when an external engine path is configured.
func (d *DockerLauncher) isEngineMode() bool {
	return d.opts.EnginePath != ""
}

// applyMCPSettings fetches MCP configuration from dotcom, resolves permissions,
// and returns environment variables to inject into the container.
func (d *DockerLauncher) applyMCPSettings(ctx context.Context, opts *LaunchAgentOpts) ([]string, error) {
	const sweagentdMCPDisableFlag = "sweagentd_mcp_disable"

	if d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, sweagentdMCPDisableFlag, opts) {
		return nil, nil
	}

	if d.ghTwirp == nil {
		d.obsv.LoggerWithTelemetry(ctx).Warn("ghTwirp client not available, skipping MCP configuration from dotcom")
		return nil, nil
	}

	params := mcp.ConfigureParams{
		CustomAgent:  opts.CustomAgent,
		GHTwirp:      d.ghTwirp,
		RepositoryID: opts.GitHubRepoID,
		UserID:       opts.ActorID,
		FFClient:     d.ffClient,
	}

	resp, err := mcp.Configure(ctx, params)
	if err != nil {
		return nil, goerrors.Errorf("failed to configure MCP: %w", err)
	}

	var envVars []string

	if resp.Encoded != "" {
		envVars = append(envVars, fmt.Sprintf("%s=%s", "GITHUB_COPILOT_MCP_JSON_FROM_INPUT", resp.Encoded))
	}

	envVars = append(envVars, fmt.Sprintf("%s=%s", mcp.InteractionIDEnvVar, opts.SessionID))

	if resp.Enabled {
		envVars = append(envVars, "GITHUB_COPILOT_3P_MCP_ENABLED=true")
	}

	// If MCP is not enabled, do not mint a token or resolve permissions.
	if !resp.Enabled {
		return envVars, nil
	}

	// Resolve permissions: agent-level first, then repo-level (if FF enabled)
	agentPerms := permissions.Unset
	if p, ok := opts.CustomAgent.(permissions.Provider); ok {
		agentPerms = p.Permissions()
	}

	repoPerms := permissions.Unset
	if d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRepoConfigCustomPermissions, opts) {
		repoPerms = resp.Permissions
	}

	// When neither the agent nor the repo specify permissions and the
	// `copilot_swe_agent_mcp_permission_gate` FF is enabled, expand the
	// default token to read-write. The runtime's PermissionGate gates each
	// non-readOnly MCP tool call behind interactive user approval, so the
	// broadened token cannot be used for unattended writes.
	//
	// Only the Copilot coding agent has the PermissionGate wired in; for
	// third-party agents (Claude, Codex, custom) the expanded write token
	// would be ungated, so we keep them on the read-only default permissions
	// until the feature parity is gained for those runtimes.
	isCopilotCodingAgent := d.appProvider != nil && d.appProvider.IsCopilotCodingAgentApp(opts.Agent.AppID())
	useExpandedDefaults := agentPerms.IsUnset() && repoPerms.IsUnset() && isCopilotCodingAgent &&
		d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentMCPPermissionGate, opts)

	perms := permissions.ResolvePermissions(agentPerms, repoPerms)
	if useExpandedDefaults {
		perms = permissions.MCPWriteDefault
	}
	if opts.IsTriggered && d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCustomAgentTriggers, opts) {
		perms = permissions.RestrictTriggeredMCPPermissions(perms)
	}

	ghp, err := perms.ToDotCom()
	if err != nil {
		return nil, goerrors.Errorf("failed to convert resolved permissions: %w", err)
	}

	// Mint a scoped GitHub token with the resolved permissions
	mintResp, err := d.ghTwirp.SweagentdAPI().MintUserToServerTokenForRepo(ctx, &sweagentdTwirp.MintUserToServerTokenForRepoRequest{
		UserId:       uint64(opts.ActorID),
		RepositoryId: uint64(opts.GitHubRepoID),
		AgentId:      opts.Agent.AppID(),
		Permissions:  ghp,
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to mint user to server token for repo: %w", err)
	}
	token := mintResp.GetToken()
	if d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentShellTokenPermissions, opts) {
		envVars = append(envVars, fmt.Sprintf("GITHUB_COPILOT_GITHUB_TOKEN=%s", token))
	}
	envVars = append(envVars, fmt.Sprintf("GITHUB_PERSONAL_ACCESS_TOKEN=%s", token))

	return envVars, nil
}

const mcpDevEnvFile = ".env.mcp-dev"

// loadMCPDevEnv reads key=value pairs from .env.mcp-dev (if it exists) and
// returns them as "KEY=VALUE" strings suitable for container env injection.
// The file is silently skipped when absent.
func loadMCPDevEnv() ([]string, error) {
	envMap, err := godotenv.Read(mcpDevEnvFile)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, goerrors.Errorf("reading %s: %w", mcpDevEnvFile, err)
	}

	envVars := make([]string, 0, len(envMap))
	for k, v := range envMap {
		if strings.HasPrefix(k, "COPILOT_MCP_") {
			envVars = append(envVars, fmt.Sprintf("%s=%s", k, v))
		}
	}
	return envVars, nil
}

func (d *DockerLauncher) getAIPToken(ctx context.Context) (string, error) {
	// Azure tokens last an hour, so we'll refresh them every 30 minutes to give the agent a 30 min buffer
	if aipToken.Token != "" && aipToken.ExpiresOn.After(time.Now().Add(30*time.Minute)) {
		return aipToken.Token, nil
	}
	cred, err := azidentity.NewAzureCLICredential(nil)
	if err != nil {
		return "", err
	}
	aipToken, err = cred.GetToken(ctx, policy.TokenRequestOptions{
		Scopes: []string{"https://ml.azure.com/.default"},
	})
	if err != nil {
		return "", err
	}
	return aipToken.Token, nil
}

func (d *DockerLauncher) pullImage(ctx context.Context) error {
	filters := filters.NewArgs()
	filters.Add("reference", d.opts.ContainerImage)

	images, err := d.client.ImageList(ctx, image.ListOptions{Filters: filters})
	if err != nil {
		return err
	}

	if len(images) == 0 {
		d.obsv.Logger.Info(fmt.Sprintf("%s not found locally", d.opts.ContainerImage))
		registry, err := d.extractRegistryFromImage(d.opts.ContainerImage)
		if err != nil {
			return err
		}
		d.obsv.Logger.Info(fmt.Sprintf("Extracting credentials for %s", registry))
		username, password, err := getUserPassFromAuthConfig(registry)
		if err != nil {
			return err
		}

		registryAuth := base64.StdEncoding.EncodeToString(fmt.Appendf(nil, `{ "username": %q, "password": %q }`, username, password))
		d.obsv.Logger.Info("Pulling the image...")
		reader, err := d.client.ImagePull(ctx, d.opts.ContainerImage, image.PullOptions{RegistryAuth: registryAuth})
		if err != nil {
			return err
		}
		defer reader.Close()
		_, _ = io.Copy(io.Discard, reader)
	}
	return nil
}

func (d *DockerLauncher) extractRegistryFromImage(imageName string) (string, error) {
	parts := strings.Split(d.opts.ContainerImage, "/")
	if len(parts) < 2 {
		return "", goerrors.Errorf("invalid image name: %s", imageName)
	}
	return parts[0], nil
}

func getUserPassFromAuthConfig(registryName string) (username, password string, err error) {
	configFilePath := filepath.Join(os.Getenv("HOME"), ".docker", "config.json")
	configFile, err := os.ReadFile(configFilePath)
	if err != nil {
		return "", "", err
	}

	var config map[string]any
	err = json.Unmarshal(configFile, &config)
	if err != nil {
		return "", "", err
	}

	auths, ok := config["auths"].(map[string]any)
	if !ok {
		return "", "", goerrors.New("invalid Docker config file format")
	}

	auth, ok := auths[registryName].(map[string]any)
	if !ok {
		return "", "", goerrors.Errorf("no auth config found for registry: %s", registryName)
	}

	authToken, ok := auth["auth"].(string)
	if !ok {
		return "", "", goerrors.Errorf("no auth token found for registry: %s", registryName)
	}

	decodedToken, err := base64.StdEncoding.DecodeString(authToken)
	if err != nil {
		return "", "", err
	}

	parts := strings.SplitN(string(decodedToken), ":", 2)
	if len(parts) != 2 {
		return "", "", goerrors.Errorf("invalid auth token format for registry: %s", registryName)
	}

	return parts[0], parts[1], nil
}

func generateComputeID() string {
	return strconv.FormatInt(time.Now().UnixNano(), 10)
}

// writeAgentInputsEventFile creates a temporary file containing a synthetic GitHub Actions event payload with the COPILOT_AGENT_INPUTS JSON blob.
// This is needed because cca-v3's readAgentInputs() reads required inputs (e.g. COPILOT_AGENT_JOB_ID) from the event file at GITHUB_EVENT_PATH,
// not from plain environment variables. This is also generally closer to what the Actions workflow actually does, so there's advantages in having it here.
func writeAgentInputsEventFile(vars Variables) (string, error) {
	// Convert to a simple map structure that mirrors events.json
	inputs := make(map[string]string, len(vars))
	for k, v := range vars {
		inputs[k] = v.Value
	}
	inputsJSON, err := json.Marshal(inputs)
	if err != nil {
		return "", goerrors.Errorf("failed to marshal agent inputs: %w", err)
	}
	event := map[string]any{
		"inputs": map[string]string{
			"COPILOT_AGENT_INPUTS": string(inputsJSON),
		},
	}

	// Save to file
	eventJSON, err := json.Marshal(event)
	if err != nil {
		return "", goerrors.Errorf("failed to marshal event file: %w", err)
	}
	f, err := os.CreateTemp("", "copilot-event-*.json")
	if err != nil {
		return "", goerrors.Errorf("failed to create temp event file: %w", err)
	}
	_, err = f.Write(eventJSON)
	if err != nil {
		_ = f.Close()
		_ = os.Remove(f.Name())
		return "", goerrors.Errorf("failed to write event file: %w", err)
	}
	err = f.Close()
	if err != nil {
		_ = os.Remove(f.Name())
		return "", goerrors.Errorf("failed to close event file: %w", err)
	}

	// Lock it down
	err = os.Chmod(f.Name(), 0o600)
	if err != nil {
		_ = os.Remove(f.Name())
		return "", goerrors.Errorf("failed to set event file permissions: %w", err)
	}

	return f.Name(), nil
}
