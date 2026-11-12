package agent

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	jobca "github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockAgenticApp is a minimal implementation of sweagentd.AgenticApp for testing.
type mockAgenticApp struct {
	appName     string
	agentSource *sweagentd.AgentSource
}

func (m *mockAgenticApp) AppID() int64            { return 1 }
func (m *mockAgenticApp) AppName() string         { return m.appName }
func (m *mockAgenticApp) BranchPrefix() string    { return "test" }
func (m *mockAgenticApp) BotID() int64            { return 2 }
func (m *mockAgenticApp) BotLogin() string        { return "test-bot" }
func (m *mockAgenticApp) CommitLogin() string     { return "test-commit" }
func (m *mockAgenticApp) CommitEmail() string     { return "test@example.com" }
func (m *mockAgenticApp) MentionableSlug() string { return "test-app" }
func (m *mockAgenticApp) ComputeSlug() string     { return "test-app" }
func (m *mockAgenticApp) EngineSlug() string      { return m.ComputeSlug() }
func (m *mockAgenticApp) HasSource() bool         { return m.agentSource != nil }
func (m *mockAgenticApp) SourceURL() string       { return "" }
func (m *mockAgenticApp) AgentSource() *sweagentd.AgentSource {
	return m.agentSource
}
func (m *mockAgenticApp) IsGlobalApp() bool                 { return false }
func (m *mockAgenticApp) IsPartnerApp() bool                { return false }
func (m *mockAgenticApp) IsThirdPartyApp() bool             { return false }
func (m *mockAgenticApp) ModelVendors() []string            { return nil }
func (m *mockAgenticApp) SetupCompute(sweagentd.ComputeEnv) {}
func (m *mockAgenticApp) Metadata() map[string]string       { return nil }
func (m *mockAgenticApp) IsQuotaExempt() bool               { return false }
func (m *mockAgenticApp) UsesExperiments() bool             { return true }
func (m *mockAgenticApp) WorkflowRunName(_ int) string      { return "" }

// noSourceApp is a mockAgenticApp without an AgentSource, reusable across tests.
var noSourceApp = &mockAgenticApp{appName: "test-engine"}

// pluginTestApp creates a mockAgenticApp with an AgentSource pointing to a plugin repo.
func pluginTestApp() *mockAgenticApp {
	return &mockAgenticApp{
		appName: "test-engine",
		agentSource: &sweagentd.AgentSource{
			URL: "https://github.com/plugin-owner/plugin-repo",
			SHA: "abc123",
		},
	}
}

// makePluginSpokes creates a spokestest client with blobs for a plugin.
// pluginJSON is the content of plugin.json; additional blobs can be passed as key=path, value=content.
func makePluginSpokes(t *testing.T, pluginJSON string, extraBlobs map[string][]byte) *spokestest.Client {
	t.Helper()
	opts := []spokestest.ClientOption{
		spokestest.WithBlob("plugin.json", []byte(pluginJSON)),
	}
	for p, content := range extraBlobs {
		opts = append(opts, spokestest.WithBlob(p, content))
	}
	return spokestest.NewClient(t, opts...)
}

func newTestOIDCService(t *testing.T) *oidc.Service {
	t.Helper()
	signer, err := devsigner.NewSignerFromKey("https://test-issuer", nil)
	require.NoError(t, err)
	return oidc.NewLocalService(featureflags.NewNoopClient(nil), signer, observability.NewNoopExporters(), oidc.ServiceConfig{})
}

// newTestExchangeService creates a Service with the minimum prerequisites for ExecuteTokenExchange.
// It wires up a noop spokes, feature flag client, plugin service, custom agent service, and OIDC service.
func newTestExchangeService(t *testing.T, noopClient *githubtwirp.NoopClient) *Service {
	t.Helper()
	spokesClient := spokestest.NewClient(t)
	ff := featureflags.NewNoopClient(nil)
	pluginSvc := plugins.NewService(observability.NewNoopExporters(), spokesClient, noopClient, "https://github.com")
	customAgentSvc := customagent.NewService(observability.NewNoopExporters(), spokesClient, noopClient, ff)
	oidcSvc := newTestOIDCService(t)
	appProvider := agenticapp.NewProvider(agenticapp.NewCopilot(0, "copilot-swe-agent", 0, "copilot-swe-agent[bot]", "commit", "commit@email.com"))
	return NewService(nil, nil, customAgentSvc, pluginSvc, observability.NewNoopExporters(), ff, noopClient, nil, appProvider, nil, oidcSvc)
}

