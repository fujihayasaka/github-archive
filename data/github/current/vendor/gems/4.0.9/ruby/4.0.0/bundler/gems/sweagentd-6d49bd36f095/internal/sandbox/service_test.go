package sandbox

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	launchsandbox "github.com/github/launch/services/pb/sandbox"
	sandboxsdk "github.com/github/sandbox/go/sandbox"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

// mockBackend implements sandboxBackend for testing.
type mockBackend struct {
	createFunc           func(ctx context.Context, opts *createSandboxOptions) (*sandboxInstance, error)
	getFunc              func(ctx context.Context, id string) (*sandboxInstance, error)
	deleteFunc           func(ctx context.Context, id string) error
	stopFunc             func(ctx context.Context, id string) error
	resumeFunc           func(ctx context.Context, id string) error
	executeFunc          func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error)
	executeWithStdinFunc func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, readyMarker string) (*sandboxsdk.ExecCommandResponse, error)
}

type launchSandboxServiceStub struct {
	getSandboxFunc func(context.Context, *launchsandbox.GetSandboxRequest) (*launchsandbox.GetSandboxResponse, error)
}

type sourceRefFFClient struct {
	featureflags.NoopClient

	userOrRepoEnabled map[string]bool
	userOrRepoCalls   int
	repoCalls         int
}

func (f *sourceRefFFClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	f.userOrRepoCalls++
	return f.userOrRepoEnabled[featureFlagName]
}

func (f *sourceRefFFClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	f.repoCalls++
	return false
}

func (m *mockBackend) createSandbox(ctx context.Context, opts *createSandboxOptions) (*sandboxInstance, error) {
	if m.createFunc != nil {
		return m.createFunc(ctx, opts)
	}
	return &sandboxInstance{
		ID:    "sb-test-123",
		State: "Running",
	}, nil
}

func (m *mockBackend) getSandbox(ctx context.Context, id string) (*sandboxInstance, error) {
	if m.getFunc != nil {
		return m.getFunc(ctx, id)
	}
	return &sandboxInstance{ID: id, State: "Running"}, nil
}

func (m *mockBackend) deleteSandbox(ctx context.Context, id string) error {
	if m.deleteFunc != nil {
		return m.deleteFunc(ctx, id)
	}
	return nil
}

func (m *mockBackend) stopSandbox(ctx context.Context, id string) error {
	if m.stopFunc != nil {
		return m.stopFunc(ctx, id)
	}
	return nil
}

func (m *mockBackend) resumeSandbox(ctx context.Context, id string) error {
	if m.resumeFunc != nil {
		return m.resumeFunc(ctx, id)
	}
	return nil
}

func (m *mockBackend) executeCommand(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
	if m.executeFunc != nil {
		return m.executeFunc(ctx, sb, req)
	}
	return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
}

func (m *mockBackend) executeCommandWithStdin(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, readyMarker string) (*sandboxsdk.ExecCommandResponse, error) {
	if m.executeWithStdinFunc != nil {
		return m.executeWithStdinFunc(ctx, sb, req, stdin, readyMarker)
	}
	return m.executeCommand(ctx, sb, req)
}

func (s *launchSandboxServiceStub) GetSandbox(ctx context.Context, req *launchsandbox.GetSandboxRequest) (*launchsandbox.GetSandboxResponse, error) {
	return s.getSandboxFunc(ctx, req)
}

func (s *launchSandboxServiceStub) CreateSandbox(context.Context, *launchsandbox.CreateSandboxRequest) (*launchsandbox.CreateSandboxResponse, error) {
	panic("unexpected CreateSandbox call")
}

func (s *launchSandboxServiceStub) DeleteSandbox(context.Context, *launchsandbox.DeleteSandboxRequest) (*launchsandbox.DeleteSandboxResponse, error) {
	panic("unexpected DeleteSandbox call")
}

func (s *launchSandboxServiceStub) StopSandbox(context.Context, *launchsandbox.StopSandboxRequest) (*launchsandbox.StopSandboxResponse, error) {
	panic("unexpected StopSandbox call")
}

func (s *launchSandboxServiceStub) ResumeSandbox(context.Context, *launchsandbox.ResumeSandboxRequest) (*launchsandbox.ResumeSandboxResponse, error) {
	panic("unexpected ResumeSandbox call")
}

func (s *launchSandboxServiceStub) GenerateSandboxToken(context.Context, *launchsandbox.GenerateSandboxTokenRequest) (*launchsandbox.GenerateSandboxTokenResponse, error) {
	panic("unexpected GenerateSandboxToken call")
}

func (s *launchSandboxServiceStub) StopSandboxesForSpammyActor(context.Context, *launchsandbox.StopSandboxesForSpammyActorRequest) (*launchsandbox.StopSandboxesForSpammyActorResponse, error) {
	panic("unexpected StopSandboxesForSpammyActor call")
}

type blockingExecStream struct {
	closed chan struct{}
}

func (s *blockingExecStream) ReceiveData() (string, []byte, int, error) {
	<-s.closed
	return "", nil, -1, context.Canceled
}

func (s *blockingExecStream) Close() error {
	select {
	case <-s.closed:
	default:
		close(s.closed)
	}
	return nil
}

func TestLaunchBackendExecuteCommandWithStdinStreamsPayload(t *testing.T) {
	startRequests := make(chan sandboxsdk.ExecStreamStartRequest, 1)
	stdinPayloads := make(chan string, 1)
	handlerErrors := make(chan error, 1)

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			handlerErrors <- err
			return
		}
		defer func() {
			_ = conn.Close(websocket.StatusNormalClosure, "done")
		}()

		ctx := r.Context()
		_, data, err := conn.Read(ctx)
		if err != nil {
			handlerErrors <- err
			return
		}
		var startMsg sandboxsdk.ExecStreamStartMessage
		err = json.Unmarshal(data, &startMsg)
		if err != nil {
			handlerErrors <- err
			return
		}
		startRequests <- startMsg.Start
		err = conn.Write(ctx, websocket.MessageText, []byte(`{"type":"session_id","data":"session-123"}`))
		if err != nil {
			handlerErrors <- err
			return
		}
		readyMarker := base64.StdEncoding.EncodeToString([]byte("ready\n"))
		readyMsg, err := json.Marshal(sandboxsdk.ExecStreamServerMessage{Type: "stdout", Data: readyMarker})
		if err != nil {
			handlerErrors <- err
			return
		}
		err = conn.Write(ctx, websocket.MessageText, readyMsg)
		if err != nil {
			handlerErrors <- err
			return
		}

		_, data, err = conn.Read(ctx)
		if err != nil {
			handlerErrors <- err
			return
		}
		var stdinMsg sandboxsdk.ExecStreamStdinMessage
		err = json.Unmarshal(data, &stdinMsg)
		if err != nil {
			handlerErrors <- err
			return
		}
		decoded, err := base64.StdEncoding.DecodeString(stdinMsg.Data)
		if err != nil {
			handlerErrors <- err
			return
		}
		stdinPayloads <- string(decoded)

		stdout := base64.StdEncoding.EncodeToString([]byte("stdout-ok"))
		stderr := base64.StdEncoding.EncodeToString([]byte("stderr-ok"))
		stdoutMsg, err := json.Marshal(sandboxsdk.ExecStreamServerMessage{Type: "stdout", Data: stdout})
		if err != nil {
			handlerErrors <- err
			return
		}
		err = conn.Write(ctx, websocket.MessageText, stdoutMsg)
		if err != nil {
			handlerErrors <- err
			return
		}
		stderrMsg, err := json.Marshal(sandboxsdk.ExecStreamServerMessage{Type: "stderr", Data: stderr})
		if err != nil {
			handlerErrors <- err
			return
		}
		err = conn.Write(ctx, websocket.MessageText, stderrMsg)
		if err != nil {
			handlerErrors <- err
			return
		}
		err = conn.Write(ctx, websocket.MessageText, []byte(`{"type":"exit_code","exitCode":7}`))
		if err != nil {
			handlerErrors <- err
			return
		}
		handlerErrors <- nil
	})
	server := httptest.NewServer(mux)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"
	execSandbox := sandboxsdk.NewClient("gh-token").NewExecSandbox("sandbox-token", "", wsURL)
	backend := &launchBackend{}

	resp, err := backend.executeCommandWithStdin(context.Background(), &sandboxInstance{execSandbox: execSandbox}, &sandboxsdk.ExecCommandRequest{
		Command:          "sh",
		Args:             []string{"-c", "cat"},
		Environment:      map[string]string{"A": "B"},
		WorkingDirectory: "/work",
	}, []byte(`{"secret":"value"}`), "ready")

	require.NoError(t, err)
	require.NotNil(t, resp)
	assert.Equal(t, 7, resp.ExitCode)
	assert.Equal(t, "stdout-ok", resp.Stdout)
	assert.Equal(t, "stderr-ok", resp.Stderr)
	assert.JSONEq(t, `{"secret":"value"}`, <-stdinPayloads)
	startReq := <-startRequests
	assert.Equal(t, "sh", startReq.Command)
	assert.Equal(t, []string{"-c", "cat"}, startReq.Args)
	assert.Equal(t, map[string]string{"A": "B"}, startReq.Environment)
	assert.Equal(t, "/work", startReq.WorkingDirectory)
	require.NotNil(t, startReq.Stdin)
	assert.True(t, *startReq.Stdin)
	require.NotNil(t, startReq.Tty)
	assert.True(t, *startReq.Tty)
	require.NoError(t, <-handlerErrors)
}

