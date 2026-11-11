package sandbox

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"maps"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	sandboxsdk "github.com/github/sandbox/go/sandbox"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp"
)

// ErrCLIExitFailure is returned when the Copilot CLI exits with a non-zero exit code.
// This sentinel marks the error as a deterministic, non-retriable failure
// (e.g., missing secrets, misconfiguration) so that callers can immediately
// surface an error to the user rather than retrying for an extended period.
var ErrCLIExitFailure = goerrors.New("CLI launch command failed with non-zero exit code")

const (
	readyTimeout           = 60 * time.Second
	readyPollInterval      = 2 * time.Second
	ccav3LaunchTimeout     = 12 * time.Second
	cliResumeLaunchTimeout = 12 * time.Second

	execOperationCloneRepository  = "clone_repository"
	execOperationWriteMCPConfig   = "write_mcp_config"
	execOperationWriteEventFile   = "write_event_file"
	execOperationWriteEnvFile     = "write_environment_file"
	execOperationWriteLaunchFiles = "write_launch_files"
)

func (s *Service) buildEnvVars(params *CreateSandboxParams) map[string]string {
	env := map[string]string{
		"COPILOT_API_URL":       s.opts.CopilotAPIURL,
		"HOME":                  "/root",
		"REMOTE_SESSION_EXPORT": "true",
		"PATH":                  "/usr/local/bin:/usr/bin:/bin",
	}
	if s.opts.MissionControlBaseURL != "" {
		env["COPILOT_MC_BASE_URL"] = s.opts.MissionControlBaseURL
	}
	if params.ProblemStatement != "" {
		env["COPILOT_AGENT_PROMPT"] = params.ProblemStatement
	}
	// Merge caller-provided environment variables. ccav3 callers must keep this
	// non-secret; runtime auth secrets are delivered through stdin.
	maps.Copy(env, params.EnvironmentVariables)
	return env
}

func (s *Service) cloneRepository(ctx context.Context, backend sandboxBackend, sb *sandboxInstance, repoNWO, branchName string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.cloneRepository")
	defer span.End()

	serverHost := "github.com"
	if s.opts.GitHubServerURL != "" {
		parsed, parseErr := url.Parse(s.opts.GitHubServerURL)
		if parseErr == nil && parsed.Host != "" {
			serverHost = parsed.Host
		}
	}

	gitFlags := ""
	if s.opts.UseDockerBackend {
		gitFlags = "-c http.sslVerify=false "
	}

	workDir := RepositoryWorkDir(repoNWO)
	cloneCmd := fmt.Sprintf(
		"mkdir -p %s && git %sclone --depth=1 --single-branch \"https://x-access-token:$GITHUB_COPILOT_GIT_TOKEN@%s/%s.git\" %s",
		shellQuote(workDir), gitFlags, serverHost, repoNWO, shellQuote(workDir),
	)
	if branchName != "" {
		cloneCmd = fmt.Sprintf(
			"mkdir -p %s && git %sclone --depth=1 --single-branch --branch %s \"https://x-access-token:$GITHUB_COPILOT_GIT_TOKEN@%s/%s.git\" %s",
			shellQuote(workDir), gitFlags, shellQuote(branchName), serverHost, repoNWO, shellQuote(workDir),
		)
	}

	_, err := s.execOrFail(ctx, backend, sb, cloneCmd, execOperationCloneRepository)
	return err
}

// RepositoryWorkDir returns the workspace directory for a repo inside
// the sandbox VM.
func RepositoryWorkDir(repoNWO string) string {
	repoName := repoNWO
	if slash := strings.LastIndex(repoNWO, "/"); slash >= 0 {
		repoName = repoNWO[slash+1:]
	}
	return "/workspaces/" + repoName
}