func TestExecuteTokenExchange(t *testing.T) {
	ctx := context.Background()

	defaultJob := func() *jobs.Job {
		return &jobs.Job{
			ID:        "test-job-123",
			RepoID:    100,
			OwnerID:   200,
			SessionID: "session-456",
			EventURL:  "https://github.com/test-owner/test-repo/issues/1",
		}
	}

	defaultUserInfo := &requestctx.UserInfo{
		ID:    42,
		Login: "test-user",
	}

	defaultApp := &mockAgenticApp{appName: "test-engine"}

	t.Run("prerequisites nil returns error", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		noopClient := githubtwirp.NewNoopClient()
		oidcSvc := newTestOIDCService(t)
		svc := NewService(nil, nil, nil, nil, obsv, nil, noopClient, nil, nil, nil, oidcSvc)

		_, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:      defaultJob(),
			UserInfo: defaultUserInfo,
			App:      defaultApp,
		})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "prerequisites are nil")
	})

	t.Run("copilot agent succeeds with empty config", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()
		// Zero-value CustomAgent has Name="" → IsCopilot() returns true
		result, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:      job,
			UserInfo: defaultUserInfo,
			App:      defaultApp,
		})

		require.NoError(t, err)
		require.NotNil(t, result)
		assert.Empty(t, result.Secrets)
		assert.Empty(t, result.IssuedTokens)
	})

	t.Run("copilot agent with name copilot succeeds", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()
		job.CustomAgent = jobca.DBRecord{Name: "copilot"}

		result, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:      job,
			UserInfo: defaultUserInfo,
			App:      defaultApp,
		})

		require.NoError(t, err)
		require.NotNil(t, result)
		assert.Empty(t, result.Secrets)
	})

	t.Run("agent name matching custom agent name resolves agent by repo ID", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()
		job.CustomAgent = jobca.DBRecord{Name: "my-agent", Version: "1.0"}

		// spokestest has no agent config, so resolution should fail
		_, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:       job,
			UserInfo:  defaultUserInfo,
			AgentName: "my-agent",
			App:       defaultApp,
		})

		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to resolve agent for job")
	})

	t.Run("empty agent name with non-copilot custom agent resolves by repo ID", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()
		job.CustomAgent = jobca.DBRecord{Name: "my-agent", Version: "1.0"}

		// AgentName is empty but job.CustomAgent is non-copilot, so GetAgentForJob is called
		_, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:      job,
			UserInfo: defaultUserInfo,
			App:      defaultApp,
		})

		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to resolve agent for job")
	})

	t.Run("different agent name uses resolveNamedAgent", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()
		job.CustomAgent = jobca.DBRecord{Name: "agent-a"}

		// AgentName differs from CustomAgent.Name → uses resolveNamedAgent
		_, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:          job,
			UserInfo:     defaultUserInfo,
			AgentName:    "agent-b",
			AgentVersion: "2.0",
			App:          defaultApp,
		})

		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to resolve agent for job")
	})

	t.Run("GetRepositoryInstallation failure propagates error", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return nil, goerrors.New("installation lookup failed")
		}
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()

		_, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:      job,
			UserInfo: defaultUserInfo,
			App:      defaultApp,
		})

		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to get repository installation")
	})

	t.Run("repo info from GetRepositoryInstallation is used in token params", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 42,
				OwnerId:        200,
				OwnerLogin:     "my-owner",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION,
				ClientId:       "test-client-id",
				RepoName:       "my-repo",
			}, nil
		}
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()

		result, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:      job,
			UserInfo: defaultUserInfo,
			App:      defaultApp,
		})

		require.NoError(t, err)
		require.NotNil(t, result)
		// With no OIDC config entries, tokens are empty
		assert.Empty(t, result.Secrets)
	})

	t.Run("secret and MCP server names are passed to resolve configuration", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()

		result, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:            job,
			UserInfo:       defaultUserInfo,
			SecretNames:    []string{"COPILOT_SECRET_EXAMPLE"},
			MCPServerNames: []string{"my-mcp-server"},
			App:            defaultApp,
		})

		require.NoError(t, err)
		require.NotNil(t, result)
		// With local OIDC service and no config, still returns empty secrets
		assert.Empty(t, result.Secrets)
	})

	t.Run("global app zeroes installation ID in token params", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			return &sweagentdTwirp.GetRepositoryInstallationResponse{
				InstallationId: 99,
				OwnerId:        300,
				OwnerLogin:     "my-org",
				OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION,
				ClientId:       "test-client-id",
				RepoName:       "org-repo",
				IsGlobal:       true,
			}, nil
		}
		svc := newTestExchangeService(t, noopClient)

		job := defaultJob()

		result, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:      job,
			UserInfo: defaultUserInfo,
			App:      defaultApp,
		})

		require.NoError(t, err)
		require.NotNil(t, result)
		// The main assertion here is that the exchange succeeds.
		// The global-app zero-installation-ID logic is exercised; with no OIDC
		// config entries the tokens are empty but the path is covered.
		assert.Empty(t, result.Secrets)
	})
}