func TestWaitForStdinReadyMarkerTimesOut(t *testing.T) {
	stream := &blockingExecStream{closed: make(chan struct{})}
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	resp, err := waitForStdinReadyMarker(stream, "ready", &stdout, &stderr, time.Now(), time.Millisecond)

	require.Error(t, err)
	require.Nil(t, resp)
	assert.Contains(t, err.Error(), "did not emit stdin ready marker")
	select {
	case <-stream.closed:
	default:
		t.Fatal("expected timeout to close the exec stream")
	}
}

func TestBuildEnvVars(t *testing.T) {
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		opts: ServiceOpts{
			CopilotAPIURL:         "https://api.copilot.test",
			MissionControlBaseURL: "https://mc.test",
		},
	}

	params := &CreateSandboxParams{
		RepositoryID:      42,
		RepositoryOwnerID: 7,
		RepositoryNWO:     "org/repo",
		ProblemStatement:  "fix the bug",
		EnvironmentVariables: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-tok",
			"GITHUB_COPILOT_GIT_TOKEN": "git-tok",
			"GITHUB_TOKEN":             "api-tok",
		},
	}

	env := svc.buildEnvVars(params)

	assert.Equal(t, "api-tok", env["GITHUB_COPILOT_API_TOKEN"])
	assert.Equal(t, "git-tok", env["GITHUB_COPILOT_GIT_TOKEN"])
	assert.Equal(t, "api-tok", env["GITHUB_TOKEN"])
	assert.Equal(t, "https://api.copilot.test", env["COPILOT_API_URL"])
	assert.Equal(t, "https://mc.test", env["COPILOT_MC_BASE_URL"])
	assert.Equal(t, "fix the bug", env["COPILOT_AGENT_PROMPT"])
	_, hasAllowAll := env["COPILOT_ALLOW_ALL"]
	assert.False(t, hasAllowAll)
}

func TestBuildEnvVars_OptionalFieldsOmitted(t *testing.T) {
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		opts: ServiceOpts{},
	}

	params := &CreateSandboxParams{
		RepositoryNWO: "org/repo",
		EnvironmentVariables: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-tok",
			"GITHUB_COPILOT_GIT_TOKEN": "git-tok",
			"GITHUB_TOKEN":             "api-tok",
		},
	}

	env := svc.buildEnvVars(params)

	_, hasMC := env["COPILOT_MC_BASE_URL"]
	assert.False(t, hasMC)
	_, hasPrompt := env["COPILOT_AGENT_PROMPT"]
	assert.False(t, hasPrompt)
}

func TestBuildEnvVars_Ccav3KeepsProblemStatementInBootstrapEnv(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters()}

	env := svc.buildEnvVars(&CreateSandboxParams{
		UseCcav3:         true,
		RepositoryNWO:    "org/repo",
		ProblemStatement: "fix the bug",
		EnvironmentVariables: map[string]string{
			"COPILOT_AGENT_RUNNER_TYPE": "STANDALONE",
		},
	})

	assert.Equal(t, "STANDALONE", env["COPILOT_AGENT_RUNNER_TYPE"])
	assert.Equal(t, "fix the bug", env["COPILOT_AGENT_PROMPT"])
}

func TestValidateRequiredEnvVars(t *testing.T) {
	t.Run("ccav3 requires stdin API token", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{}, false, &CreateSandboxParams{UseCcav3: true})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "GITHUB_COPILOT_API_TOKEN")
	})

	t.Run("requires GITHUB_TOKEN for copilot CLI", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{"GITHUB_COPILOT_API_TOKEN": "api-tok"}, false, nil)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "GITHUB_TOKEN")
	})

	t.Run("requires git token when repository is set", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{"GITHUB_TOKEN": "api-tok"}, true, nil)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "GITHUB_COPILOT_GIT_TOKEN")
	})

	t.Run("does not require git token when repository is not set", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{"GITHUB_TOKEN": "api-tok"}, false, nil)
		require.NoError(t, err)
	})

	t.Run("passes with both tokens when repository is set", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{
			"GITHUB_COPILOT_GIT_TOKEN": "git-tok",
			"GITHUB_TOKEN":             "api-tok",
		}, true, nil)
		require.NoError(t, err)
	})

	t.Run("ccav3 requires stdin secrets", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{}, false, &CreateSandboxParams{UseCcav3: true})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "GITHUB_COPILOT_API_TOKEN")
	})

	t.Run("ccav3 requires stdin git token", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{}, false, &CreateSandboxParams{
			UseCcav3: true,
			StdinSecrets: map[string]string{
				"GITHUB_COPILOT_API_TOKEN": "api-tok",
			},
		})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "GITHUB_TOKEN")
	})

	t.Run("ccav3 uses stdin git token for repository setup", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{}, true, &CreateSandboxParams{
			UseCcav3: true,
			StdinSecrets: map[string]string{
				"GITHUB_COPILOT_API_TOKEN": "api-tok",
				"GITHUB_TOKEN":             "git-tok",
			},
		})
		require.NoError(t, err)
	})

	t.Run("ccav3 rejects secrets in bootstrap env", func(t *testing.T) {
		err := validateRequiredEnvVars(map[string]string{}, false, &CreateSandboxParams{
			UseCcav3: true,
			EnvironmentVariables: map[string]string{
				"GITHUB_COPILOT_API_TOKEN": "api-tok",
			},
			StdinSecrets: map[string]string{
				"GITHUB_COPILOT_API_TOKEN": "api-tok",
				"GITHUB_TOKEN":             "git-tok",
			},
		})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "bootstrap environment contains secret key")
	})
}

func TestCcav3RequiredStdinSecretKeysAreSecretEnvKeys(t *testing.T) {
	for _, requiredKey := range ccav3RequiredStdinSecretKeys {
		assert.Contains(t, Ccav3SecretEnvKeys, requiredKey)
	}
}

