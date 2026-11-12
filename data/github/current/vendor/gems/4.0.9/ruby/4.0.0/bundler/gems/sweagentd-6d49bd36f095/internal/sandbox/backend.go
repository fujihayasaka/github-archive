package sandbox

import (
	"bytes"
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	launchsandbox "github.com/github/launch/services/pb/sandbox"
	sandboxsdk "github.com/github/sandbox/go/sandbox"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/twitchtv/twirp"
)

const (
	launchTwirpClientTimeout = 10 * time.Second
	stdinReadyMarkerTimeout  = 10 * time.Second
)

// sandboxBackend is the boundary between sandbox orchestration and the concrete
// compute implementation. Cloud sandboxes use Launch Twirp for lifecycle and
// Sandbox SDK ADC helpers for exec; local development uses Docker.
type sandboxBackend interface {
	createSandbox(ctx context.Context, opts *createSandboxOptions) (*sandboxInstance, error)
	getSandbox(ctx context.Context, id string) (*sandboxInstance, error)
	deleteSandbox(ctx context.Context, id string) error
	stopSandbox(ctx context.Context, id string) error
	resumeSandbox(ctx context.Context, id string) error
	executeCommand(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error)
	executeCommandWithStdin(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, readyMarker string) (*sandboxsdk.ExecCommandResponse, error)
}

type sandboxInstance struct {
	ID          string
	State       string
	Labels      map[string]string
	execSandbox *sandboxsdk.Sandbox
}

type sandboxResources struct {
	CPU    string
	Memory string
}

type createSandboxOptions struct {
	SourceRef            *launchsandbox.CreateSandboxSourceRef
	Resources            *sandboxResources
	Labels               map[string]string
	EnvironmentVariables map[string]string
	EgressPolicy         *launchsandbox.EgressPolicy
	Lifecycle            *launchsandbox.LifecyclePolicy
	Repositories         map[string]*launchsandbox.Repositories
	BillableOwnerID      uint64
	BillableOwnerType    string
}

// launchBackend calls Launch's internal sandbox Twirp service for lifecycle,
// then delegates create-time ADC credentials to the Sandbox SDK for exec.
type launchBackend struct {
	sandboxClient launchsandbox.LaunchSandboxService
	execClient    *sandboxsdk.Client
	actor         *launchsandbox.ActorIdentity
}

func (b *launchBackend) createSandbox(ctx context.Context, opts *createSandboxOptions) (*sandboxInstance, error) {
	if opts.Resources == nil {
		return nil, goerrors.New("sandbox resources are required")
	}
	resp, err := b.sandboxClient.CreateSandbox(ctx, &launchsandbox.CreateSandboxRequest{
		Actor:     b.actor,
		SourceRef: opts.SourceRef,
		Resources: &launchsandbox.Resources{
			Cpu:    opts.Resources.CPU,
			Memory: opts.Resources.Memory,
		},
		Labels:               opts.Labels,
		EnvironmentVariables: opts.EnvironmentVariables,
		EgressPolicy:         opts.EgressPolicy,
		Lifecycle:            opts.Lifecycle,
		Repositories:         opts.Repositories,
		BillableOwnerId:      opts.BillableOwnerID,
		BillableOwnerType:    opts.BillableOwnerType,
	})
	if err != nil {
		return nil, err
	}
	sb := b.sandboxInstanceFromProto(resp.GetSandbox())
	if sb == nil {
		return nil, goerrors.New("Launch returned empty sandbox create response")
	}
	if sb.execSandbox == nil {
		return nil, goerrors.New("Launch returned sandbox without exec credentials")
	}
	return sb, nil
}

func (b *launchBackend) getSandbox(ctx context.Context, id string) (*sandboxInstance, error) {
	resp, err := b.sandboxClient.GetSandbox(ctx, &launchsandbox.GetSandboxRequest{
		SandboxId:    id,
		IncludeToken: true,
		Actor:        b.actor,
	})
	if err != nil {
		return nil, err
	}
	sb := b.sandboxInstanceFromProto(resp.GetSandbox())
	if sb == nil {
		return nil, goerrors.New("Launch returned empty sandbox get response")
	}
	return sb, nil
}

func (b *launchBackend) deleteSandbox(ctx context.Context, id string) error {
	_, err := b.sandboxClient.DeleteSandbox(ctx, &launchsandbox.DeleteSandboxRequest{
		SandboxId: id,
		Actor:     b.actor,
	})
	return err
}