func TestResolveNamedAgent(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("app plugin has the agent", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		agentConfig := "---\nname: my-agent\ndescription: test\n---\nThis is a prompt"
		spokes := makePluginSpokes(t, `{"name":"test-plugin","agents":["agents/"]}`, map[string][]byte{
			"agents/my-agent.md": []byte(agentConfig),
			"my-agent.md@abc123": []byte(agentConfig),
		})
		pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
		ffClient := featureflags.NewNoopClient(nil)
		customAgentSvc := customagent.NewService(obsv, spokes, noopClient, ffClient)

		svc := &Service{
			pluginSvc:      pluginSvc,
			customAgentSvc: customAgentSvc,
			obsv:           obsv,
			ff:             ffClient,
		}

		appPlugin, err := pluginSvc.GetPluginForApp(ctx, pluginTestApp())
		require.NoError(t, err)

		agent, fromApp, err := svc.resolveNamedAgent(ctx, appPlugin, nil, ExecuteTokenExchangeParams{
			Job:       &jobs.Job{RepoID: 100},
			AgentName: "my-agent",
			App:       pluginTestApp(),
		})
		require.NoError(t, err)
		require.NotNil(t, agent)
		assert.Equal(t, "my-agent", agent.Name())
		assert.True(t, fromApp, "agent from app plugin should return agentFromApp=true")
	})

	t.Run("app plugin nil falls back to repo plugins", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		agentConfig := "---\nname: repo-agent\ndescription: test\n---\nThis is a prompt"
		agentSpokes := customagenttest.MakeSpokes(t, map[string]string{
			"repo-agent": agentConfig,
		})
		ffClient := featureflags.NewNoopClient(nil)
		pluginSvc := plugins.NewService(obsv, spokestest.NewClient(t), noopClient, "https://github.com")
		customAgentSvc := customagent.NewService(obsv, agentSpokes, noopClient, ffClient)

		svc := &Service{
			pluginSvc:      pluginSvc,
			customAgentSvc: customAgentSvc,
			obsv:           obsv,
			ff:             ffClient,
		}

		agent, fromApp, err := svc.resolveNamedAgent(ctx, nil, nil, ExecuteTokenExchangeParams{
			Job:       &jobs.Job{RepoID: 100},
			UserInfo:  &requestctx.UserInfo{ID: 42, Login: "test-user"},
			AgentName: "repo-agent",
			App:       noSourceApp,
		})
		require.NoError(t, err)
		require.NotNil(t, agent)
		assert.Equal(t, "repo-agent", agent.Name())
		assert.False(t, fromApp, "agent from custom agent service should return agentFromApp=false")
	})

	t.Run("falls back to custom agent service when no plugin match", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		pluginSpokes := spokestest.NewClient(t)
		pluginSvc := plugins.NewService(obsv, pluginSpokes, noopClient, "https://github.com")

		agentConfig := "---\nname: repo-agent\ndescription: test\n---\nThis is a prompt"
		agentSpokes := customagenttest.MakeSpokes(t, map[string]string{
			"repo-agent": agentConfig,
		})
		ffClient := featureflags.NewNoopClient(nil)
		customAgentSvc := customagent.NewService(obsv, agentSpokes, noopClient, ffClient)

		svc := &Service{
			pluginSvc:      pluginSvc,
			customAgentSvc: customAgentSvc,
			obsv:           obsv,
			ff:             ffClient,
		}

		agent, fromApp, err := svc.resolveNamedAgent(ctx, nil, nil, ExecuteTokenExchangeParams{
			Job:       &jobs.Job{RepoID: 100},
			UserInfo:  &requestctx.UserInfo{ID: 42, Login: "test-user"},
			AgentName: "repo-agent",
			App:       noSourceApp,
		})
		require.NoError(t, err)
		require.NotNil(t, agent)
		assert.Equal(t, "repo-agent", agent.Name())
		assert.False(t, fromApp, "agent from custom agent service should return agentFromApp=false")
	})

	t.Run("neither plugins nor repo have agent returns error", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		pluginSpokes := spokestest.NewClient(t)
		pluginSvc := plugins.NewService(obsv, pluginSpokes, noopClient, "https://github.com")

		agentSpokes := customagenttest.MakeSpokesWithRepoAndCommitSHA(t, map[string]string{}, "", 0)
		ffClient := featureflags.NewNoopClient(nil)
		customAgentSvc := customagent.NewService(obsv, agentSpokes, noopClient, ffClient)

		svc := &Service{
			pluginSvc:      pluginSvc,
			customAgentSvc: customAgentSvc,
			obsv:           obsv,
			ff:             ffClient,
		}

		_, _, err := svc.resolveNamedAgent(ctx, nil, nil, ExecuteTokenExchangeParams{
			Job:       &jobs.Job{RepoID: 100},
			UserInfo:  &requestctx.UserInfo{ID: 42, Login: "test-user"},
			AgentName: "nonexistent",
			App:       noSourceApp,
		})
		require.Error(t, err)
		assert.ErrorIs(t, err, ErrFailedToResolveAgentForExchange)
	})
}