func TestSandboxSourceRef_Stable(t *testing.T) {
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
	}
	params := &CreateSandboxParams{ActorID: 7, RepositoryID: 42}
	sourceRef := svc.sandboxSourceRef(context.Background(), params)

	require.NotNil(t, sourceRef.Image)
	assert.Equal(t, "cca", sourceRef.Image.Name)
	assert.True(t, sourceRef.Image.IsPublic)
}

func TestSandboxSourceRef_Prerelease(t *testing.T) {
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSandboxPrereleaseImage: true,
		}),
	}
	params := &CreateSandboxParams{ActorID: 7, RepositoryID: 42}
	sourceRef := svc.sandboxSourceRef(context.Background(), params)

	require.NotNil(t, sourceRef.Image)
	assert.Equal(t, "cca-prerelease", sourceRef.Image.Name)
	assert.True(t, sourceRef.Image.IsPublic)
}

func TestSandboxSourceRef_UsesUserOrRepoEnablement(t *testing.T) {
	ffClient := &sourceRefFFClient{userOrRepoEnabled: map[string]bool{
		featureflags.CopilotSWEAgentSandboxPrereleaseImage: true,
	}}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: ffClient,
	}

	params := &CreateSandboxParams{ActorID: 123, RepositoryID: 42}
	sourceRef := svc.sandboxSourceRef(context.Background(), params)

	require.NotNil(t, sourceRef.Image)
	assert.Equal(t, "cca-prerelease", sourceRef.Image.Name)
	assert.Equal(t, 1, ffClient.userOrRepoCalls)
	assert.Equal(t, 0, ffClient.repoCalls)
}

func TestSandboxSourceRef_Ccav3TakesPrecedence(t *testing.T) {
	ffClient := &sourceRefFFClient{userOrRepoEnabled: map[string]bool{
		featureflags.CopilotSWEAgentSandboxPrereleaseImage: true,
	}}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: ffClient,
	}

	// UseCcav3 is set by the CCA launcher, not a feature flag on the service.
	params := &CreateSandboxParams{ActorID: 123, RepositoryID: 42, UseCcav3: true}
	sourceRef := svc.sandboxSourceRef(context.Background(), params)

	require.NotNil(t, sourceRef.Image)
	assert.Equal(t, "cca-runtime", sourceRef.Image.Name)
	// Prerelease flag not checked because UseCcav3 won.
	assert.Equal(t, 0, ffClient.userOrRepoCalls)
}

func TestCreateSandboxUsesDefaultSourceRef(t *testing.T) {
	backend := &mockBackend{
		createFunc: func(ctx context.Context, opts *createSandboxOptions) (*sandboxInstance, error) {
			require.NotNil(t, opts.SourceRef)
			require.NotNil(t, opts.SourceRef.Image)
			assert.Equal(t, "cca", opts.SourceRef.Image.Name)
			assert.True(t, opts.SourceRef.Image.IsPublic)
			return &sandboxInstance{
				ID:    "sb-test-123",
				State: "Running",
			}, nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	result, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		EnvironmentVariables: map[string]string{
			"GITHUB_TOKEN": "api-token",
		},
	})

	require.NoError(t, err)
	assert.Equal(t, "sb-test-123", result.SandboxID)
}

func TestWriteMCPConfigSkippedWhenNoRepository(t *testing.T) {
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		t.Fatal("MCPConfigurationForRepository should not be called when RepositoryID is 0")
		return nil, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
	}

	// Should not panic, not call dotcom, and not invoke any backend exec.
	svc.writeMCPConfig(context.Background(), &mockBackend{}, &sandboxInstance{ID: "sb-1"}, &CreateSandboxParams{
		ActorID:      7,
		RepositoryID: 0,
	})
}

func TestCreateSandboxUsesPrereleaseSourceRef(t *testing.T) {
	backend := &mockBackend{
		createFunc: func(ctx context.Context, opts *createSandboxOptions) (*sandboxInstance, error) {
			require.NotNil(t, opts.SourceRef)
			require.NotNil(t, opts.SourceRef.Image)
			assert.Equal(t, "cca-prerelease", opts.SourceRef.Image.Name)
			assert.True(t, opts.SourceRef.Image.IsPublic)
			return &sandboxInstance{
				ID:    "sb-test-123",
				State: "Running",
			}, nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentSandboxPrereleaseImage: true,
		}),
		ghTwirp: ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	result, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		ActorID:      7,
		RepositoryID: 42,
		EnvironmentVariables: map[string]string{
			"GITHUB_TOKEN": "api-token",
		},
	})

	require.NoError(t, err)
	assert.Equal(t, "sb-test-123", result.SandboxID)
}

func TestShellQuote(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello", "'hello'"},
		{"it's a test", "'it'\\''s a test'"},
		{"", "''"},
		{"foo bar", "'foo bar'"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			assert.Equal(t, tt.expected, shellQuote(tt.input))
		})
	}
}

func TestBuildEnvironmentFile(t *testing.T) {
	contents, err := buildEnvironmentFile(map[string]string{
		"QUOTE":     "it's complicated",
		"API_TOKEN": "tok",
		"PATH":      "/usr/bin:/bin",
	})

	require.NoError(t, err)
	assert.Equal(t, "export API_TOKEN='tok'\nexport PATH='/usr/bin:/bin'\nexport QUOTE='it'\\''s complicated'\n", contents)
}

func TestBuildEnvironmentFileRejectsInvalidName(t *testing.T) {
	tests := []string{"", "1FOO", "BAD-NAME", "FÖÖ"}

	for _, name := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := buildEnvironmentFile(map[string]string{
				name: "value",
			})

			require.Error(t, err)
			assert.Contains(t, err.Error(), "invalid environment variable name")
		})
	}
}

func TestBuildCopilotCommandCcav3WithoutEnvironmentFile(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters()}

	command := svc.buildCopilotCommand(&CreateSandboxParams{
		UseCcav3: true,
	})

	assert.Contains(t, command, "unset GITHUB_TOKEN GITHUB_COPILOT_GITHUB_TOKEN GITHUB_COPILOT_API_TOKEN")
	assert.Contains(t, command, "mkfifo -m 600 \"$ccav3_stdin_fifo\"")
	assert.Contains(t, command, ccav3StdinReadyMarker)
	assert.Contains(t, command, "IFS= read -r ccav3_stdin_secrets")
	assert.Contains(t, command, `ccav3_launch_log="/tmp/cca-launch-$(date +%s)-$$.log"`)
	assert.Contains(t, command, "kill \"$ccav3_stale_pid\"")
	assert.Contains(t, command, "nohup setsid sh -c 'exec node /opt/copilot-runtime/copilot-developer-action-main/dist-cca-v3/index.js /var/log < \"$1\"' sh \"$ccav3_stdin_fifo\" </dev/null >\"$ccav3_launch_log\" 2>&1 &")
	assert.Contains(t, command, "printf '%s' \"$ccav3_stdin_secrets\" > \"$ccav3_stdin_fifo\"")
}

func TestBuildCopilotCommandCcav3SourcesEnvironmentFile(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters()}

	command := svc.buildCopilotCommand(&CreateSandboxParams{
		UseCcav3:            true,
		EnvironmentFilePath: EnvironmentFilePath,
	})

	assert.Contains(t, command, "trap 'rm -f '\\''/tmp/copilot-env.sh'\\''' EXIT")
	assert.Contains(t, command, "set -a && . '/tmp/copilot-env.sh' && set +a && rm -f '/tmp/copilot-env.sh'")
	assert.Contains(t, command, "trap - EXIT")
	assert.Contains(t, command, "mkfifo -m 600 \"$ccav3_stdin_fifo\"")
	assert.Contains(t, command, "nohup setsid sh -c 'exec node /opt/copilot-runtime/copilot-developer-action-main/dist-cca-v3/index.js /var/log < \"$1\"' sh \"$ccav3_stdin_fifo\" </dev/null >\"$ccav3_launch_log\" 2>&1 &")
}