func (s *Service) writeMCPConfig(ctx context.Context, backend sandboxBackend, sb *sandboxInstance, params *CreateSandboxParams) {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.writeMCPConfig")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sb.ID),
		kvp.Uint64("actor_id", params.ActorID),
	)

	// MCP configuration is repository-scoped. Skip the fetch entirely when
	// the sandbox is not attached to a repository — there is nothing for
	// dotcom to resolve and the request would be rejected with
	// "repository_id must be non empty".
	if params.RepositoryID == 0 {
		logger.Info("Skipping MCP config: no repository attached")
		return
	}

	mcpResp, err := mcp.Configure(ctx, mcp.ConfigureParams{
		GHTwirp:      s.ghTwirp,
		RepositoryID: int64(params.RepositoryID),
		UserID:       int64(params.ActorID),
		FFClient:     s.ffClient,
	})
	if err != nil {
		logger.WithError(err).Warn("Failed to get MCP config")
		return
	}

	if mcpResp.Encoded == "" {
		return
	}

	mcpJSON, err := base64.StdEncoding.DecodeString(mcpResp.Encoded)
	if err != nil {
		logger.WithError(err).Warn("Failed to decode MCP config")
		return
	}

	writeCmd := fmt.Sprintf("mkdir -p /root/.copilot && cat > /root/.copilot/mcp-config.json << 'MCPEOF'\n%s\nMCPEOF", string(mcpJSON))
	_, writeErr := s.execOrFail(ctx, backend, sb, writeCmd, execOperationWriteMCPConfig)
	if writeErr != nil {
		logger.WithError(writeErr).Warn("Failed to write MCP config")
		return
	}

	logger.Info("MCP config written to sandbox")
}

func (s *Service) startCopilotCLI(ctx context.Context, backend sandboxBackend, sb *sandboxInstance, params *CreateSandboxParams) error {
	stdinSecretsPayload, err := buildCcav3StdinSecretsPayload(params)
	if err != nil {
		return err
	}
	copilotCommand := s.buildCopilotCommand(params)
	launchCommand := copilotCommand
	// Only the interactive Copilot CLI is wrapped in tmux. The ccav3 command
	// performs its own stdin handoff and detaches the node process after the
	// handoff completes.
	if !params.UseCcav3 {
		launchCommand = buildTmuxLaunchCommand(copilotCommand)
	}
	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sb.ID),
		kvp.Uint64("actor_id", params.ActorID),
		kvp.String("command", copilotCommand),
	)
	logger.Info("Starting Copilot CLI")

	launchStart := time.Now()
	req := &sandboxsdk.ExecCommandRequest{
		Command: "sh",
		Args:    []string{"-c", launchCommand},
	}
	var result *sandboxsdk.ExecCommandResponse
	if len(stdinSecretsPayload) > 0 {
		// Bound the ccav3 wrapper wait so a failed stdin/FIFO handoff cannot
		// leave LaunchAgent blocked indefinitely. The outer launch timeout is
		// intentionally slightly larger than the inner stdinReadyMarkerTimeout
		// in backend.go so that a missing-marker timeout surfaces with its
		// more specific error message rather than being shadowed by ctx
		// cancellation. The extra slack accommodates SendStdin + exit_code
		// receipt after the marker phase completes.
		launchCtx, cancel := context.WithTimeout(ctx, ccav3LaunchTimeout)
		defer cancel()
		result, err = backend.executeCommandWithStdin(launchCtx, sb, req, stdinSecretsPayload, ccav3StdinReadyMarker)
	} else {
		result, err = backend.executeCommand(ctx, sb, req)
	}
	metricTags := s.obsv.TelemetryTags(ctx)
	s.obsv.DistributionMs(ctx, "sandbox.cli_launch_duration_ms", metricTags, time.Since(launchStart))

	if result != nil {
		s.obsv.DistributionMs(ctx, "sandbox.cli_launch_server_duration_ms", metricTags, time.Duration(result.ExecutionTimeMs)*time.Millisecond)
	}

	if err != nil {
		s.obsv.Increment(ctx, "sandbox.cli_launch_error", metricTags.Merge(stats.Tags{"kind": "transport"}))
		return goerrors.Errorf("CLI launch error in sandbox %s: %w", sb.ID, err)
	}
	if result != nil && result.ExitCode != 0 {
		s.obsv.Increment(ctx, "sandbox.cli_launch_error", metricTags.Merge(stats.Tags{"kind": "nonzero_exit"}))
		return goerrors.Errorf("CLI launch command exited %d in sandbox %s: %s: %w", result.ExitCode, sb.ID, result.Stderr, ErrCLIExitFailure)
	}

	s.obsv.Increment(ctx, "sandbox.cli_launch_success", metricTags)
	logger.Info("Copilot CLI launched")
	return nil
}

