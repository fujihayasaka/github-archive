package sandbox

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/image"
	docker "github.com/docker/docker/client"
	"github.com/docker/docker/pkg/stdcopy"
	sandboxsdk "github.com/github/sandbox/go/sandbox"
	"github.com/github/sweagentd/internal/goerrors"
)

// dockerSandboxImage is the publicly-published CCA base image.
const dockerSandboxImage = "ghcr.io/github/sandbox/copilot-cca:latest"

// dockerSandboxClient implements sandboxBackend using a local Docker daemon.
// It creates containers that behave like cloud sandbox VMs, allowing the
// sandbox service to run entirely locally for development and testing.
type dockerSandboxClient struct {
	docker *docker.Client
	image  string
}

// newDockerSandboxClient creates a sandbox client backed by the local Docker daemon.
func newDockerSandboxClient() (*dockerSandboxClient, error) {
	cli, err := docker.NewClientWithOpts(docker.FromEnv)
	if err != nil {
		return nil, goerrors.Errorf("failed to create Docker client: %w", err)
	}
	return &dockerSandboxClient{
		docker: cli,
		image:  dockerSandboxImage,
	}, nil
}

func (c *dockerSandboxClient) createSandbox(ctx context.Context, opts *createSandboxOptions) (*sandboxInstance, error) {
	// Pull the image (no-op if already cached).
	pullResp, err := c.docker.ImagePull(ctx, c.image, image.PullOptions{})
	if err != nil {
		return nil, goerrors.Errorf("failed to pull sandbox image %s: %w", c.image, err)
	}
	defer pullResp.Close()
	_, _ = io.Copy(io.Discard, pullResp)

	containerCfg := &container.Config{
		Image:  c.image,
		Tty:    true,
		Cmd:    []string{"sleep", "infinity"},
		Env:    mapToEnvSlice(opts.EnvironmentVariables),
		Labels: opts.Labels,
	}

	hostCfg := &container.HostConfig{
		NetworkMode: container.NetworkMode("host"),
	}

	containerID := fmt.Sprintf("sandbox-%d", time.Now().UnixNano())
	resp, err := c.docker.ContainerCreate(ctx, containerCfg, hostCfg, nil, nil, containerID)
	if err != nil {
		return nil, goerrors.Errorf("failed to create container: %w", err)
	}

	err = c.docker.ContainerStart(ctx, resp.ID, container.StartOptions{})
	if err != nil {
		return nil, goerrors.Errorf("failed to start container: %w", err)
	}

	return &sandboxInstance{
		ID:     resp.ID,
		State:  "running",
		Labels: opts.Labels,
	}, nil
}

func (c *dockerSandboxClient) getSandbox(ctx context.Context, id string) (*sandboxInstance, error) {
	info, err := c.docker.ContainerInspect(ctx, id)
	if err != nil {
		return nil, goerrors.Errorf("failed to inspect container %s: %w", id, err)
	}

	state := "running"
	if !info.State.Running {
		state = "stopped"
	}

	return &sandboxInstance{
		ID:     id,
		State:  state,
		Labels: info.Config.Labels,
	}, nil
}

func (c *dockerSandboxClient) deleteSandbox(ctx context.Context, id string) error {
	timeout := 5
	err := c.docker.ContainerStop(ctx, id, container.StopOptions{Timeout: &timeout})
	if err != nil {
		if !docker.IsErrNotFound(err) {
			return goerrors.Errorf("failed to stop container %s: %w", id, err)
		}
	}

	err = c.docker.ContainerRemove(ctx, id, container.RemoveOptions{Force: true})
	if err != nil && !docker.IsErrNotFound(err) {
		return goerrors.Errorf("failed to remove container %s: %w", id, err)
	}
	return nil
}

func (c *dockerSandboxClient) stopSandbox(ctx context.Context, id string) error {
	err := c.docker.ContainerPause(ctx, id)
	if err != nil {
		return goerrors.Errorf("failed to pause container %s: %w", id, err)
	}
	return nil
}

func (c *dockerSandboxClient) resumeSandbox(ctx context.Context, id string) error {
	err := c.docker.ContainerUnpause(ctx, id)
	if err != nil {
		return goerrors.Errorf("failed to unpause container %s: %w", id, err)
	}
	return nil
}

// executeCommand runs a command inside a Docker container via docker exec.
func (c *dockerSandboxClient) executeCommand(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
	return c.executeDockerCommand(ctx, sb, req, nil, false)
}

func (c *dockerSandboxClient) executeCommandWithStdin(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, readyMarker string) (*sandboxsdk.ExecCommandResponse, error) {
	return c.executeDockerCommand(ctx, sb, req, stdin, true)
}

func (c *dockerSandboxClient) executeDockerCommand(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, attachStdin bool) (*sandboxsdk.ExecCommandResponse, error) {
	cmd := []string{req.Command}
	cmd = append(cmd, req.Args...)

	execCfg := container.ExecOptions{
		Cmd:          cmd,
		AttachStdin:  attachStdin,
		AttachStdout: true,
		AttachStderr: true,
		WorkingDir:   req.WorkingDirectory,
		Env:          mapToEnvSlice(req.Environment),
	}

	execResp, err := c.docker.ContainerExecCreate(ctx, sb.ID, execCfg)
	if err != nil {
		return nil, goerrors.Errorf("failed to create exec: %w", err)
	}

	attachResp, err := c.docker.ContainerExecAttach(ctx, execResp.ID, container.ExecAttachOptions{})
	if err != nil {
		return nil, goerrors.Errorf("failed to attach exec: %w", err)
	}
	defer attachResp.Close()

	start := time.Now()

	var stdinErrCh chan error
	if attachStdin {
		stdinErrCh = make(chan error, 1)
		go func() {
			_, writeErr := attachResp.Conn.Write(stdin)
			if writeErr == nil {
				writeErr = attachResp.CloseWrite()
			}
			stdinErrCh <- writeErr
		}()
	}

	var stdout, stderr bytes.Buffer
	_, err = stdcopy.StdCopy(&stdout, &stderr, attachResp.Reader)
	if err != nil {
		return nil, goerrors.Errorf("failed to read exec output: %w", err)
	}
	if attachStdin {
		writeErr := <-stdinErrCh
		if writeErr != nil {
			return nil, goerrors.Errorf("failed to write exec stdin: %w", writeErr)
		}
	}

	inspectResp, err := c.docker.ContainerExecInspect(ctx, execResp.ID)
	if err != nil {
		return nil, goerrors.Errorf("failed to inspect exec result: %w", err)
	}

	return &sandboxsdk.ExecCommandResponse{
		ExitCode:        inspectResp.ExitCode,
		Stdout:          stdout.String(),
		Stderr:          stderr.String(),
		ExecutionTimeMs: int(time.Since(start).Milliseconds()),
	}, nil
}

func mapToEnvSlice(env map[string]string) []string {
	if env == nil {
		return nil
	}
	result := make([]string, 0, len(env))
	for k, v := range env {
		result = append(result, k+"="+v)
	}
	return result
}