func TestCcav3LaunchCommandPipesLineStdinSecretsToNode(t *testing.T) {
	tempDir := t.TempDir()
	writeExecutable(t, filepath.Join(tempDir, "node"), "#!/bin/sh\ncat > \"$NODE_STDIN_CAPTURE\"\nenv | sort > \"$NODE_ENV_CAPTURE\"\ntouch \"$NODE_STARTED\"\nwhile [ ! -f \"$NODE_RELEASE\" ]; do sleep 0.01; done\ntouch \"$NODE_DONE\"\n")
	// Provide a setsid shim so the test works on platforms (e.g. macOS) where
	// setsid is not installed by default. The real production behavior of
	// setsid (escaping the wrapper's PTY session) is not what this test
	// exercises; this test only verifies stdin/env plumbing.
	writeExecutable(t, filepath.Join(tempDir, "setsid"), "#!/bin/sh\nexec \"$@\"\n")

	envFile := filepath.Join(tempDir, "copilot-env.sh")
	require.NoError(t, os.WriteFile(envFile, []byte("export NONSECRET='ok'\n"), 0o600))
	stdinCapture := filepath.Join(tempDir, "stdin-capture.json")
	envCapture := filepath.Join(tempDir, "env-capture.txt")
	startedPath := filepath.Join(tempDir, "node-started")
	releasePath := filepath.Join(tempDir, "node-release")
	donePath := filepath.Join(tempDir, "node-done")
	payload := `{"GITHUB_TOKEN":"top-secret-value"}`

	svc := &Service{obsv: observability.NewNoopExporters()}
	launchCommand := svc.buildCopilotCommand(&CreateSandboxParams{
		UseCcav3:            true,
		EnvironmentFilePath: envFile,
	})
	require.NotContains(t, launchCommand, "top-secret-value")
	require.NotContains(t, launchCommand, "/tmp/copilot-stdin-secrets.json")

	cmd := exec.Command("sh", "-c", launchCommand)
	cmd.Stdin = strings.NewReader(payload + "\n")
	cmd.Env = append(os.Environ(),
		"PATH="+tempDir+":"+os.Getenv("PATH"),
		"NODE_STDIN_CAPTURE="+stdinCapture,
		"NODE_ENV_CAPTURE="+envCapture,
		"NODE_STARTED="+startedPath,
		"NODE_RELEASE="+releasePath,
		"NODE_DONE="+donePath,
		"GITHUB_TOKEN=parent-env-secret",
	)
	output, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "launch command failed:\n%s", string(output))
	require.Eventually(t, func() bool {
		stdinBytes, readErr := os.ReadFile(stdinCapture)
		return readErr == nil && string(stdinBytes) == payload
	}, time.Second, 10*time.Millisecond)

	stdinBytes, err := os.ReadFile(stdinCapture)
	require.NoError(t, err)
	assert.Equal(t, payload, string(stdinBytes))
	require.Eventually(t, func() bool {
		_, statErr := os.Stat(startedPath)
		return statErr == nil
	}, time.Second, 10*time.Millisecond)
	require.NoFileExists(t, donePath, "launch command should return while ccav3 continues running detached")
	envBytes, err := os.ReadFile(envCapture)
	require.NoError(t, err)
	env := string(envBytes)
	assert.Contains(t, env, "NONSECRET=ok\n")
	assert.NotContains(t, env, "top-secret-value")
	assert.NotContains(t, env, "parent-env-secret")
	_, err = os.Stat(envFile)
	assert.True(t, os.IsNotExist(err), "expected environment file to be removed")
	require.NoError(t, os.WriteFile(releasePath, []byte("done"), 0o600))
	require.Eventually(t, func() bool {
		_, statErr := os.Stat(donePath)
		return statErr == nil
	}, time.Second, 10*time.Millisecond)
}

func writeExecutable(t *testing.T, path, contents string) {
	t.Helper()
	require.NoError(t, os.WriteFile(path, []byte(contents), 0o755))
}

func TestExecCopilotCLIWritesCcav3EventEnvironmentAndStreamsStdinSecrets(t *testing.T) {
	var commands []string
	var launchStdin []byte
	backend := &mockBackend{
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sb-123", sb.ID)
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			commands = append(commands, req.Args[1])
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
		executeWithStdinFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, readyMarker string) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sb-123", sb.ID)
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			commands = append(commands, req.Args[1])
			launchStdin = append([]byte(nil), stdin...)
			assert.Equal(t, ccav3StdinReadyMarker, readyMarker)
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			require.Equal(t, uint64(100), actorID)
			return backend, nil
		},
	}

	err := svc.ExecCopilotCLI(context.Background(), "sb-123", 100, "owner/repo", "fix", nil, map[string]string{
		"COPILOT_AGENT_RUNNER_TYPE": "STANDALONE",
	}, `{"inputs":{"COPILOT_AGENT_INPUTS":"{}"}}`, map[string]string{
		"GITHUB_COPILOT_API_TOKEN": "fresh-api-token",
		"GITHUB_TOKEN":             "fresh-git-token",
	}, true)

	require.NoError(t, err)
	require.Len(t, commands, 2)
	assert.Contains(t, commands[0], "> '/tmp/copilot-event.json'")
	assert.Contains(t, commands[0], "> '/tmp/copilot-env.sh'")
	assert.Contains(t, commands[0], "umask 077")
	assert.NotContains(t, commands[0], "GITHUB_COPILOT_API_TOKEN")
	assert.NotContains(t, commands[0], "fresh-api-token")
	assert.Contains(t, commands[1], "set -a")
	assert.Contains(t, commands[1], "unset GITHUB_TOKEN")
	assert.Contains(t, commands[1], "nohup setsid sh -c")
	assert.Contains(t, commands[1], "/tmp/copilot-env.sh")
	assert.NotContains(t, commands[1], "tmux new-session")
	assert.Contains(t, commands[1], "mkfifo -m 600")
	assert.NotContains(t, commands[1], "head -c")
	assert.NotContains(t, commands[1], "/tmp/copilot-stdin-secrets.json")
	assert.Contains(t, commands[1], ccav3StdinReadyMarker)
	assert.Contains(t, commands[1], "IFS= read -r ccav3_stdin_secrets")
	assert.Contains(t, commands[1], "printf '%s' \"$ccav3_stdin_secrets\" > \"$ccav3_stdin_fifo\"")
	assert.NotContains(t, commands[1], "fresh-api-token")
	assert.NotContains(t, commands[1], "fresh-git-token")
	assert.JSONEq(t, `{"GITHUB_COPILOT_API_TOKEN":"fresh-api-token","GITHUB_TOKEN":"fresh-git-token"}`, string(launchStdin))
	assert.True(t, strings.HasSuffix(string(launchStdin), "\n"), "ccav3 stdin secrets should be newline-terminated for ADC TTY delivery")
}

func TestStartCopilotCLIBoundsCcav3StdinLaunch(t *testing.T) {
	var sawDeadline bool
	backend := &mockBackend{
		executeWithStdinFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest, stdin []byte, readyMarker string) (*sandboxsdk.ExecCommandResponse, error) {
			deadline, ok := ctx.Deadline()
			require.True(t, ok)
			assert.WithinDuration(t, time.Now().Add(ccav3LaunchTimeout), deadline, time.Second)
			assert.Equal(t, ccav3StdinReadyMarker, readyMarker)
			sawDeadline = true
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	svc := &Service{obsv: observability.NewNoopExporters()}

	err := svc.startCopilotCLI(context.Background(), backend, &sandboxInstance{ID: "sb-123"}, &CreateSandboxParams{
		ActorID:  1,
		UseCcav3: true,
		StdinSecrets: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-token",
			"GITHUB_TOKEN":             "git-token",
		},
	})

	require.NoError(t, err)
	assert.True(t, sawDeadline)
}