func (b *launchBackend) stopSandbox(ctx context.Context, id string) error {
	_, err := b.sandboxClient.StopSandbox(ctx, &launchsandbox.StopSandboxRequest{
		SandboxId: id,
		Actor:     b.actor,
	})
	return err
}

func (b *launchBackend) resumeSandbox(ctx context.Context, id string) error {
	_, err := b.sandboxClient.ResumeSandbox(ctx, &launchsandbox.ResumeSandboxRequest{
		SandboxId: id,
		Actor:     b.actor,
	})
	return err
}

func (b *launchBackend) executeCommand(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
	execSandbox, err := b.execSandbox(sb)
	if err != nil {
		return nil, err
	}
	resp, err := execSandbox.ExecuteCommand(ctx, req)
	if err != nil {
		return nil, goerrors.Errorf("execute sandbox command: %w", err)
	}
	return resp, nil
}

func (b *launchBackend) executeCommandWithStdin(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, readyMarker string) (*sandboxsdk.ExecCommandResponse, error) {
	execSandbox, err := b.execSandbox(sb)
	if err != nil {
		return nil, err
	}
	stream, err := execSandbox.ExecStreamConnect(ctx)
	if err != nil {
		return nil, goerrors.Errorf("connect sandbox exec stream: %w", err)
	}
	defer func() {
		_ = stream.Close()
	}()

	stdinEnabled := true
	// ADC currently delivers streamed stdin reliably through the TTY path.
	ttyEnabled := true
	start := time.Now()
	err = stream.Start(sandboxsdk.ExecStreamStartRequest{
		Command:          req.Command,
		Args:             req.Args,
		Environment:      req.Environment,
		WorkingDirectory: req.WorkingDirectory,
		Stdin:            &stdinEnabled,
		Tty:              &ttyEnabled,
	})
	if err != nil {
		return nil, goerrors.Errorf("start sandbox exec stream: %w", err)
	}

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	if readyMarker != "" {
		resp, err := waitForStdinReadyMarker(stream, readyMarker, &stdout, &stderr, start, stdinReadyMarkerTimeout)
		if err != nil {
			return nil, err
		}
		if resp != nil {
			return resp, nil
		}
	}
	if len(stdin) > 0 {
		err = stream.SendStdin(stdin)
		if err != nil {
			return nil, goerrors.Errorf("send sandbox exec stdin: %w", err)
		}
	}

	for {
		msgType, data, exitCode, receiveErr := stream.ReceiveData()
		if receiveErr != nil {
			return nil, goerrors.Errorf("receive sandbox exec stream: %w", receiveErr)
		}
		switch msgType {
		case "stdout":
			_, _ = stdout.Write(data)
		case "stderr":
			_, _ = stderr.Write(data)
		case "exit_code":
			return &sandboxsdk.ExecCommandResponse{
				ExitCode:        exitCode,
				Stdout:          stdout.String(),
				Stderr:          stderr.String(),
				ExecutionTimeMs: int(time.Since(start).Milliseconds()),
			}, nil
		default:
		}
	}
}

func waitForStdinReadyMarker(stream execStream, readyMarker string, stdout, stderr *bytes.Buffer, start time.Time, timeout time.Duration) (*sandboxsdk.ExecCommandResponse, error) {
	result := make(chan waitForStdinReadyMarkerResult, 1)
	go func() {
		resp, err := receiveUntilStdinReadyMarker(stream, readyMarker, stdout, stderr, start)
		result <- waitForStdinReadyMarkerResult{resp: resp, err: err}
	}()

	timer := time.NewTimer(timeout)
	defer timer.Stop()

	select {
	case res := <-result:
		return res.resp, res.err
	case <-timer.C:
		_ = stream.Close()
		return nil, goerrors.Errorf("sandbox exec stream did not emit stdin ready marker within %s", timeout)
	}
}

type waitForStdinReadyMarkerResult struct {
	resp *sandboxsdk.ExecCommandResponse
	err  error
}

func receiveUntilStdinReadyMarker(stream execStreamReceiver, readyMarker string, stdout, stderr *bytes.Buffer, start time.Time) (*sandboxsdk.ExecCommandResponse, error) {
	var pendingStdout bytes.Buffer
	for {
		msgType, data, exitCode, receiveErr := stream.ReceiveData()
		if receiveErr != nil {
			return nil, goerrors.Errorf("receive sandbox exec stream: %w", receiveErr)
		}
		switch msgType {
		case "stdout":
			_, _ = pendingStdout.Write(data)
			if strings.Contains(pendingStdout.String(), readyMarker) {
				_, _ = stdout.WriteString(stripReadyMarker(pendingStdout.String(), readyMarker))
				return nil, nil
			}
		case "stderr":
			_, _ = stderr.Write(data)
		case "exit_code":
			return &sandboxsdk.ExecCommandResponse{
				ExitCode:        exitCode,
				Stdout:          pendingStdout.String(),
				Stderr:          stderr.String(),
				ExecutionTimeMs: int(time.Since(start).Milliseconds()),
			}, nil
		default:
		}
	}
}

