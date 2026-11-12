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
	"github.com/github/sweagentd/internal/observability"
)

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

type DockerLauncherOpts struct {
	ExternalLauncherOpts
	AnthropicKeyOpts
	ContainerImage          string
	DockerAIPProxy          bool
	DockerUseHostNetworking bool
	DockerMapPort           int
}

func NewDockerLauncher(obsv observability.Exporters, ffClient featureflags.Client, opts DockerLauncherOpts) (*DockerLauncher, error) {
	client, err := docker.NewClientWithOpts(docker.FromEnv)
	if err != nil {
		return nil, err
	}
	return &DockerLauncher{
		obsv:     obsv,
		ffClient: ffClient,
		client:   client,
		opts:     opts,
	}, nil
}

func (d *DockerLauncher) LauncherType() LauncherType {
	return LauncherTypeDocker
}

func (d *DockerLauncher) LaunchAgent(ctx context.Context, opts LaunchAgentOpts) (string, error) {
	privileged := false
	networkMode := container.NetworkMode("default")
	pidMode := container.PidMode("")
	cgroupNS := container.CgroupnsModeEmpty
	userNS := container.UsernsMode("")
	mounts := []mount.Mount{}

	computeID := generateComputeID()

	gzip := d.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentGZipProblemStatement, &opts)
	envVars := GetVariablesStrings(d.opts, opts, nil, gzip)
	if d.opts.AgentDebug {
		envVars = append(envVars, fmt.Sprintf("COPILOT_AGENT_DEBUG=%s", "true"))
	}
	// Inject a local user token that has access to the Azure AI Platform team's model proxy if enabled
	if d.opts.DockerAIPProxy {
		token, err := d.getAIPToken(ctx)
		if err != nil {
			return "", err
		}
		envVars = append(envVars, fmt.Sprintf("AIP_SWE_AGENT_TOKEN=%s", token))
	}

	if d.opts.MCPEnabled {
		d.obsv.Logger.Info("MCP is enabled, make sure you built the container with an mcp-config.json file present")
	}

	// Need to check feature flags for firewall enablement at this point rather than in main since it can change at any time
	firewallEnabledByDefault := isFirewallEnabledByDefault(ctx, d.ffClient, d.opts.AgentLauncherOpts)
	// Inject firewall settings if needed
	if firewallEnabledByDefault {
		// For Actions, we need to also check the related secret for the copilot environment variable to see if we should use
		// this default instead but Docker needs to work independently, so we'll just assume the default is correct for now
		envVars = append(envVars, fmt.Sprintf("COPILOT_AGENT_FIREWALL_ENABLED=%s", "true"))
		envVars = append(envVars, fmt.Sprintf("COPILOT_AGENT_FIREWALL_ALLOW_LIST=%s", d.opts.AgentFirewallRequiredAllowList))
		envVars = append(envVars, fmt.Sprintf("COPILOT_AGENT_FIREWALL_RULE_SET_ALLOW_LIST=%s", d.opts.AgentFirewallRuleSetAllowListDefault))
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

	err := d.pullImage(ctx)
	if err != nil {
		return "", err
	}

	// Set the network mode to host if DOCKER_USE_HOST_NETWORKING is true
	if d.opts.DockerUseHostNetworking {
		networkMode = container.NetworkMode("host")
	}

	containerConfig := &container.Config{
		Image: d.opts.ContainerImage,
		Tty:   true,
		Env:   envVars,
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
		return "", err
	}

	err = d.client.ContainerStart(ctx, c.ID, container.StartOptions{})
	if err != nil {
		return "", err
	}

	// Copy container logs into stdout in a non-blocking manner
	go func() {
		ctx = context.WithoutCancel(ctx)
		r, err := d.client.ContainerLogs(ctx, c.ID, container.LogsOptions{Follow: true, ShowStdout: true, ShowStderr: true})
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error getting container logs: %v\n", err)
			return
		}
		defer r.Close()

		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			fmt.Fprintf(os.Stdout, "\t(runtime): %s\n", scanner.Text())
		}
		if err := scanner.Err(); err != nil {
			fmt.Fprintf(os.Stderr, "Error reading container logs: %v\n", err)
		}
	}()

	return c.ID, nil
}

func (d *DockerLauncher) TerminateAgent(ctx context.Context, opts TerminateAgentOpts) error {
	return d.client.ContainerKill(ctx, opts.ComputeID, "SIGKILL")
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

		registryAuth := base64.StdEncoding.EncodeToString([]byte(fmt.Sprintf("{ \"username\": \"%s\", \"password\": \"%s\" }", username, password)))
		d.obsv.Logger.Info("Pulling the image...")
		reader, err := d.client.ImagePull(ctx, d.opts.ContainerImage, image.PullOptions{RegistryAuth: registryAuth})
		if err != nil {
			return err
		}
		defer reader.Close()
		io.Copy(io.Discard, reader)
	}
	return nil
}

func (d *DockerLauncher) extractRegistryFromImage(imageName string) (string, error) {
	parts := strings.Split(d.opts.ContainerImage, "/")
	if len(parts) < 2 {
		return "", fmt.Errorf("invalid image name: %s", imageName)
	}
	return parts[0], nil
}

func getUserPassFromAuthConfig(registryName string) (string, string, error) {
	configFilePath := filepath.Join(os.Getenv("HOME"), ".docker", "config.json")
	configFile, err := os.ReadFile(configFilePath)
	if err != nil {
		return "", "", err
	}

	var config map[string]interface{}
	if err := json.Unmarshal(configFile, &config); err != nil {
		return "", "", err
	}

	auths, ok := config["auths"].(map[string]interface{})
	if !ok {
		return "", "", fmt.Errorf("invalid Docker config file format")
	}

	auth, ok := auths[registryName].(map[string]interface{})
	if !ok {
		return "", "", fmt.Errorf("no auth config found for registry: %s", registryName)
	}

	authToken, ok := auth["auth"].(string)
	if !ok {
		return "", "", fmt.Errorf("no auth token found for registry: %s", registryName)
	}

	decodedToken, err := base64.StdEncoding.DecodeString(authToken)
	if err != nil {
		return "", "", err
	}

	parts := strings.SplitN(string(decodedToken), ":", 2)
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid auth token format for registry: %s", registryName)
	}

	return parts[0], parts[1], nil
}