func TestExecCopilotCLIRejectsCcav3SecretsInEnvironmentFile(t *testing.T) {
	backend := &mockBackend{}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	err := svc.ExecCopilotCLI(context.Background(), "sb-123", 100, "owner/repo", "fix", nil, map[string]string{
		"GITHUB_COPILOT_API_TOKEN": "fresh-api-token",
	}, `{"inputs":{"COPILOT_AGENT_INPUTS":"{}"}}`, map[string]string{
		"GITHUB_COPILOT_API_TOKEN": "fresh-api-token",
		"GITHUB_TOKEN":             "fresh-git-token",
	}, true)

	require.Error(t, err)
	assert.Contains(t, err.Error(), "environment file contains secret key")
}

func TestRepositoryWorkDir(t *testing.T) {
	assert.Equal(t, "/workspaces/repo", RepositoryWorkDir("owner/repo"))
	assert.Equal(t, "/workspaces/repo", RepositoryWorkDir("repo"))
	assert.Equal(t, "/workspaces/repo.name", RepositoryWorkDir("owner/repo.name"))
}

func TestCloneRepositoryUsesRepoNameWorkDir(t *testing.T) {
	tests := []struct {
		name     string
		branch   string
		expected string
	}{
		{
			name:     "default branch",
			expected: "mkdir -p '/workspaces/repo' && git clone --depth=1 --single-branch \"https://x-access-token:$GITHUB_COPILOT_GIT_TOKEN@github.com/owner/repo.git\" '/workspaces/repo'",
		},
		{
			name:     "explicit branch",
			branch:   "feature-branch",
			expected: "mkdir -p '/workspaces/repo' && git clone --depth=1 --single-branch --branch 'feature-branch' \"https://x-access-token:$GITHUB_COPILOT_GIT_TOKEN@github.com/owner/repo.git\" '/workspaces/repo'",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var command string
			backend := &mockBackend{
				executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
					require.Equal(t, "sb-123", sb.ID)
					require.Equal(t, "sh", req.Command)
					require.Len(t, req.Args, 2)
					command = req.Args[1]
					assert.Empty(t, req.Environment)
					return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
				},
			}
			svc := &Service{obsv: observability.NewNoopExporters()}

			err := svc.cloneRepository(context.Background(), backend, &sandboxInstance{ID: "sb-123"}, "owner/repo", tt.branch)

			require.NoError(t, err)
			assert.Equal(t, tt.expected, command)
		})
	}
}

func TestCreateSandboxCcav3SkipsPreLaunchRepositoryClone(t *testing.T) {
	var commands []string
	backend := &mockBackend{
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sb-test-123", sb.ID)
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			commands = append(commands, req.Args[1])
			assert.NotContains(t, req.Environment, "GITHUB_COPILOT_GIT_TOKEN")
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	result, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		RepositoryNWO: "owner/repo",
		ActorID:       1,
		UseCcav3:      true,
		EventFileJSON: `{"inputs":{"COPILOT_AGENT_INPUTS":"{}"}}`,
		StdinSecrets: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-token",
			"GITHUB_TOKEN":             "git-token",
		},
		EnvironmentVariables: map[string]string{
			"COPILOT_AGENT_RUNNER_TYPE":             "STANDALONE",
			"COPILOT_CCA_V3_USE_EXISTING_WORKSPACE": "false",
			"GITHUB_EVENT_PATH":                     EventFilePath,
			"GITHUB_WORKSPACE":                      RepositoryWorkDir("owner/repo"),
		},
	})

	require.NoError(t, err)
	assert.Equal(t, "sb-test-123", result.SandboxID)
	assert.NotEmpty(t, commands)
	for _, command := range commands {
		assert.NotContains(t, command, "git clone")
	}
}

func TestCreateSandboxLaunchesFromRepoNameWorkDir(t *testing.T) {
	var launchCommand string
	backend := &mockBackend{
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sb-test-123", sb.ID)
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			if isTmuxLaunchCommand(req.Args[1]) {
				launchCommand = req.Args[1]
			}
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			require.Equal(t, uint64(1), actorID)
			return backend, nil
		},
	}

	_, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		RepositoryNWO: "owner/repo",
		ActorID:       1,
		EnvironmentVariables: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-token",
			"GITHUB_COPILOT_GIT_TOKEN": "git-token",
			"GITHUB_TOKEN":             "api-token",
		},
		CLIFlags: []string{"--resume=task-123"},
	})

	require.NoError(t, err)
	require.NotEmpty(t, launchCommand)
	assert.Equal(t, "tmux new-session -d -s copilot 'cd '\\''/workspaces/repo'\\'' && copilot --remote --resume=task-123'", launchCommand)
	assert.NotContains(t, launchCommand, "--server")
	assert.NotContains(t, launchCommand, "--auth-token-env")
	assert.NotContains(t, launchCommand, "/tmp/copilot-cmd.sh")
	assert.NotContains(t, launchCommand, "nohup")
	assert.NotContains(t, launchCommand, "setsid")
	assert.NotContains(t, launchCommand, "script")
	assert.NotContains(t, launchCommand, "timeout")
	assert.NotContains(t, launchCommand, "~/.copilot/server.log")
}

func TestCreateSandboxSkipsServiceCloneForCcav3(t *testing.T) {
	var cloneCalled atomic.Bool
	backend := &mockBackend{
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			if strings.Contains(req.Args[1], "git clone") {
				cloneCalled.Store(true)
			}
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	_, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		RepositoryNWO: "owner/repo",
		ActorID:       1,
		UseCcav3:      true,
		EventFileJSON: "{}",
		StdinSecrets: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-token",
			"GITHUB_TOKEN":             "git-token",
		},
	})

	require.NoError(t, err)
	assert.False(t, cloneCalled.Load(), "expected ccav3 to clone the repository instead of sandbox setup")
}

func TestCreateSandboxCcav3LaunchIsNotWrappedInTmux(t *testing.T) {
	var launchCommand string
	backend := &mockBackend{
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			if strings.Contains(req.Args[1], "dist-cca-v3/index.js") {
				launchCommand = req.Args[1]
			}
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	_, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		RepositoryNWO: "owner/repo",
		ActorID:       1,
		UseCcav3:      true,
		EventFileJSON: "{}",
		StdinSecrets: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-token",
			"GITHUB_TOKEN":             "git-token",
		},
	})

	require.NoError(t, err)
	require.NotEmpty(t, launchCommand)
	assert.NotContains(t, launchCommand, "tmux new-session", "ccav3 launch should not be wrapped in tmux")
}

func TestCreateSandboxRunsBeforeCLIStartBeforeLaunch(t *testing.T) {
	var cliStarted atomic.Bool
	backend := &mockBackend{
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			if strings.Contains(req.Args[1], "dist-cca-v3/index.js") {
				cliStarted.Store(true)
			}
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	_, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		ActorID:       1,
		UseCcav3:      true,
		EventFileJSON: "{}",
		BeforeCLIStart: func(ctx context.Context, sandboxID string) error {
			require.Equal(t, "sb-test-123", sandboxID)
			require.False(t, cliStarted.Load())
			return nil
		},
		StdinSecrets: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-token",
			"GITHUB_TOKEN":             "git-token",
		},
	})

	require.NoError(t, err)
	assert.True(t, cliStarted.Load())
}

