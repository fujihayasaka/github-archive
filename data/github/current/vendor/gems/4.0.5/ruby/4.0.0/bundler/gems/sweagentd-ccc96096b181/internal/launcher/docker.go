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
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// DockerLauncher is an implementation of AgentLauncher that uses Docker to run agents.
type DockerLauncher struct {
	obsv     observability.Exporters
	ffClient featureflags.Client
	opts     DockerLauncherOpts
	client   *docker.Client
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
	// WorkflowCompletedHandler is called when the container finishes running, allowing
	// for session finalization through the same flow as GitHub Actions workflows
	WorkflowCompletedHandler WorkflowRunCompletedHandler
}

// NewDockerLauncher creates a new DockerLauncher with the given options.
func NewDockerLauncher(obsv observability.Exporters, ffClient featureflags.Client, opts *DockerLauncherOpts) (*DockerLauncher, error) {
	client, err := docker.NewClientWithOpts(docker.FromEnv)
	if err != nil {
		return nil, err
	}
	return &DockerLauncher{
		obsv:     obsv,
		ffClient: ffClient,
		client:   client,
		opts:     *opts,
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

	gzip := d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentGZipProblemStatement, opts)
	vars := GetVariables(ctx, d.ffClient, d.opts, opts, nil, gzip)

	var err error
	envVars := GetVariablesStrings(ctx, d.ffClient, d.opts, opts, &vars, gzip)
	if d.opts.AgentDebug {
		envVars = append(envVars, fmt.Sprintf("COPILOT_AGENT_DEBUG=%s", "true"))
	}

	envVars = append(envVars,
		fmt.Sprintf("GITHUB_COPILOT_API_TOKEN=%s", d.opts.GitHubCopilotAPIToken),
		fmt.Sprintf("COPILOT_INTEGRATION_ID=%s", d.opts.CopilotIntegrationID),
		fmt.Sprintf("CAPI_HMAC_KEY=%s", d.opts.CAPIHMACKey))

	featureFlags := getFeatureFlags(ctx, d.ffClient, opts)
	if len(featureFlags) > 0 {
		envVars = append(envVars, fmt.Sprintf("COPILOT_FEATURE_FLAGS=%s", strings.Join(featureFlags, ",")))
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
		d.obsv.Logger.Info("MCP is enabled, make sure you built the container with an mcp-config.json file present")
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

	// Determine which runtime entry point to use based on feature flags
	entryPoint := d.getRuntimeEntryPoint(ctx, opts)

	containerConfig := &container.Config{
		Image: d.opts.ContainerImage,
		Tty:   true,
		Env:   envVars,
	}

	// Note: The runtime image always has /opt/ebpf/launch.sh as ENTRYPOINT, which expects
	// the full command as a single string in $1, so we use the same format regardless
	containerConfig.Cmd = []string{fmt.Sprintf("node %s", entryPoint), "/var/log"}

	// Create playwright logs directory if it doesn't exist
	playwrightLogsDir := "/tmp/playwright-logs"
	err = os.MkdirAll(playwrightLogsDir, 0o755) //nolint:gosec // Directory permissions are acceptable here
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to create playwright logs directory: %w", err))
	}

	// Add playwright logs mount
	mounts = append(mounts, mount.Mount{
		Type:   mount.TypeBind,
		Source: "/tmp/playwright-logs",
		Target: "/tmp/playwright-logs",
	})

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
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to create docker container: %w", err))
	}

	err = d.client.ContainerStart(ctx, c.ID, container.StartOptions{})
	if err != nil {
		return nil, NonRetriableLaunchError(goerrors.Errorf("failed to start docker container: %w", err))
	}

	// Copy container logs into a file in runtime-logs folder and wait for container completion in a non-blocking manner
	go func() {
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
		statusCh, errCh := d.client.ContainerWait(ctx, c.ID, container.WaitConditionNotRunning)
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

				err = d.opts.WorkflowCompletedHandler.OnWorkflowRunCompleted(ctx, event)
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
	if d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2, opts) {
		return "dist-cca/index.js"
	}

	if d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointClaude, opts) {
		return "dist-claude/index.js"
	}

	if d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCodex, opts) {
		return "dist-codex/index.js"
	}

	return "dist/index.js"
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
