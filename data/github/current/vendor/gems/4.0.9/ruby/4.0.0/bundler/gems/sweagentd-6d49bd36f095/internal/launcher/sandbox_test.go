package launcher

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sandbox"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockSandboxService implements sandboxService for testing.
type mockSandboxService struct {
	createFunc  func(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error)
	stopFunc    func(ctx context.Context, sandboxID string, actorID uint64) error
	resumeFunc  func(ctx context.Context, sandboxID string, actorID uint64) error
	execCLIFunc func(ctx context.Context, sandboxID string, actorID uint64) error

	// captured values for assertions
	lastCreateParams  *sandbox.CreateSandboxParams
	lastStopID        string
	lastStopActorID   uint64
	lastResumeID      string
	lastResumeActorID uint64
	lastExecEventJSON string
	lastExecRepoNWO   string
	lastExecEnvVars   map[string]string
	lastExecSecrets   map[string]string
	lastExecUseCcav3  bool

	createCalled  bool
	resumeCalled  bool
	execCLICalled bool
	stopCalled    bool
}

func (m *mockSandboxService) CreateSandbox(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
	m.createCalled = true
	m.lastCreateParams = params
	if m.createFunc != nil {
		return m.createFunc(ctx, params)
	}
	return &sandbox.CreateSandboxResult{SandboxID: "sb-test-123"}, nil
}

func (m *mockSandboxService) StopSandbox(ctx context.Context, sandboxID string, actorID uint64) error {
	m.stopCalled = true
	m.lastStopID = sandboxID
	m.lastStopActorID = actorID
	if m.stopFunc != nil {
		return m.stopFunc(ctx, sandboxID, actorID)
	}
	return nil
}

func (m *mockSandboxService) ResumeSandbox(ctx context.Context, sandboxID string, actorID uint64) error {
	m.resumeCalled = true
	m.lastResumeID = sandboxID
	m.lastResumeActorID = actorID
	if m.resumeFunc != nil {
		return m.resumeFunc(ctx, sandboxID, actorID)
	}
	return nil
}

func (m *mockSandboxService) ExecCopilotCLI(ctx context.Context, sandboxID string, actorID uint64, repoNWO, problemStatement string, cliFlags []string, envVars map[string]string, eventJSON string, stdinSecrets map[string]string, useCcav3 bool) error {
	m.execCLICalled = true
	m.lastExecRepoNWO = repoNWO
	m.lastExecEnvVars = envVars
	m.lastExecEventJSON = eventJSON
	m.lastExecSecrets = stdinSecrets
	m.lastExecUseCcav3 = useCcav3
	if m.execCLIFunc != nil {
		return m.execCLIFunc(ctx, sandboxID, actorID)
	}
	return nil
}

func agentInputsFromEventJSON(t *testing.T, eventJSON string) map[string]string {
	t.Helper()

	var event struct {
		Inputs map[string]string `json:"inputs"`
	}
	require.NoError(t, json.Unmarshal([]byte(eventJSON), &event))

	var env map[string]string
	require.NoError(t, json.Unmarshal([]byte(event.Inputs["COPILOT_AGENT_INPUTS"]), &env))
	return env
}

// mockTokenMinter implements sandboxTokenMinter for testing.
type mockTokenMinter struct {
	userToken     string
	serverToken   string
	userErr       error
	serverErr     error
	lastUserReq   *sweagentdTwirp.MintUserToServerTokenForRepoRequest
	lastServerReq *sweagentdTwirp.MintServerToServerTokenForRepoRequest
	userCalls     int
	serverCalls   int
}

func (m *mockTokenMinter) MintUserToServerTokenForRepo(_ context.Context, req *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error) {
	m.userCalls++
	m.lastUserReq = req
	if m.userErr != nil {
		return nil, m.userErr
	}
	tok := m.userToken
	if tok == "" {
		tok = "test-user-token"
	}
	return &sweagentdTwirp.MintUserToServerTokenForRepoResponse{Token: tok}, nil
}

func (m *mockTokenMinter) MintServerToServerTokenForRepo(_ context.Context, req *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
	m.serverCalls++
	m.lastServerReq = req
	if m.serverErr != nil {
		return nil, m.serverErr
	}
	tok := m.serverToken
	if tok == "" {
		tok = "test-server-token"
	}
	return &sweagentdTwirp.MintServerToServerTokenForRepoResponse{Token: tok}, nil
}