func TestExecCopilotCLISkipsServiceCloneForCcav3Resume(t *testing.T) {
	var cloneCalled atomic.Bool
	var getCalls atomic.Int32
	backend := &mockBackend{
		getFunc: func(ctx context.Context, id string) (*sandboxInstance, error) {
			getCalls.Add(1)
			return &sandboxInstance{ID: id, State: "Running"}, nil
		},
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			require.Equal(t, "sb-existing", sb.ID)
			require.Equal(t, "sh", req.Command)
			require.Len(t, req.Args, 2)
			if strings.Contains(req.Args[1], "git clone") {
				cloneCalled.Store(true)
			}
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			require.Equal(t, uint64(1), actorID)
			return backend, nil
		},
	}

	err := svc.ExecCopilotCLI(context.Background(), "sb-existing", 1, "owner/repo", "fix it", nil, nil, "{}", map[string]string{
		"GITHUB_COPILOT_API_TOKEN": "api-token",
		"GITHUB_TOKEN":             "git-token",
	}, true)

	require.NoError(t, err)
	assert.False(t, cloneCalled.Load(), "expected resumed ccav3 job to start without sandbox setup clone")
	assert.GreaterOrEqual(t, getCalls.Load(), int32(2), "expected resume to check readiness and then fetch the sandbox for exec")
}

func TestCreateSandboxCleansUpWhenTmuxLaunchFails(t *testing.T) {
	var deleteCalled atomic.Bool
	backend := &mockBackend{
		executeFunc: func(ctx context.Context, sb *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			if isTmuxLaunchCommand(req.Args[1]) {
				return &sandboxsdk.ExecCommandResponse{ExitCode: 127, Stderr: "tmux not found in sandbox"}, nil
			}
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
		deleteFunc: func(ctx context.Context, id string) error {
			deleteCalled.Store(true)
			return nil
		},
	}
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockMCPConfigurationForRepository = func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
		return &sweagentdTwirp.MCPConfigurationForRepositoryResponse{IsMcpEnabled: false}, nil
	}
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		ghTwirp:  ghTwirp,
		backendFactory: func(actorID uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	_, err := svc.CreateSandbox(context.Background(), &CreateSandboxParams{
		RepositoryNWO: "owner/repo",
		ActorID:       1,
		EnvironmentVariables: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": "api-token",
			"GITHUB_COPILOT_GIT_TOKEN": "git-token",
			"GITHUB_TOKEN":             "api-token",
		},
	})

	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to start CLI")
	assert.True(t, deleteCalled.Load(), "expected the sandbox to be cleaned up after CLI launch failure")
}

func TestBuildTmuxLaunchCommand(t *testing.T) {
	command := buildTmuxLaunchCommand("cd '/workspaces/repo' && copilot --remote --foo 'bar baz'")

	assert.Equal(t, "tmux new-session -d -s copilot 'cd '\\''/workspaces/repo'\\'' && copilot --remote --foo '\\''bar baz'\\'''", command)
}

func isTmuxLaunchCommand(command string) bool {
	return strings.Contains(command, "tmux new-session -d -s copilot")
}

func TestDeleteSandbox(t *testing.T) {
	svc := &Service{
		obsv:     observability.NewNoopExporters(),
		ffClient: featureflags.NewNoopClient(nil),
		opts:     ServiceOpts{UseDockerBackend: true},
	}

	err := svc.DeleteSandbox(context.Background(), "test-sb-id", 1)
	// Docker backend creates a real Docker client which may fail without a daemon,
	// but the method should not panic.
	if err != nil {
		// Either "sandbox backend" or Docker connection error is acceptable
		assert.Error(t, err)
	}
}

func TestBuildCreateSandboxOptionsAddsScopeLabels(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters(), ffClient: featureflags.NewNoopClient(nil)}
	params := &CreateSandboxParams{
		RepositoryID: 42,
		AgentID:      3,
	}

	opts := svc.buildCreateSandboxOptions(context.Background(), params, map[string]string{})

	assert.Equal(t, map[string]string{
		sandboxAgentIDLabel:      "3",
		sandboxRepositoryIDLabel: "42",
	}, opts.Labels)
}

func TestBuildCreateSandboxOptionsOmitsRepositoryAgentSecrets(t *testing.T) {
	// TODO: Re-enable agent secrets configuration once we have credential
	// isolation in place, so the agent doesn't have direct access to those
	// secrets. This test should then assert that the secrets are configured.
	svc := &Service{obsv: observability.NewNoopExporters(), ffClient: featureflags.NewNoopClient(nil)}
	params := &CreateSandboxParams{
		RepositoryNWO: "github/repo",
	}

	opts := svc.buildCreateSandboxOptions(context.Background(), params, map[string]string{})

	assert.Nil(t, opts.Repositories)
}

func TestBuildCreateSandboxOptionsOmitsRepositoriesWithoutRepository(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters(), ffClient: featureflags.NewNoopClient(nil)}

	opts := svc.buildCreateSandboxOptions(context.Background(), &CreateSandboxParams{}, map[string]string{})

	assert.Nil(t, opts.Repositories)
}

func TestWaitForReady_AlreadyRunning(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(ctx context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{ID: id, State: "Running"}, nil
		},
	}

	svc := &Service{obsv: observability.NewNoopExporters()}
	err := svc.waitForReady(context.Background(), backend, "sb-123")
	require.NoError(t, err)
}

func TestWaitForReady_FailedState(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(ctx context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{ID: id, State: "Failed"}, nil
		},
	}

	svc := &Service{obsv: observability.NewNoopExporters()}
	err := svc.waitForReady(context.Background(), backend, "sb-123")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "terminal state")
}

func TestLaunchBackendBuildsExecSandboxFromCreateResponse(t *testing.T) {
	backend := &launchBackend{
		execClient: sandboxsdk.NewClient(""),
	}

	sb := backend.sandboxInstanceFromProto(&launchsandbox.SandboxProto{
		Id:    "sb-123",
		State: "Running",
		Labels: map[string]string{
			sandboxAgentIDLabel:      "3",
			sandboxRepositoryIDLabel: "42",
		},
		Token: "sandbox-token",
		Urls: &launchsandbox.SandboxURLs{
			CommandUrl:   "https://example.com/execute",
			StreamingUrl: "wss://example.com/stream",
		},
	})

	require.NotNil(t, sb)
	assert.Equal(t, "sb-123", sb.ID)
	assert.Equal(t, "42", sb.Labels[sandboxRepositoryIDLabel])
	assert.Equal(t, "3", sb.Labels[sandboxAgentIDLabel])
	assert.NotNil(t, sb.execSandbox)
}

func TestLaunchBackendRequiresCompleteExecCredentials(t *testing.T) {
	backend := &launchBackend{
		execClient: sandboxsdk.NewClient(""),
	}

	sb := backend.sandboxInstanceFromProto(&launchsandbox.SandboxProto{
		Id:    "sb-123",
		State: "Running",
		Token: "sandbox-token",
	})

	require.NotNil(t, sb)
	assert.Nil(t, sb.execSandbox)
}

func TestLaunchBackendGetSandboxRequestsToken(t *testing.T) {
	var gotReq *launchsandbox.GetSandboxRequest
	backend := &launchBackend{
		sandboxClient: &launchSandboxServiceStub{
			getSandboxFunc: func(ctx context.Context, req *launchsandbox.GetSandboxRequest) (*launchsandbox.GetSandboxResponse, error) {
				gotReq = req
				sb := &launchsandbox.SandboxProto{
					Id:    req.GetSandboxId(),
					State: "Running",
				}
				if req.GetIncludeToken() {
					sb.Token = "sandbox-token"
					sb.Urls = &launchsandbox.SandboxURLs{
						CommandUrl:   "https://example.com/execute",
						StreamingUrl: "wss://example.com/stream",
					}
				}
				return &launchsandbox.GetSandboxResponse{Sandbox: sb}, nil
			},
		},
		execClient: sandboxsdk.NewClient(""),
		actor:      &launchsandbox.ActorIdentity{Id: 123},
	}

	sb, err := backend.getSandbox(context.Background(), "sb-123")

	require.NoError(t, err)
	require.NotNil(t, gotReq)
	assert.Equal(t, "sb-123", gotReq.GetSandboxId())
	assert.True(t, gotReq.GetIncludeToken())
	assert.Equal(t, uint64(123), gotReq.GetActor().GetId())
	require.NotNil(t, sb)
	assert.NotNil(t, sb.execSandbox)
}