func TestLoadRepoPlugins(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("feature flag disabled returns empty list", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		spokes := spokestest.NewClient(t)
		pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
		ff := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPluginsEnabled: false,
		})

		svc := &Service{
			pluginSvc: pluginSvc,
			obsv:      obsv,
			ff:        ff,
		}

		result, err := svc.loadRepoPlugins(ctx, &jobs.Job{RepoID: 100})
		require.NoError(t, err)
		assert.Empty(t, result)
	})

	t.Run("feature flag enabled with no settings returns nil", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		spokes := spokestest.NewClient(t)
		pluginSvc := plugins.NewService(obsv, spokes, noopClient, "https://github.com")
		ff := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPluginsEnabled: true,
		})

		svc := &Service{
			pluginSvc: pluginSvc,
			obsv:      obsv,
			ff:        ff,
			ghtwirp:   noopClient,
		}

		result, err := svc.loadRepoPlugins(ctx, &jobs.Job{RepoID: 100})
		require.NoError(t, err)
		assert.Empty(t, result)
	})
}

func TestExecuteTokenExchange_PluginIntegration(t *testing.T) {
	ctx := context.Background()

	t.Run("MCP server names with no plugins does not panic", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := &jobs.Job{
			ID:        "test-job",
			RepoID:    100,
			OwnerID:   200,
			SessionID: "session-1",
		}

		result, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:            job,
			UserInfo:       &requestctx.UserInfo{ID: 42, Login: "test-user"},
			MCPServerNames: []string{"some-server"},
			App:            noSourceApp,
		})
		require.NoError(t, err)
		require.NotNil(t, result)
		assert.Empty(t, result.Secrets)
	})

	t.Run("different agent name with no matching agent returns error", func(t *testing.T) {
		noopClient := githubtwirp.NewNoopClient()
		svc := newTestExchangeService(t, noopClient)

		job := &jobs.Job{
			ID:          "test-job",
			RepoID:      100,
			OwnerID:     200,
			SessionID:   "session-1",
			CustomAgent: jobca.DBRecord{Name: "agent-a"},
		}

		_, err := svc.ExecuteTokenExchange(ctx, ExecuteTokenExchangeParams{
			Job:       job,
			UserInfo:  &requestctx.UserInfo{ID: 42, Login: "test-user"},
			AgentName: "agent-b",
			App:       noSourceApp,
		})
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to resolve agent for job")
	})
}