func newTestSandboxLauncher(svc sandboxService, opts *SandboxLauncherOpts) *SandboxLauncher {
	return newTestSandboxLauncherWithMinter(svc, &mockTokenMinter{}, opts)
}

func newTestSandboxLauncherWithMinter(svc sandboxService, minter sandboxTokenMinter, opts *SandboxLauncherOpts) *SandboxLauncher {
	if opts == nil {
		opts = &SandboxLauncherOpts{}
	}
	return NewSandboxLauncher(
		observability.NewNoopExporters(),
		featureflags.NewNoopClient(nil),
		svc,
		minter,
		*opts,
	)
}

func TestSandboxLauncher_LauncherType(t *testing.T) {
	launcher := newTestSandboxLauncher(&mockSandboxService{}, nil)
	assert.Equal(t, TypeSandbox, launcher.LauncherType())
}

func TestSandboxLauncher_LaunchAgent(t *testing.T) {
	mock := &mockSandboxService{}
	minter := &mockTokenMinter{
		userToken:   "user-token",
		serverToken: "server-token",
	}
	launcher := newTestSandboxLauncherWithMinter(mock, minter, nil)

	opts := &LaunchAgentOpts{
		GitHubRepo:        "org/repo",
		GitHubRepoID:      42,
		GitHubRepoOwnerID: 7,
		BranchName:        "copilot/fix-bug",
		ActorID:           100,
		ProblemStatement:  "Fix the tests",
		Nonce:             "job-nonce",
		Agent:             agenticapptest.NewTestCopilotWithID(t, 837),
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	assert.Equal(t, "sb-test-123", result.ComputeID)
	assert.False(t, result.CustomSetupSteps)
	assert.Empty(t, result.RunsOn)

	// Verify params were translated correctly.
	p := mock.lastCreateParams
	require.NotNil(t, p)
	assert.Equal(t, uint64(42), p.RepositoryID)
	assert.Equal(t, uint64(7), p.RepositoryOwnerID)
	assert.Equal(t, "org/repo", p.RepositoryNWO)
	assert.Equal(t, "copilot/fix-bug", p.BranchName)
	assert.Equal(t, uint64(100), p.ActorID)
	assert.Equal(t, int64(837), p.AgentID)
	assert.Equal(t, "Fix the tests", p.ProblemStatement)
	require.NotNil(t, p.Lifecycle)
	assert.True(t, p.Lifecycle.AutoSuspendEnabled)
	assert.Equal(t, int32(60), p.Lifecycle.AutoSuspendIdleTimeoutMin)
	assert.Equal(t, int32(59), p.Lifecycle.AutoDeleteAfterMin)

	// Verify runtime auth tokens are not in the inherited VM env. The git token
	// is delivered through stdin so ccav3 can own repository setup.
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_COPILOT_API_TOKEN")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_COPILOT_GIT_TOKEN")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_TOKEN")
	assert.NotContains(t, p.EnvironmentVariables, "COPILOT_JOB_NONCE")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_VERIFICATION_TOKEN")
	assert.Equal(t, "user-token", p.StdinSecrets["GITHUB_COPILOT_API_TOKEN"])
	assert.Equal(t, "server-token", p.StdinSecrets["GITHUB_TOKEN"])
	assert.Equal(t, "job-nonce", p.StdinSecrets["COPILOT_JOB_NONCE"])
	assert.Equal(t, "STANDALONE", p.EnvironmentVariables["COPILOT_AGENT_RUNNER_TYPE"])
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_ACTIONS")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_EVENT_NAME")

	// Verify minter was called with the expected requests.
	require.NotNil(t, minter.lastUserReq)
	assert.Equal(t, uint64(100), minter.lastUserReq.UserId)
	assert.Equal(t, uint64(42), minter.lastUserReq.RepositoryId)
	assert.Equal(t, int64(837), minter.lastUserReq.AgentId)
	assert.Equal(t, sandboxLaunchTokenPermissions, minter.lastUserReq.Permissions)

	require.NotNil(t, minter.lastServerReq)
	assert.Equal(t, uint64(42), minter.lastServerReq.RepositoryId)
	assert.Equal(t, int64(837), minter.lastServerReq.AgentId)
	assert.Equal(t, sandboxGitTokenPermissions, minter.lastServerReq.Permissions)
}