func TestLaunchSandboxClientDoesNotRetryCreateSandbox(t *testing.T) {
	var requests int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&requests, 1)
		http.Error(w, "launch unavailable", http.StatusInternalServerError)
	}))
	defer server.Close()

	svc := &Service{
		obsv: observability.NewNoopExporters(),
		opts: ServiceOpts{
			LaunchTwirpBaseURL: server.URL,
			LaunchTwirpHMACKey: "secret",
		},
	}

	client, err := svc.newLaunchSandboxClient()
	require.NoError(t, err)

	_, err = client.CreateSandbox(context.Background(), &launchsandbox.CreateSandboxRequest{})

	require.Error(t, err)
	assert.Equal(t, int32(1), atomic.LoadInt32(&requests))
}

func TestLaunchSandboxClientForwardsHeaders(t *testing.T) {
	var gotUserAgent, gotRequestID string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotUserAgent = r.Header.Get("User-Agent")
		gotRequestID = r.Header.Get(headers.GitHubRequestID)
		http.Error(w, "launch unavailable", http.StatusInternalServerError)
	}))
	defer server.Close()

	svc := &Service{
		obsv: observability.NewNoopExporters(),
		opts: ServiceOpts{
			LaunchTwirpBaseURL: server.URL,
			LaunchTwirpHMACKey: "secret",
		},
	}

	client, err := svc.newLaunchSandboxClient()
	require.NoError(t, err)

	ctx := requestid.WithGitHubRequestID(context.Background(), "req-123")
	_, err = client.CreateSandbox(ctx, &launchsandbox.CreateSandboxRequest{})

	require.Error(t, err)
	assert.Equal(t, "sweagentd", gotUserAgent)
	assert.Equal(t, "req-123", gotRequestID)
}

func TestBuildLifecyclePolicyDefaultDisablesAutoSuspend(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters()}

	policy := svc.buildLifecyclePolicy(&CreateSandboxParams{})
	data, err := proto.Marshal(policy)
	require.NoError(t, err)

	var decoded launchsandbox.LifecyclePolicy
	err = proto.Unmarshal(data, &decoded)
	require.NoError(t, err)

	require.NotNil(t, decoded.AutoSuspend)
	assert.False(t, decoded.AutoSuspend.Enabled)
}

func TestBuildLifecyclePolicyIncludesAutoSuspendAndAutoDelete(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters()}

	policy := svc.buildLifecyclePolicy(&CreateSandboxParams{
		Lifecycle: &LifecycleParams{
			AutoSuspendEnabled:        true,
			AutoSuspendIdleTimeoutMin: 5,
			AutoDeleteAfterMin:        59,
		},
	})
	data, err := proto.Marshal(policy)
	require.NoError(t, err)

	var decoded launchsandbox.LifecyclePolicy
	err = proto.Unmarshal(data, &decoded)
	require.NoError(t, err)

	require.NotNil(t, decoded.AutoSuspend)
	assert.True(t, decoded.AutoSuspend.Enabled)
	assert.Equal(t, int32(5), decoded.AutoSuspend.IdleTimeout)
	require.NotNil(t, decoded.AutoDelete)
	assert.Equal(t, int32(59), decoded.AutoDelete.DeleteAfter)
}

func TestBuildEgressPolicy_FirewallDisabled(t *testing.T) {
	svc := NewService(observability.NewNoopExporters(), nil, nil, ServiceOpts{})
	params := &CreateSandboxParams{FirewallEnabled: false}

	policy := svc.buildEgressPolicy(params)
	assert.Equal(t, "Allow", policy.DefaultAction)
	assert.Equal(t, trafficInspectionFull, policy.TrafficInspection)
	assert.Empty(t, policy.HostRules)
}

func TestBuildEgressPolicy_FirewallEnabledWithDefaults(t *testing.T) {
	svc := NewService(observability.NewNoopExporters(), nil, nil, ServiceOpts{})
	params := &CreateSandboxParams{
		FirewallEnabled:         true,
		FirewallUseDefaultRules: true,
	}

	policy := svc.buildEgressPolicy(params)
	assert.Equal(t, "Deny", policy.DefaultAction)
	assert.Equal(t, trafficInspectionFull, policy.TrafficInspection)
	// Default rule patterns are loaded from the embedded YAML at package init.
	assert.Len(t, policy.HostRules, len(requiredHostRules)+len(defaultRuleHostPatterns))
	// Spot-check entries from across the bundled rule files.
	assertHostRule(t, policy, "raw.githubusercontent.com")
	assertHostRule(t, policy, "proxy.golang.org")
	assertHostRule(t, policy, "*.githubusercontent.com")
}

func TestBuildEgressPolicy_FirewallEnabledWithCustomRules(t *testing.T) {
	svc := NewService(observability.NewNoopExporters(), nil, nil, ServiceOpts{})
	params := &CreateSandboxParams{
		FirewallEnabled:         true,
		FirewallUseDefaultRules: true,
		FirewallAllowedRules:    []string{"*.example.com", "api.custom.io"},
	}

	policy := svc.buildEgressPolicy(params)
	assert.Equal(t, "Deny", policy.DefaultAction)
	assert.Len(t, policy.HostRules, len(requiredHostRules)+len(defaultRuleHostPatterns)+2)
	assertHostRule(t, policy, "*.example.com")
	assertHostRule(t, policy, "api.custom.io")
}

func TestBuildEgressPolicy_FirewallEnabledNoDefaults(t *testing.T) {
	svc := NewService(observability.NewNoopExporters(), nil, nil, ServiceOpts{})
	params := &CreateSandboxParams{
		FirewallEnabled:         true,
		FirewallUseDefaultRules: false,
		FirewallAllowedRules:    []string{"*.example.com"},
	}

	policy := svc.buildEgressPolicy(params)
	assert.Equal(t, "Deny", policy.DefaultAction)
	assert.Len(t, policy.HostRules, len(requiredHostRules)+1)
	assertHostRule(t, policy, "github.com")
	assertHostRule(t, policy, "api.githubcopilot.com")
	assertHostRule(t, policy, "*.example.com")
}

func TestBuildEgressPolicy_FirewallEnabledAlwaysAllowsSetupAndRemoteHosts(t *testing.T) {
	svc := NewService(observability.NewNoopExporters(), nil, nil, ServiceOpts{
		GitHubServerURL:       "https://github.enterprise.test",
		CopilotAPIURL:         "https://api.copilot.test",
		MissionControlBaseURL: "https://mc.copilot.test/agents",
	})
	params := &CreateSandboxParams{
		FirewallEnabled:         true,
		FirewallUseDefaultRules: false,
		FirewallAllowedRules:    []string{"api.copilot.test", "custom.test"},
	}

	policy := svc.buildEgressPolicy(params)
	assert.Equal(t, "Deny", policy.DefaultAction)
	assertHostRule(t, policy, "github.enterprise.test")
	assertHostRule(t, policy, "api.copilot.test")
	assertHostRule(t, policy, "mc.copilot.test")
	assertHostRule(t, policy, "custom.test")

	count := 0
	for _, rule := range policy.HostRules {
		if rule.Pattern == "api.copilot.test" {
			count++
		}
	}
	assert.Equal(t, 1, count)
}