type execStream interface {
	execStreamReceiver
	Close() error
}

type execStreamReceiver interface {
	ReceiveData() (msgType string, data []byte, exitCode int, err error)
}

func stripReadyMarker(output, readyMarker string) string {
	output = strings.Replace(output, readyMarker+"\r\n", "", 1)
	output = strings.Replace(output, readyMarker+"\n", "", 1)
	return strings.Replace(output, readyMarker, "", 1)
}

func (b *launchBackend) execSandbox(sb *sandboxInstance) (*sandboxsdk.Sandbox, error) {
	if sb == nil || sb.execSandbox == nil {
		return nil, goerrors.New("sandbox exec credentials are required")
	}
	return sb.execSandbox, nil
}

func (s *Service) newBackend(actorID uint64) (sandboxBackend, error) {
	if s.backendFactory != nil {
		return s.backendFactory(actorID)
	}
	if s.opts.UseDockerBackend {
		return newDockerSandboxClient()
	}
	return s.newLaunchBackend(actorID)
}

func (s *Service) newLaunchBackend(actorID uint64) (*launchBackend, error) {
	if actorID == 0 {
		return nil, goerrors.New("actor ID is required for Launch sandbox Twirp")
	}

	sandboxClient, err := s.newLaunchSandboxClient()
	if err != nil {
		return nil, err
	}

	return &launchBackend{
		sandboxClient: sandboxClient,
		execClient:    s.newSandboxExecClient(),
		actor:         &launchsandbox.ActorIdentity{Id: actorID},
	}, nil
}

func (s *Service) newLaunchSandboxClient() (launchsandbox.LaunchSandboxService, error) {
	if s.opts.LaunchTwirpBaseURL == "" {
		return nil, goerrors.New("Launch deployer Twirp base URL is required")
	}
	if s.opts.LaunchTwirpHMACKey == "" {
		return nil, goerrors.New("Launch deployer Twirp HMAC key is required")
	}

	twirpHTTPClient := &http.Client{
		Timeout: launchTwirpClientTimeout,
		Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, s.obsv, "launch-twirp", func(*http.Request) stats.Tags {
			return stats.Tags{"api_target": "launch_sandbox_twirp"}
		}),
	}
	signedClient, err := twirpAuth.NewRequestHMACSigner(s.opts.LaunchTwirpHMACKey, twirpHTTPClient)
	if err != nil {
		return nil, goerrors.Errorf("failed to create HMAC signer for Launch deployer Twirp client: %w", err)
	}

	hooks := &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, req *http.Request) (context.Context, error) {
			req.Header.Set("User-Agent", "sweagentd")
			if reqID := requestid.GetGitHubRequestID(ctx); reqID != "" {
				req.Header.Set(headers.GitHubRequestID, reqID)
			}
			return ctx, nil
		},
	}
	return launchsandbox.NewLaunchSandboxServiceProtobufClient(s.opts.LaunchTwirpBaseURL, signedClient, twirp.WithClientHooks(hooks)), nil
}

func (s *Service) newSandboxExecClient() *sandboxsdk.Client {
	return sandboxsdk.NewClient("",
		sandboxsdk.WithHTTPClient(&http.Client{
			Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, s.obsv, "sandbox-adc", func(*http.Request) stats.Tags {
				return stats.Tags{"api_target": "sandbox_adc"}
			}),
		}),
		sandboxsdk.WithUserAgent("sweagentd"),
	)
}

func (b *launchBackend) sandboxInstanceFromProto(sb *launchsandbox.SandboxProto) *sandboxInstance {
	if sb == nil {
		return nil
	}
	instance := &sandboxInstance{
		ID:     sb.GetId(),
		State:  sb.GetState(),
		Labels: sb.GetLabels(),
	}
	if sb.GetToken() != "" && sb.GetUrls().GetCommandUrl() != "" && sb.GetUrls().GetStreamingUrl() != "" {
		instance.execSandbox = b.execClient.NewExecSandbox(sb.GetToken(), sb.GetUrls().GetCommandUrl(), sb.GetUrls().GetStreamingUrl())
	}
	return instance
}