func TestSandboxLauncher_LaunchAgentCallsBeforeAgentStart(t *testing.T) {
	mock := &mockSandboxService{
		createFunc: func(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
			require.NotNil(t, params.BeforeCLIStart)
			require.NoError(t, params.BeforeCLIStart(ctx, "sb-test-123"))
			return &sandbox.CreateSandboxResult{SandboxID: "sb-test-123"}, nil
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	var hookResult *LaunchResult
	opts := &LaunchAgentOpts{
		GitHubRepo:   "org/repo",
		GitHubRepoID: 42,
		ActorID:      100,
		Agent:        agenticapptest.NewTestCopilot(t),
		BeforeAgentStart: func(ctx context.Context, result *LaunchResult) error {
			hookResult = result
			return nil
		},
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	require.NotNil(t, hookResult)
	assert.Equal(t, "sb-test-123", hookResult.ComputeID)
	assert.Equal(t, "sb-test-123", result.ComputeID)
}

func TestSandboxLauncher_LaunchAgent_UserTokenMintError(t *testing.T) {
	mock := &mockSandboxService{}
	minter := &mockTokenMinter{userErr: goerrors.New("mint failed")}
	launcher := newTestSandboxLauncherWithMinter(mock, minter, nil)

	opts := &LaunchAgentOpts{
		Agent: agenticapptest.NewTestCopilot(t),
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to mint sandbox launch token")
	assert.Nil(t, mock.lastCreateParams)
}

func TestSandboxLauncher_LaunchAgent_GitTokenMintError(t *testing.T) {
	mock := &mockSandboxService{}
	minter := &mockTokenMinter{serverErr: goerrors.New("mint failed")}
	launcher := newTestSandboxLauncherWithMinter(mock, minter, nil)

	opts := &LaunchAgentOpts{
		Agent: agenticapptest.NewTestCopilot(t),
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "failed to mint sandbox git token")
	assert.Nil(t, mock.lastCreateParams)
}

func TestSandboxLauncher_LaunchAgent_Error(t *testing.T) {
	mock := &mockSandboxService{
		createFunc: func(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
			return nil, goerrors.New("backend failure")
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		Agent: agenticapptest.NewTestCopilot(t),
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "sandbox launch failed")
	assert.Contains(t, err.Error(), "backend failure")
}

func TestSandboxLauncher_LaunchAgent_FirewallFromRepoConfig(t *testing.T) {
	mock := &mockSandboxService{}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		Agent: agenticapptest.NewTestCopilot(t),
		RepoConfig: &sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsFirewallEnabled:             true,
			ShouldFirewallUseDefaultRules: true,
			FirewallAllowedRules:          []string{"*.example.com"},
		},
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	p := mock.lastCreateParams
	assert.True(t, p.FirewallEnabled)
	assert.True(t, p.FirewallUseDefaultRules)
	assert.Equal(t, []string{"*.example.com"}, p.FirewallAllowedRules)
}

func TestSandboxLauncher_LaunchAgent_FirewallDefault(t *testing.T) {
	mock := &mockSandboxService{}
	// Enable firewall by default via config.
	launcher := newTestSandboxLauncher(mock, &SandboxLauncherOpts{
		ExternalLauncherOpts: ExternalLauncherOpts{AgentLauncherOpts: AgentLauncherOpts{
			AgentFirewallEnabledDefault: true,
		}},
	})

	opts := &LaunchAgentOpts{
		Agent: agenticapptest.NewTestCopilot(t),
		// No RepoConfig — should fall back to default.
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	p := mock.lastCreateParams
	assert.True(t, p.FirewallEnabled)
	assert.True(t, p.FirewallUseDefaultRules)
}

func TestSandboxLauncher_TerminateAgent(t *testing.T) {
	mock := &mockSandboxService{}
	minter := &mockTokenMinter{}
	launcher := newTestSandboxLauncherWithMinter(mock, minter, nil)

	err := launcher.TerminateAgent(context.Background(), TerminateAgentOpts{
		ComputeID: "sb-to-stop",
		ActorID:   77,
		OwnerID:   99,
		RepoID:    42,
		AgentID:   837,
	})
	require.NoError(t, err)

	// TerminateAgent stops (suspends) the VM rather than deleting it.
	assert.Equal(t, "sb-to-stop", mock.lastStopID)
	assert.Equal(t, uint64(77), mock.lastStopActorID)
	assert.Zero(t, minter.userCalls)
	assert.Zero(t, minter.serverCalls)
}

func TestSandboxLauncher_TerminateAgent_Error(t *testing.T) {
	mock := &mockSandboxService{
		stopFunc: func(ctx context.Context, sandboxID string, actorID uint64) error {
			return goerrors.New("stop failed")
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	err := launcher.TerminateAgent(context.Background(), TerminateAgentOpts{
		ComputeID: "sb-123",
	})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "stop failed")
}

func TestSandboxLauncher_TerminateAgent_SandboxNotRunning(t *testing.T) {
	mock := &mockSandboxService{
		stopFunc: func(ctx context.Context, sandboxID string, actorID uint64) error {
			return goerrors.New(`twirp error internal: unexpected status code 409: {"title":"SandboxNotRunning","status":409}`)
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	err := launcher.TerminateAgent(context.Background(), TerminateAgentOpts{
		ComputeID: "sb-already-stopped",
		ActorID:   77,
	})
	require.NoError(t, err, "SandboxNotRunning should be treated as success")
}

func TestSandboxLauncher_LaunchAgent_Resume_Success(t *testing.T) {
	mock := &mockSandboxService{}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		ActorID:                   100,
		PreviousComputeID:         "sb-previous-456",
		PreviousComputeLaunchedAt: time.Now().Unix(),
		Agent:                     agenticapptest.NewTestCopilot(t),
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	// Should resume the previous sandbox, not create a new one.
	assert.Equal(t, "sb-previous-456", result.ComputeID)
	assert.True(t, mock.resumeCalled)
	assert.False(t, mock.createCalled)
	assert.Equal(t, "sb-previous-456", mock.lastResumeID)
	assert.Equal(t, uint64(100), mock.lastResumeActorID)
	assert.True(t, mock.execCLICalled)
	assert.True(t, mock.lastExecUseCcav3)
	assert.NotContains(t, mock.lastExecEnvVars, "GITHUB_COPILOT_API_TOKEN")
	assert.NotContains(t, mock.lastExecEnvVars, "GITHUB_TOKEN")
	assert.Equal(t, "test-user-token", mock.lastExecSecrets["GITHUB_COPILOT_API_TOKEN"])
	assert.Equal(t, "test-server-token", mock.lastExecSecrets["GITHUB_TOKEN"])
	assert.Equal(t, "STANDALONE", mock.lastExecEnvVars["COPILOT_AGENT_RUNNER_TYPE"])
	assert.NotContains(t, mock.lastExecEnvVars, "GITHUB_ACTIONS")
	assert.NotContains(t, mock.lastExecEnvVars, "GITHUB_EVENT_NAME")
	assert.NotEmpty(t, mock.lastExecEventJSON)
}

func TestSandboxLauncher_LaunchAgent_Resume_Ccav3OwnsRepositoryPreparation(t *testing.T) {
	mock := &mockSandboxService{}
	minter := &mockTokenMinter{serverToken: "server-token"}
	launcher := newTestSandboxLauncherWithMinter(mock, minter, nil)

	opts := &LaunchAgentOpts{
		GitHubRepo:                "org/repo",
		GitHubRepoID:              42,
		GitHubRepoOwnerID:         7,
		ActorID:                   100,
		PreviousComputeID:         "sb-previous-456",
		PreviousComputeLaunchedAt: time.Now().Unix(),
		Agent:                     agenticapptest.NewTestCopilot(t),
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	assert.True(t, mock.execCLICalled)
	assert.True(t, mock.lastExecUseCcav3)
	assert.Equal(t, "org/repo", mock.lastExecRepoNWO)

	assert.Equal(t, "false", mock.lastExecEnvVars["COPILOT_CCA_V3_USE_EXISTING_WORKSPACE"])
	// GITHUB_WORKSPACE is intentionally not set for ccav3: the runtime SDK-clones
	// the repo itself, so defaulting MCP cwd to a /workspaces/<repo> path that
	// never exists on the sandbox would break MCP server spawning.
	assert.NotContains(t, mock.lastExecEnvVars, "GITHUB_WORKSPACE")
	assert.Equal(t, "server-token", mock.lastExecSecrets["GITHUB_TOKEN"])

	eventInputs := agentInputsFromEventJSON(t, mock.lastExecEventJSON)
	assert.NotContains(t, eventInputs, "GITHUB_TOKEN")
}

func TestSandboxLauncher_LaunchAgent_Resume_Fallback(t *testing.T) {
	mock := &mockSandboxService{
		resumeFunc: func(ctx context.Context, sandboxID string, actorID uint64) error {
			return goerrors.New("sandbox corrupted")
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		ActorID:                   100,
		GitHubRepoID:              42,
		GitHubRepoOwnerID:         7,
		PreviousComputeID:         "sb-corrupt",
		PreviousComputeLaunchedAt: time.Now().Unix(),
		Agent:                     agenticapptest.NewTestCopilot(t),
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	// Resume failed, so a fresh sandbox should have been created.
	assert.Equal(t, "sb-test-123", result.ComputeID)
	assert.True(t, mock.resumeCalled)
	assert.True(t, mock.createCalled)
}

func TestSandboxLauncher_LaunchAgent_NoPreviousComputeID(t *testing.T) {
	mock := &mockSandboxService{}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		// PreviousComputeID is empty — no resume attempt.
		Agent: agenticapptest.NewTestCopilot(t),
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	assert.Equal(t, "sb-test-123", result.ComputeID)
	assert.False(t, mock.resumeCalled)
	assert.True(t, mock.createCalled)
}

func TestSandboxLauncher_LaunchAgent_ErrorClassification(t *testing.T) {
	mock := &mockSandboxService{
		createFunc: func(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
			return nil, goerrors.New("backend failure")
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		Agent: agenticapptest.NewTestCopilot(t),
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.Error(t, err)

	// CreateSandbox errors should be wrapped with ClassifyLaunchError.
	assert.True(t, IsRetriableLaunchError(err), "unknown errors default to retriable")
	assert.Contains(t, err.Error(), "sandbox launch failed")
}

func TestSandboxLauncher_LaunchAgent_Resume_FallbackAlsoFails(t *testing.T) {
	mock := &mockSandboxService{
		resumeFunc: func(ctx context.Context, sandboxID string, actorID uint64) error {
			return goerrors.New("ADC error")
		},
		createFunc: func(ctx context.Context, params *sandbox.CreateSandboxParams) (*sandbox.CreateSandboxResult, error) {
			return nil, goerrors.New("provisioning failure")
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		PreviousComputeID:         "sb-broken",
		PreviousComputeLaunchedAt: time.Now().Unix(),
		Agent:                     agenticapptest.NewTestCopilot(t),
	}

	_, err := launcher.LaunchAgent(context.Background(), opts)
	require.Error(t, err)

	// Both resume and create failed. The create error should be classified.
	assert.True(t, mock.resumeCalled)
	assert.True(t, mock.createCalled)
	assert.Contains(t, err.Error(), "sandbox launch failed")
	assert.Contains(t, err.Error(), "provisioning failure")
}

func TestSandboxLauncher_LaunchAgent_Resume_ExecFailStopsAndFallsBack(t *testing.T) {
	mock := &mockSandboxService{
		// Resume succeeds but ExecCopilotCLI fails.
		execCLIFunc: func(ctx context.Context, sandboxID string, actorID uint64) error {
			return goerrors.New("tmux session failed")
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		ActorID:                   100,
		GitHubRepoID:              42,
		GitHubRepoOwnerID:         7,
		PreviousComputeID:         "sb-exec-fail",
		PreviousComputeLaunchedAt: time.Now().Unix(),
		Agent:                     agenticapptest.NewTestCopilot(t),
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	// Resume succeeded, exec failed → stop the resumed sandbox → fallback to fresh.
	assert.True(t, mock.resumeCalled)
	assert.True(t, mock.execCLICalled)
	assert.True(t, mock.stopCalled, "should stop the resumed sandbox after exec failure")
	assert.Equal(t, "sb-exec-fail", mock.lastStopID)
	assert.True(t, mock.createCalled, "should fall back to CreateSandbox")
	assert.Equal(t, "sb-test-123", result.ComputeID)
}

func TestSandboxLauncher_LaunchAgent_Resume_ExecFailAfterBeforeAgentStartDoesNotFallback(t *testing.T) {
	mock := &mockSandboxService{
		execCLIFunc: func(ctx context.Context, sandboxID string, actorID uint64) error {
			return goerrors.New("tmux session failed")
		},
	}
	launcher := newTestSandboxLauncher(mock, nil)

	hookCalls := 0
	opts := &LaunchAgentOpts{
		ActorID:                   100,
		GitHubRepoID:              42,
		GitHubRepoOwnerID:         7,
		PreviousComputeID:         "sb-exec-fail",
		PreviousComputeLaunchedAt: time.Now().Unix(),
		Agent:                     agenticapptest.NewTestCopilot(t),
		BeforeAgentStart: func(ctx context.Context, result *LaunchResult) error {
			hookCalls++
			assert.Equal(t, "sb-exec-fail", result.ComputeID)
			return nil
		},
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.Error(t, err)
	require.Nil(t, result)

	assert.Equal(t, 1, hookCalls)
	assert.True(t, mock.resumeCalled)
	assert.True(t, mock.execCLICalled)
	assert.True(t, mock.stopCalled, "should stop the resumed sandbox after exec failure")
	assert.False(t, mock.createCalled, "should not duplicate launch bookkeeping on a fresh fallback")
}

func TestSandboxLauncher_LaunchAgent_Resume_SkippedTokenExpiry(t *testing.T) {
	mock := &mockSandboxService{}
	launcher := newTestSandboxLauncher(mock, nil)

	opts := &LaunchAgentOpts{
		ActorID:                   100,
		GitHubRepoID:              42,
		GitHubRepoOwnerID:         7,
		PreviousComputeID:         "sb-expired",
		PreviousComputeLaunchedAt: time.Now().Add(-2 * time.Hour).Unix(), // 2 hours ago
		Agent:                     agenticapptest.NewTestCopilot(t),
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)

	// Tokens expired — should skip resume entirely and create fresh.
	assert.False(t, mock.resumeCalled, "should not attempt resume with expired tokens")
	assert.True(t, mock.createCalled, "should create fresh sandbox")
	assert.Equal(t, "sb-test-123", result.ComputeID)
}

func TestSandboxLauncher_LaunchAgent_Ccav3(t *testing.T) {
	mock := &mockSandboxService{}
	minter := &mockTokenMinter{
		userToken:   "user-token",
		serverToken: "server-token",
	}
	launcher := NewSandboxLauncher(
		observability.NewNoopExporters(),
		featureflags.NewNoopClient(nil),
		mock,
		minter,
		SandboxLauncherOpts{ExternalLauncherOpts: ExternalLauncherOpts{
			AgentLauncherOpts: AgentLauncherOpts{
				AgentCallbackURL:  "https://callback.test",
				CopilotAPIURL:     "https://api.copilot.test",
				UploadsURL:        "https://uploads.test",
				DownloadsURL:      "https://downloads.test",
				SecretScanningURL: "https://secret-scanning.test",
			},
			GitHubServerURL:      "https://github.test",
			CAPIHMACKey:          "hmac-secret",
			CopilotIntegrationID: "integration-secret",
		}},
	)

	opts := &LaunchAgentOpts{
		GitHubRepo:        "org/repo",
		GitHubRepoID:      42,
		GitHubRepoOwnerID: 7,
		GitHubBaseCommit:  "abc123",
		BranchName:        "copilot/fix-bug",
		ActorID:           100,
		ProblemStatement:  "Fix the tests",
		Nonce:             "job-nonce",
		JobID:             "job-123",
		Action:            "task",
		Agent:             agenticapptest.NewTestCopilotWithID(t, 837),
	}

	result, err := launcher.LaunchAgent(context.Background(), opts)
	require.NoError(t, err)
	assert.Equal(t, "sb-test-123", result.ComputeID)
	assert.True(t, mock.createCalled)

	// Verify ccav3 params.
	p := mock.lastCreateParams
	require.NotNil(t, p)
	assert.True(t, p.UseCcav3)

	// Verify key env vars for ccav3 bootstrap. Auth tokens are delivered via
	// stdin, not event inputs or inherited process env.
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_TOKEN")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_COPILOT_API_TOKEN")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_COPILOT_GIT_TOKEN")
	assert.NotContains(t, p.EnvironmentVariables, "COPILOT_JOB_NONCE")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_VERIFICATION_TOKEN")
	assert.Equal(t, "server-token", p.StdinSecrets["GITHUB_TOKEN"])
	assert.Equal(t, "user-token", p.StdinSecrets["GITHUB_COPILOT_API_TOKEN"])
	assert.Equal(t, "user-token", p.StdinSecrets["GITHUB_COPILOT_GITHUB_TOKEN"])
	assert.Equal(t, "integration-secret", p.StdinSecrets["GITHUB_COPILOT_INTEGRATION_ID"])
	assert.Equal(t, "job-nonce", p.StdinSecrets["COPILOT_JOB_NONCE"])
	assert.Equal(t, "job-nonce", p.StdinSecrets["GITHUB_VERIFICATION_TOKEN"])
	assert.Equal(t, "false", p.EnvironmentVariables["COPILOT_CCA_V3_USE_EXISTING_WORKSPACE"])
	// GITHUB_WORKSPACE is intentionally not set for ccav3 (see prepareCcav3).
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_WORKSPACE")
	assert.Equal(t, "STANDALONE", p.EnvironmentVariables["COPILOT_AGENT_RUNNER_TYPE"])
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_ACTIONS")
	assert.NotContains(t, p.EnvironmentVariables, "GITHUB_EVENT_NAME")

	// CLI flags should NOT be set when using ccav3.
	assert.Empty(t, p.CLIFlags)

	inputs := decodeEventInputs(t, p.EventFileJSON)
	for _, key := range ccav3RequiredEventInputs {
		assert.NotEmpty(t, inputs[key], "required ccav3 event input %s should be present", key)
	}
	assert.Equal(t, "https://callback.test", inputs["COPILOT_AGENT_CALLBACK_URL"])
	assert.Equal(t, "job-123", inputs["COPILOT_AGENT_JOB_ID"])
	assert.Equal(t, "job-nonce", inputs["COPILOT_JOB_NONCE"])
	assert.Equal(t, "org/repo", inputs["GITHUB_REPOSITORY"])
	assert.Equal(t, "42", inputs["GITHUB_REPOSITORY_ID"])
	assert.Equal(t, "7", inputs["GITHUB_REPOSITORY_OWNER_ID"])
	assert.Equal(t, "https://github.test", inputs["GITHUB_SERVER_URL"])
	assert.NotContains(t, inputs, "GITHUB_VERIFICATION_TOKEN")
	assert.NotContains(t, inputs, "GITHUB_COPILOT_API_TOKEN")
	assert.NotContains(t, inputs, "GITHUB_TOKEN")
	assert.NotContains(t, inputs, "GITHUB_COPILOT_GIT_TOKEN")
	assert.NotContains(t, inputs, "GITHUB_COPILOT_INTEGRATION_ID")
	assert.NotContains(t, inputs, "CAPI_HMAC_KEY")
}

var ccav3RequiredEventInputs = []string{
	"COPILOT_API_URL",
	"COPILOT_AGENT_ACTION",
	"COPILOT_AGENT_RUNTIME_VERSION",
	"COPILOT_AGENT_BASE_COMMIT",
	"COPILOT_AGENT_BRANCH_NAME",
	"COPILOT_AGENT_CALLBACK_URL",
	"COPILOT_AGENT_COMMIT_LOGIN",
	"COPILOT_AGENT_COMMIT_EMAIL",
	"COPILOT_AGENT_ISSUE_NUMBER",
	"COPILOT_AGENT_JOB_ID",
	"COPILOT_AGENT_PROMPT",
	"COPILOT_JOB_NONCE",
	"GITHUB_UPLOADS_URL",
	"GITHUB_DOWNLOADS_URL",
	"SECRET_SCANNING_URL",
}

func decodeEventInputs(t *testing.T, eventJSON string) map[string]string {
	t.Helper()

	var event struct {
		Inputs map[string]string `json:"inputs"`
	}
	require.NoError(t, json.Unmarshal([]byte(eventJSON), &event))
	require.NotEmpty(t, event.Inputs["COPILOT_AGENT_INPUTS"])

	var inputs map[string]string
	require.NoError(t, json.Unmarshal([]byte(event.Inputs["COPILOT_AGENT_INPUTS"]), &inputs))
	return inputs
}