func TestBuildEgressPolicy_FirewallEnabledIncludesRequiredAllowListHosts(t *testing.T) {
	svc := NewService(observability.NewNoopExporters(), nil, nil, ServiceOpts{
		RequiredFirewallAllowList: "raw.githubusercontent.com,https://codeload.github.com/,*.example.org",
	})
	params := &CreateSandboxParams{
		FirewallEnabled:         true,
		FirewallUseDefaultRules: false,
	}

	policy := svc.buildEgressPolicy(params)
	assert.Equal(t, "Deny", policy.DefaultAction)
	assertHostRule(t, policy, "raw.githubusercontent.com")
	assertHostRule(t, policy, "codeload.github.com")
	assertHostRule(t, policy, "*.example.org")
}

func assertHostRule(t *testing.T, policy *launchsandbox.EgressPolicy, pattern string) {
	t.Helper()
	for _, rule := range policy.HostRules {
		if rule.Pattern == pattern {
			assert.Equal(t, "Allow", rule.Action)
			return
		}
	}
	assert.Failf(t, "missing host rule", "expected host rule %q", pattern)
}

func TestGetSandboxInfoReadsLabels(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(_ context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{
				ID:    id,
				State: "Running",
				Labels: map[string]string{
					sandboxRepositoryIDLabel: "42",
					sandboxAgentIDLabel:      "7",
				},
			}, nil
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}
	info, err := svc.GetSandboxInfo(context.Background(), "sb-1", 1)
	require.NoError(t, err)
	assert.Equal(t, int64(42), info.RepositoryID)
	assert.Equal(t, int64(7), info.AgentID)
}

func TestGetSandboxInfoMissingLabels(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(_ context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{ID: id, State: "Running", Labels: map[string]string{}}, nil
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}
	_, err := svc.GetSandboxInfo(context.Background(), "sb-1", 1)
	require.Error(t, err)
	assert.ErrorIs(t, err, ErrSandboxLabelsMissing)
}

func TestGetSandboxInfoUnparseableLabels(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(_ context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{
				ID:    id,
				State: "Running",
				Labels: map[string]string{
					sandboxRepositoryIDLabel: "not-a-number",
					sandboxAgentIDLabel:      "7",
				},
			}, nil
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}
	_, err := svc.GetSandboxInfo(context.Background(), "sb-1", 1)
	require.Error(t, err)
	assert.ErrorIs(t, err, ErrSandboxLabelsMissing)
}

func TestGetSandboxStateReturnsBackendState(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(_ context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{ID: id, State: "Suspended"}, nil
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}
	state, err := svc.GetSandboxState(context.Background(), "sb-1", 1)
	require.NoError(t, err)
	assert.Equal(t, "Suspended", state)
}

func TestGetSandboxStateBackendErrorBubbles(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(_ context.Context, _ string) (*sandboxInstance, error) {
			return nil, goerrors.New("launch unavailable")
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}
	_, err := svc.GetSandboxState(context.Background(), "sb-1", 1)
	require.Error(t, err)
}

func TestResumeCopilotCLIRejectsBadEnv(t *testing.T) {
	svc := &Service{obsv: observability.NewNoopExporters()}
	cases := []struct {
		name string
		env  map[string]string
	}{
		{name: "empty", env: map[string]string{}},
		{name: "invalid-name", env: map[string]string{"GITHUB TOKEN": "x"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := svc.ResumeCopilotCLI(context.Background(), "sb-1", 1, "owner/repo", tc.env)
			require.Error(t, err)
		})
	}
}

func TestBuildCLIResumeWrapperCommand_NoSecretsInCommand(t *testing.T) {
	cmd := buildCLIResumeWrapperCommand("/workspaces/repo", "copilot --remote --continue")

	// Hard safety guarantee: the wrapper builder takes only workDir and the
	// copilot invocation — never env values — so secrets cannot end up in
	// the command string even by accident. Sanity-check that nothing looks
	// like an inlined credential.
	assert.NotContains(t, cmd, "GITHUB_TOKEN=")
	assert.NotContains(t, cmd, "GITHUB_COPILOT_API_TOKEN=")

	// Structural guarantees from the threat model:
	assert.Contains(t, cmd, "tmux kill-server", "must kill old tmux server first so its stale env is not reused")
	assert.Contains(t, cmd, `cd '\''/workspaces/repo'\'' && exec copilot --remote --continue`)
	assert.Contains(t, cmd, "tmux new-session -d -s copilot")
}

func TestResumeCopilotCLIPassesEnvViaExecCommandEnvironment(t *testing.T) {
	const apiToken = "fresh-token-api"
	const gitToken = "fresh-token-git"

	var execCmds []string
	var execEnvs []map[string]string

	backend := &mockBackend{
		getFunc: func(_ context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{ID: id, State: "Running"}, nil
		},
		executeFunc: func(_ context.Context, _ *sandboxInstance, req *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			execCmds = append(execCmds, req.Args[1])
			execEnvs = append(execEnvs, req.Environment)
			return &sandboxsdk.ExecCommandResponse{ExitCode: 0}, nil
		},
	}

	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}

	err := svc.ResumeCopilotCLI(context.Background(), "sb-1", 1, "owner/repo", map[string]string{
		"GITHUB_COPILOT_API_TOKEN": apiToken,
		"GITHUB_COPILOT_GIT_TOKEN": gitToken,
		"GITHUB_TOKEN":             gitToken,
		"REMOTE_JSON_RPC":          "true",
	})
	require.NoError(t, err)

	require.Len(t, execCmds, 1, "expected exactly one exec for CLI resume relaunch")
	wrapper := execCmds[0]
	for _, secret := range []string{apiToken, gitToken} {
		assert.NotContains(t, wrapper, secret, "secret token must not appear in wrapper command args")
	}
	assert.Contains(t, wrapper, "tmux kill-server", "wrapper must kill old tmux server before relaunch")
	assert.Contains(t, wrapper, "tmux new-session -d -s copilot")
	assert.Contains(t, wrapper, "copilot --remote --continue")

	require.Len(t, execEnvs, 1)
	env := execEnvs[0]
	assert.Equal(t, apiToken, env["GITHUB_COPILOT_API_TOKEN"])
	assert.Equal(t, gitToken, env["GITHUB_COPILOT_GIT_TOKEN"])
	assert.Equal(t, gitToken, env["GITHUB_TOKEN"])
	assert.Equal(t, "true", env["REMOTE_JSON_RPC"])
}

func TestResumeCopilotCLIBubblesExecError(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(_ context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{ID: id, State: "Running"}, nil
		},
		executeFunc: func(context.Context, *sandboxInstance, *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			return nil, assert.AnError
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}
	err := svc.ResumeCopilotCLI(context.Background(), "sb-1", 1, "owner/repo", map[string]string{
		"GITHUB_TOKEN": "tok",
	})
	require.Error(t, err)
}

func TestResumeCopilotCLINonzeroExitWrapsErrCLIExitFailure(t *testing.T) {
	backend := &mockBackend{
		getFunc: func(_ context.Context, id string) (*sandboxInstance, error) {
			return &sandboxInstance{ID: id, State: "Running"}, nil
		},
		executeFunc: func(context.Context, *sandboxInstance, *sandboxsdk.ExecCommandRequest) (*sandboxsdk.ExecCommandResponse, error) {
			return &sandboxsdk.ExecCommandResponse{ExitCode: 1, Stderr: "boom"}, nil
		},
	}
	svc := &Service{
		obsv: observability.NewNoopExporters(),
		backendFactory: func(uint64) (sandboxBackend, error) {
			return backend, nil
		},
	}
	err := svc.ResumeCopilotCLI(context.Background(), "sb-1", 1, "owner/repo", map[string]string{
		"GITHUB_TOKEN": "tok",
	})
	require.Error(t, err)
	assert.ErrorIs(t, err, ErrCLIExitFailure)
}