func buildTmuxLaunchCommand(copilotCommand string) string {
	return fmt.Sprintf("tmux new-session -d -s copilot %s", shellQuote(copilotCommand))
}

func buildCcav3StdinSecretsPayload(params *CreateSandboxParams) ([]byte, error) {
	if !params.UseCcav3 || len(params.StdinSecrets) == 0 {
		return nil, nil
	}
	contents, err := buildStdinSecretsJSON(params.StdinSecrets)
	if err != nil {
		return nil, err
	}
	return []byte(contents + "\n"), nil
}

func (s *Service) execOrFail(ctx context.Context, backend sandboxBackend, sb *sandboxInstance, command, operation string) (*sandboxsdk.ExecCommandResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.execOrFail")
	defer span.End()

	execStart := time.Now()

	result, err := backend.executeCommand(ctx, sb, &sandboxsdk.ExecCommandRequest{
		Command: "sh",
		Args:    []string{"-c", command},
	})

	metricTags := s.obsv.TelemetryTags(ctx).Merge(stats.Tags{"operation": operation})
	s.obsv.DistributionMs(ctx, "sandbox.exec_duration_ms", metricTags, time.Since(execStart))

	if result != nil {
		s.obsv.DistributionMs(ctx, "sandbox.exec_server_duration_ms", metricTags, time.Duration(result.ExecutionTimeMs)*time.Millisecond)
	}

	if err != nil {
		s.obsv.Increment(ctx, "sandbox.exec_error", stats.Tags{"method": "execOrFail", "operation": operation, "kind": "transport"})
		wrappedErr := goerrors.Errorf("sandbox exec failed: %w", err)
		s.obsv.LogAndReportError(ctx, wrappedErr, fmt.Sprintf("sandbox executeCommand error in %s", sb.ID))
		return nil, wrappedErr
	}
	if result.ExitCode != 0 {
		s.obsv.Increment(ctx, "sandbox.exec_error", stats.Tags{"method": "execOrFail", "operation": operation, "kind": "nonzero_exit"})
		wrappedErr := goerrors.Errorf("sandbox command failed (exit %d)\nstderr: %s", result.ExitCode, result.Stderr)
		s.obsv.LogAndReportError(ctx, wrappedErr, fmt.Sprintf("sandbox command failed (exit %d) in %s: %s", result.ExitCode, sb.ID, truncateCommand(command)))
		return result, wrappedErr
	}
	s.obsv.Increment(ctx, "sandbox.exec_success", stats.Tags{"method": "execOrFail", "operation": operation})
	return result, nil
}

func (s *Service) waitForReady(ctx context.Context, backend sandboxBackend, sandboxID string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.waitForReady")
	defer span.End()

	deadline := time.Now().Add(readyTimeout)
	for time.Now().Before(deadline) {
		sb, err := backend.getSandbox(ctx, sandboxID)
		if err != nil {
			return goerrors.Errorf("failed to check sandbox state: %w", err)
		}

		switch {
		case IsSandboxRunning(sb.State):
			return nil
		case isTerminalSandboxState(sb.State):
			return goerrors.Errorf("sandbox entered terminal state: %s", sb.State)
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(readyPollInterval):
		}
	}

	return goerrors.Errorf("sandbox %s did not become ready within %s", sandboxID, readyTimeout)
}

func (s *Service) cleanupSandbox(ctx context.Context, backend sandboxBackend, sandboxID string, actorID uint64) {
	if s.opts.UseDockerBackend {
		return
	}
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.cleanupSandbox")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("sandbox_id", sandboxID),
		kvp.Uint64("actor_id", actorID),
	)
	if s.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentSandboxDebugRetain, int64(actorID)) {
		logger.Info("Retaining sandbox after error for debugging (feature flag enabled)")
		return
	}
	err := backend.deleteSandbox(ctx, sandboxID)
	if err != nil {
		logger.WithError(err).Warn("Failed to clean up sandbox")
	}
}

// writeLaunchFiles writes ccav3's event and/or environment file in a single
// sandbox exec so resume can refresh both files with one Launch round trip.
func (s *Service) writeLaunchFiles(ctx context.Context, backend sandboxBackend, sb *sandboxInstance, eventJSON string, envVars map[string]string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "sandbox.Service.writeLaunchFiles")
	defer span.End()

	var commands []string
	if eventJSON != "" {
		commands = append(commands, buildWriteBase64FileCommand(EventFilePath, eventJSON))
	}
	if len(envVars) > 0 {
		contents, err := buildEnvironmentFile(envVars)
		if err != nil {
			return err
		}
		commands = append(commands, buildWriteBase64FileCommand(EnvironmentFilePath, contents))
	}
	if len(commands) == 0 {
		return nil
	}

	operation := execOperationWriteLaunchFiles
	if len(commands) == 1 {
		if eventJSON != "" {
			operation = execOperationWriteEventFile
		} else {
			operation = execOperationWriteEnvFile
		}
	}

	cmd := fmt.Sprintf("(umask 077 && %s)", strings.Join(commands, " && "))
	_, err := s.execOrFail(ctx, backend, sb, cmd, operation)
	return err
}

func buildWriteBase64FileCommand(path, contents string) string {
	encoded := base64.StdEncoding.EncodeToString([]byte(contents))
	return fmt.Sprintf("printf '%%s' '%s' | base64 -d > %s", encoded, shellQuote(path))
}

func buildStdinSecretsJSON(secrets map[string]string) (string, error) {
	contents, err := json.Marshal(secrets)
	if err != nil {
		return "", goerrors.Errorf("failed to marshal stdin secrets: %w", err)
	}
	return string(contents), nil
}

func buildEnvironmentFile(envVars map[string]string) (string, error) {
	keys := make([]string, 0, len(envVars))
	for key := range envVars {
		if !isShellIdentifier(key) {
			return "", goerrors.Errorf("invalid environment variable name: %s", key)
		}
		keys = append(keys, key)
	}
	sort.Strings(keys)

	var b strings.Builder
	for _, key := range keys {
		_, _ = b.WriteString("export ")
		_, _ = b.WriteString(key)
		_, _ = b.WriteString("=")
		_, _ = b.WriteString(shellQuote(envVars[key]))
		_, _ = b.WriteString("\n")
	}
	return b.String(), nil
}

func isShellIdentifier(value string) bool {
	if value == "" {
		return false
	}
	for i, r := range value {
		switch {
		case r == '_':
		case r >= 'A' && r <= 'Z':
		case r >= 'a' && r <= 'z':
		case i > 0 && r >= '0' && r <= '9':
		default:
			return false
		}
	}
	return true
}

// truncateCommand returns a prefix of the command safe for logging.
func truncateCommand(cmd string) string {
	const maxLen = 80
	if len(cmd) <= maxLen {
		return cmd
	}
	return cmd[:maxLen] + "..."
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

func isTerminalSandboxState(state string) bool {
	return strings.EqualFold(state, "failed") || strings.EqualFold(state, "deleted")
}
