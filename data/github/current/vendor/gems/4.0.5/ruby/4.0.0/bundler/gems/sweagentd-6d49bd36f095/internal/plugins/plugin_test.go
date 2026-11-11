package plugins

import (
	"context"
	"encoding/json"
	"sort"
	"testing"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockAgenticApp is a minimal implementation of sweagentd.AgenticApp for testing.
type mockAgenticApp struct {
	agentSource *sweagentd.AgentSource
}

func (m *mockAgenticApp) AppID() int64                        { return 1 }
func (m *mockAgenticApp) AppName() string                     { return "mock-app" }
func (m *mockAgenticApp) WorkflowRunName(_ int) string        { return "" }
func (m *mockAgenticApp) BranchPrefix() string                { return "mock" }
func (m *mockAgenticApp) BotID() int64                        { return 1 }
func (m *mockAgenticApp) BotLogin() string                    { return "mock-bot" }
func (m *mockAgenticApp) CommitLogin() string                 { return "mock-commit" }
func (m *mockAgenticApp) CommitEmail() string                 { return "mock@test.com" }
func (m *mockAgenticApp) MentionableSlug() string             { return "mock-slug" }
func (m *mockAgenticApp) ComputeSlug() string                 { return "mock-compute" }
func (m *mockAgenticApp) EngineSlug() string                  { return m.ComputeSlug() }
func (m *mockAgenticApp) HasSource() bool                     { return m.agentSource != nil }
func (m *mockAgenticApp) SourceURL() string                   { return "" }
func (m *mockAgenticApp) AgentSource() *sweagentd.AgentSource { return m.agentSource }
func (m *mockAgenticApp) IsGlobalApp() bool                   { return false }
func (m *mockAgenticApp) IsPartnerApp() bool                  { return false }
func (m *mockAgenticApp) IsThirdPartyApp() bool               { return true }
func (m *mockAgenticApp) ModelVendors() []string              { return nil }
func (m *mockAgenticApp) Metadata() map[string]string         { return nil }
func (m *mockAgenticApp) IsQuotaExempt() bool                 { return false }
func (m *mockAgenticApp) UsesExperiments() bool               { return true }
func (m *mockAgenticApp) SetupCompute(sweagentd.ComputeEnv)   {}

const testRepoURL = "https://github.com/test-owner/test-repo"

// defaultTestSHA is the default commit SHA returned by spokestest.NewClient.
const defaultTestSHA = "sha-0123456789101112131415161718192021222324252627"

// testMeta returns a PluginMetadata with the given CloneURL for simple direct-URL test cases.
func testMeta(cloneURL string) PluginMetadata {
	return PluginMetadata{CloneURL: cloneURL}
}

// resolveTestPlugin is a helper that resolves a pluginSpec via ResolvePluginRepos and returns
// the first PluginMetadata. It fails the test if resolution returns no results.
func resolveTestPlugin(ctx context.Context, t *testing.T, svc *Service, extraKnownMarketplaces map[string]ExtraMarketplace, pluginSpec string) PluginMetadata {
	t.Helper()
	resolved, err := svc.ResolvePluginRepos(ctx, &SettingsJSON{
		EnabledPlugins:         map[string]bool{pluginSpec: true},
		ExtraKnownMarketplaces: extraKnownMarketplaces,
	})
	require.NoError(t, err)
	require.NotEmpty(t, resolved, "ResolvePluginRepos returned no results for spec %q", pluginSpec)
	return resolved[0]
}

func agentNames(m map[string]string) []string {
	names := make([]string, 0, len(m))
	for k := range m {
		names = append(names, k)
	}
	sort.Strings(names)
	return names
}

// newTestService creates a Service backed by the given spokestest blobs and a noop ghtwirp client.
func newTestService(t *testing.T, opts ...spokestest.ClientOption) *Service {
	t.Helper()
	spokesClient := spokestest.NewClient(t, opts...)
	ghTwirp := githubtwirp.NewNoopClient()
	obsv := observability.NewNoopExporters()
	return NewService(obsv, spokesClient, ghTwirp, "https://github.com")
}

// testExtraMarketplace builds a single-entry ExtraMarketplace map pointing to a GitHub repo.
func testExtraMarketplace(name, repo string) map[string]ExtraMarketplace {
	return map[string]ExtraMarketplace{
		name: {Source: MarketplaceSourceConfig{Source: "github", Repo: repo}},
	}
}

func TestGetPlugin_Config(t *testing.T) {
	ctx := context.Background()

	t.Run("basic plugin.json", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test-plugin","description":"A test plugin"}`)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Empty(t, plugin.Info.MCPServers)
		assert.Empty(t, plugin.Info.AgentPaths)
		assert.Equal(t, "test-plugin", plugin.Info.Name)
	})

	t.Run("with MCP config", func(t *testing.T) {
		mcpJSON := `{"mcpServers":{"my-server":{"command":"node","args":["server.js"],"tools":["tool1"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob(".mcp.json", []byte(mcpJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		require.NotEmpty(t, plugin.Info.MCPServers)
		reconstructed := mcpconfig.JSON{Servers: plugin.Info.MCPServers}
		mcpBytes, marshalErr := json.Marshal(reconstructed)
		require.NoError(t, marshalErr)
		assert.JSONEq(t, mcpJSON, string(mcpBytes))
	})

	t.Run("returns tools: [\"*\"] when no tools are specified", func(t *testing.T) {
		mcpJSON := `{"mcpServers":{"my-server":{"command":"node","args":["server.js"]}}}`
		svc := newTestService(
			t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob(".mcp.json", []byte(mcpJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)

		server := plugin.Info.MCPServers["my-server"]
		assert.Equal(t, []string{"*"}, server.Tools)
	})

	t.Run("mcpServers as string path in plugin.json", func(t *testing.T) {
		mcpJSON := `{"mcpServers":{"path-server":{"command":"python","args":["serve.py"],"tools":["search"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test","mcpServers":"./config/mcp.json"}`)),
			spokestest.WithBlob("config/mcp.json", []byte(mcpJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		require.NotEmpty(t, plugin.Info.MCPServers)
		assert.Equal(t, "python", plugin.Info.MCPServers["path-server"].Command)
		assert.Equal(t, []string{"search"}, plugin.Info.MCPServers["path-server"].Tools)
	})

	t.Run("mcpServers as string path defaults tools to wildcard", func(t *testing.T) {
		mcpJSON := `{"mcpServers":{"ref-server":{"command":"node","args":["index.js"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test","mcpServers":"mcp.json"}`)),
			spokestest.WithBlob("mcp.json", []byte(mcpJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, []string{"*"}, plugin.Info.MCPServers["ref-server"].Tools)
	})

	t.Run("mcpServers as inline object in plugin.json", func(t *testing.T) {
		pluginJSON := `{"name":"test","mcpServers":{"inline-server":{"command":"go","args":["run","."],"tools":["build"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(pluginJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		require.NotEmpty(t, plugin.Info.MCPServers)
		assert.Equal(t, "go", plugin.Info.MCPServers["inline-server"].Command)
		assert.Equal(t, []string{"build"}, plugin.Info.MCPServers["inline-server"].Tools)
	})

	t.Run("mcpServers inline defaults tools to wildcard", func(t *testing.T) {
		pluginJSON := `{"name":"test","mcpServers":{"no-tools-server":{"command":"node","args":["srv.js"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(pluginJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, []string{"*"}, plugin.Info.MCPServers["no-tools-server"].Tools)
	})

	t.Run("mcpServers in plugin.json overrides .mcp.json", func(t *testing.T) {
		dotMCPJSON := `{"mcpServers":{"dot-server":{"command":"old","args":["cmd"]}}}`
		pluginJSON := `{"name":"test","mcpServers":{"inline-server":{"command":"new","args":["cmd"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(pluginJSON)),
			spokestest.WithBlob(".mcp.json", []byte(dotMCPJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		// inline mcpServers should override .mcp.json
		assert.NotContains(t, plugin.Info.MCPServers, "dot-server")
		assert.Contains(t, plugin.Info.MCPServers, "inline-server")
	})

	t.Run("falls back to .github/mcp.json when .mcp.json is absent", func(t *testing.T) {
		mcpJSON := `{"mcpServers":{"github-server":{"command":"node","args":["srv.js"],"tools":["read"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob(".github/mcp.json", []byte(mcpJSON)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		require.NotEmpty(t, plugin.Info.MCPServers)
		assert.Equal(t, "node", plugin.Info.MCPServers["github-server"].Command)
		assert.Equal(t, []string{"read"}, plugin.Info.MCPServers["github-server"].Tools)
	})

	t.Run(".mcp.json takes priority over .github/mcp.json", func(t *testing.T) {
		rootMCP := `{"mcpServers":{"root-server":{"command":"node","args":["root.js"]}}}`
		githubMCP := `{"mcpServers":{"github-server":{"command":"node","args":["github.js"]}}}`
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob(".mcp.json", []byte(rootMCP)),
			spokestest.WithBlob(".github/mcp.json", []byte(githubMCP)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Contains(t, plugin.Info.MCPServers, "root-server")
		assert.NotContains(t, plugin.Info.MCPServers, "github-server")
	})
}

func TestGetPlugin_ManifestLocation(t *testing.T) {
	ctx := context.Background()

	t.Run("non-root plugin.json", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob(".plugin/plugin.json", []byte(`{"name":"from-dot-plugin"}`)),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, "from-dot-plugin", plugin.Info.Name)
	})

	t.Run("dot-plugin takes priority over root", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob(".plugin/plugin.json", []byte(`{"name":"priority-winner"}`)),
			spokestest.WithBlob("plugin.json", []byte(`{"name":"root-fallback"}`)),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, "priority-winner", plugin.Info.Name)
	})
}

func TestGetPlugin_AgentDiscovery(t *testing.T) {
	ctx := context.Background()

	t.Run("default agents directory", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob("agents/reviewer.agent.md", []byte("# Agent")),
			spokestest.WithBlob("agents/helper.md", []byte("# Agent")),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, []string{"helper", "reviewer"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("duplicate .agent.md and .md resolve to single entry", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob("agents/foo.agent.md", []byte("# Agent")),
			spokestest.WithBlob("agents/foo.md", []byte("# Agent")),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, []string{"foo"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("custom agents path string", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test","agents":"custom-agents/"}`)),
			spokestest.WithBlob("custom-agents/my-agent.md", []byte("# Agent")),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, []string{"my-agent"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("agents path array", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test","agents":["agents/","extra-agents/"]}`)),
			spokestest.WithBlob("agents/a.md", []byte("# Agent")),
			spokestest.WithBlob("extra-agents/b.md", []byte("# Agent")),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, []string{"a", "b"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("skips non-md files", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob("agents/valid.md", []byte("# Agent")),
			spokestest.WithBlob("agents/readme.txt", []byte("not an agent")),
			spokestest.WithBlob("agents/config.json", []byte("{}")),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Equal(t, []string{"valid"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("missing agent path yields no agents", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test","agents":"../../etc"}`)),
		)
		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)
		assert.Empty(t, plugin.Info.AgentPaths)
	})
}

func TestGetPlugin_Errors(t *testing.T) {
	ctx := context.Background()

	t.Run("no plugin.json", func(t *testing.T) {
		svc := newTestService(t)
		_, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.Error(t, err)
		assert.Contains(t, err.Error(), "no valid plugin.json found")
	})

	t.Run("invalid plugin.json", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte("not valid json{{{")),
		)
		_, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.Error(t, err)
		assert.Contains(t, err.Error(), "invalid plugin.json")
	})

	t.Run("invalid .mcp.json", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob(".mcp.json", []byte("not valid json{{{")),
		)
		_, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.Error(t, err)
		assert.Contains(t, err.Error(), "invalid MCP config")
	})
}

func TestGetPlugin_Marketplace(t *testing.T) {
	ctx := context.Background()

	t.Run("local source", func(t *testing.T) {
		marketplaceJSON := `{
			"name": "my-marketplace",
			"plugins": [
				{"name": "frontend-design", "source": "./plugins/frontend-design"},
				{"name": "security-checks", "source": "plugins/security-checks"}
			]
		}`
		svc := newTestService(t,
			spokestest.WithBlob(".github/plugin/marketplace.json", []byte(marketplaceJSON)),
			spokestest.WithBlob("plugins/frontend-design/plugin.json", []byte(`{"name":"frontend-design"}`)),
			spokestest.WithBlob("plugins/frontend-design/agents/designer.agent.md", []byte("# Agent")),
			spokestest.WithBlob("plugins/frontend-design/.mcp.json", []byte(`{"mcpServers":{}}`)),
		)

		meta := resolveTestPlugin(ctx, t, svc, testExtraMarketplace("my-marketplace", "test-owner/test-repo"), "frontend-design@my-marketplace")
		plugin, err := svc.GetPlugin(ctx, meta)
		require.NoError(t, err)
		assert.Equal(t, "frontend-design", plugin.Info.Name)
		assert.Equal(t, "my-marketplace", plugin.Meta.MarketplaceName)
		assert.Equal(t, []string{"designer"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("empty name in plugin.json falls back to marketplace entry name", func(t *testing.T) {
		marketplaceJSON := `{
			"name": "test-mkt",
			"plugins": [{"name": "my-plugin", "source": "plugins/my-plugin"}]
		}`
		svc := newTestService(t,
			spokestest.WithBlob("marketplace.json", []byte(marketplaceJSON)),
			spokestest.WithBlob("plugins/my-plugin/plugin.json", []byte(`{}`)),
			spokestest.WithBlob("plugins/my-plugin/agents/bot.md", []byte("# Agent")),
		)

		meta := resolveTestPlugin(ctx, t, svc, testExtraMarketplace("test-mkt", "test-owner/test-repo"), "my-plugin@test-mkt")
		plugin, err := svc.GetPlugin(ctx, meta)
		require.NoError(t, err)
		assert.Equal(t, "my-plugin", plugin.Info.Name)
		assert.Equal(t, "test-mkt", plugin.Meta.MarketplaceName)
		assert.Equal(t, []string{"bot"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("plugin not found in marketplace", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("marketplace.json", []byte(`{"name": "my-mkt", "plugins": [{"name": "other", "source": "plugins/other"}]}`)),
		)

		resolved, err := svc.ResolvePluginRepos(context.Background(), &SettingsJSON{
			EnabledPlugins:         map[string]bool{"nonexistent@my-mkt": true},
			ExtraKnownMarketplaces: testExtraMarketplace("my-mkt", "test-owner/test-repo"),
		})
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Contains(t, resolved[0].ResolutionFailure, "not found in marketplace")
	})

	t.Run("traversal source rejected", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("marketplace.json", []byte(`{"name": "mkt", "plugins": [{"name": "evil", "source": "../../etc/passwd"}]}`)),
		)

		resolved, err := svc.ResolvePluginRepos(context.Background(), &SettingsJSON{
			EnabledPlugins:         map[string]bool{"evil@mkt": true},
			ExtraKnownMarketplaces: testExtraMarketplace("mkt", "test-owner/test-repo"),
		})
		require.NoError(t, err)
		require.Len(t, resolved, 1)
		assert.Contains(t, resolved[0].ResolutionFailure, "path traversal")
	})

	t.Run("pluginRoot resolves paths", func(t *testing.T) {
		marketplaceJSON := `{
			"name": "awesome-copilot",
			"metadata": {"pluginRoot": "./plugins"},
			"plugins": [{"name": "my-tool", "source": "my-tool"}]
		}`
		svc := newTestService(t,
			spokestest.WithBlob(".github/plugin/marketplace.json", []byte(marketplaceJSON)),
			spokestest.WithBlob("plugins/my-tool/plugin.json", []byte(`{"name":"my-tool"}`)),
			spokestest.WithBlob("plugins/my-tool/agents/helper.md", []byte("# Agent")),
			spokestest.WithBlob("plugins/my-tool/agents/reviewer.agent.md", []byte("# Agent")),
		)

		meta := resolveTestPlugin(ctx, t, svc, testExtraMarketplace("awesome-copilot", "test-owner/test-repo"), "my-tool@awesome-copilot")
		plugin, err := svc.GetPlugin(ctx, meta)
		require.NoError(t, err)
		assert.Equal(t, "my-tool", plugin.Info.Name)
		assert.Equal(t, "awesome-copilot", plugin.Meta.MarketplaceName)
		assert.Equal(t, []string{"helper", "reviewer"}, agentNames(plugin.Info.AgentPaths))
	})

	t.Run("marketplace OID used for local plugin references", func(t *testing.T) {
		marketplaceJSON := `{
			"name": "mkt",
			"plugins": [{"name": "local-plugin", "source": "./plugins/local-plugin"}]
		}`
		svc := newTestService(t,
			spokestest.WithBlob(".github/plugin/marketplace.json", []byte(marketplaceJSON)),
			spokestest.WithBlob("plugins/local-plugin/plugin.json", []byte(`{"name":"local-plugin"}`)),
		)

		meta := resolveTestPlugin(ctx, t, svc, testExtraMarketplace("mkt", "test-owner/test-repo"), "local-plugin@mkt")
		plugin, err := svc.GetPlugin(ctx, meta)
		require.NoError(t, err)
		assert.Equal(t, "local-plugin", plugin.Info.Name)
		// The plugin OID should be the marketplace repo's default branch OID,
		// not independently resolved, since local sources inherit the marketplace commit.
		assert.Equal(t, defaultTestSHA, plugin.Info.OID)
	})

	t.Run("pluginRoot leading dot-slash cleaned", func(t *testing.T) {
		marketplaceJSON := `{
			"name": "mkt",
			"metadata": {"pluginRoot": "./base"},
			"plugins": [{"name": "p1", "source": "./sub"}]
		}`
		svc := newTestService(t,
			spokestest.WithBlob("marketplace.json", []byte(marketplaceJSON)),
			spokestest.WithBlob("base/sub/plugin.json", []byte(`{"name":"p1"}`)),
			spokestest.WithBlob("base/sub/agents/bot.md", []byte("# Agent")),
		)

		meta := resolveTestPlugin(ctx, t, svc, testExtraMarketplace("mkt", "test-owner/test-repo"), "p1@mkt")
		plugin, err := svc.GetPlugin(ctx, meta)
		require.NoError(t, err)
		assert.Equal(t, "p1", plugin.Info.Name)
		assert.Equal(t, []string{"bot"}, agentNames(plugin.Info.AgentPaths))
	})
}

func TestGetPluginAgent(t *testing.T) {
	ctx := context.Background()

	t.Run("parses all frontmatter fields", func(t *testing.T) {
		agentMD := "---\ndescription: A helpful code reviewer\ntools:\n  - view\n  - edit\nmodel: gpt-4\n---\nYou are a code reviewer."

		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob("agents/reviewer.agent.md", []byte(agentMD)),
			spokestest.WithCommitSHAAndBlob("reviewer.agent.md", defaultTestSHA, []byte(agentMD)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)

		agent, err := svc.GetPluginAgent(ctx, plugin, "reviewer")
		require.NoError(t, err)
		assert.Equal(t, "reviewer", agent.Name())
		assert.Equal(t, "A helpful code reviewer", agent.Description())
		assert.Equal(t, "You are a code reviewer.", agent.Prompt())
		assert.Equal(t, []string{"view", "edit"}, agent.Tools())
		assert.Equal(t, "gpt-4", agent.Model())
	})

	t.Run("loads .md files without .agent suffix", func(t *testing.T) {
		agentMD := "---\ndescription: A helper agent\n---\nHelp the user."

		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob("agents/helper.md", []byte(agentMD)),
			spokestest.WithCommitSHAAndBlob("helper.md", defaultTestSHA, []byte(agentMD)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)

		agent, err := svc.GetPluginAgent(ctx, plugin, "helper")
		require.NoError(t, err)
		assert.Equal(t, "helper", agent.Name())
		assert.Equal(t, "A helper agent", agent.Description())
	})

	t.Run("custom agents path", func(t *testing.T) {
		agentMD := "---\ndescription: Custom path agent\n---\nDo things."

		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test","agents":"my-agents/"}`)),
			spokestest.WithBlob("my-agents/bot.agent.md", []byte(agentMD)),
			spokestest.WithCommitSHAAndBlob("bot.agent.md", defaultTestSHA, []byte(agentMD)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)

		agent, err := svc.GetPluginAgent(ctx, plugin, "bot")
		require.NoError(t, err)
		assert.Equal(t, "bot", agent.Name())
		assert.Equal(t, "Custom path agent", agent.Description())
	})

	t.Run("repo owner and name from URL", func(t *testing.T) {
		agentMD := "---\ndescription: Spokes agent\n---\nVia spokes."

		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob("agents/my-agent.md", []byte(agentMD)),
			spokestest.WithCommitSHAAndBlob("my-agent.md", defaultTestSHA, []byte(agentMD)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta("https://github.com/octocat/my-plugin"))
		require.NoError(t, err)

		agent, err := svc.GetPluginAgent(ctx, plugin, "my-agent")
		require.NoError(t, err)
		assert.Equal(t, "my-agent", agent.Name())
		assert.Equal(t, "Spokes agent", agent.Description())
		assert.Equal(t, "octocat", agent.RepoOwner())
		assert.Equal(t, "my-plugin", agent.RepoName())
	})

	t.Run("marketplace plugin agent", func(t *testing.T) {
		agentMD := "---\ndescription: A writer agent\n---\nYou write docs."
		marketplaceData := `{
"name": "awesome-copilot",
"plugins": [{"name": "se-team", "source": "./plugins/se-team"}]
}`

		svc := newTestService(t,
			spokestest.WithBlob(".github/plugin/marketplace.json", []byte(marketplaceData)),
			spokestest.WithBlob("plugins/se-team/plugin.json", []byte(`{"name":"se-team"}`)),
			spokestest.WithBlob("plugins/se-team/agents/writer.agent.md", []byte(agentMD)),
			spokestest.WithCommitSHAAndBlob("writer.agent.md", defaultTestSHA, []byte(agentMD)),
		)

		meta := resolveTestPlugin(ctx, t, svc, testExtraMarketplace("awesome-copilot", "test-owner/test-repo"), "se-team@awesome-copilot")
		plugin, err := svc.GetPlugin(ctx, meta)
		require.NoError(t, err)

		agent, err := svc.GetPluginAgent(ctx, plugin, "writer")
		require.NoError(t, err)
		assert.Equal(t, "writer", agent.Name())
		assert.Equal(t, "A writer agent", agent.Description())
	})
}

func TestGetPluginAgent_Errors(t *testing.T) {
	ctx := context.Background()

	t.Run("agent not found", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)

		_, err = svc.GetPluginAgent(ctx, plugin, "nonexistent")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "not found")
	})

	t.Run("malformed agent config", func(t *testing.T) {
		badMD := "No frontmatter here, just plain text."

		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"test"}`)),
			spokestest.WithBlob("agents/broken.agent.md", []byte(badMD)),
			spokestest.WithCommitSHAAndBlob("broken.agent.md", defaultTestSHA, []byte(badMD)),
		)

		plugin, err := svc.GetPlugin(ctx, testMeta(testRepoURL))
		require.NoError(t, err)

		_, err = svc.GetPluginAgent(ctx, plugin, "broken")
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to parse agent config")
	})
}

func TestGetPluginForApp(t *testing.T) {
	ctx := context.Background()

	t.Run("returns plugin for app with agent source", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"app-plugin"}`)),
			spokestest.WithBlob("agents/main.agent.md", []byte("---\ndescription: Main agent\n---\nDo things.")),
		)

		app := &mockAgenticApp{
			agentSource: &sweagentd.AgentSource{
				URL: testRepoURL,
				SHA: defaultTestSHA,
			},
		}

		plugin, err := svc.GetPluginForApp(ctx, app)
		require.NoError(t, err)
		require.NotNil(t, plugin)
		assert.Equal(t, "app-plugin", plugin.Info.Name)
		assert.Equal(t, testRepoURL, plugin.Meta.CloneURL)
		assert.Equal(t, defaultTestSHA, plugin.Meta.SHA)
	})

	t.Run("returns nil when agent source is nil", func(t *testing.T) {
		svc := newTestService(t)
		app := &mockAgenticApp{agentSource: nil}

		plugin, err := svc.GetPluginForApp(ctx, app)
		require.NoError(t, err)
		assert.Nil(t, plugin)
	})

	t.Run("returns nil when agent source URL is empty", func(t *testing.T) {
		svc := newTestService(t)
		app := &mockAgenticApp{agentSource: &sweagentd.AgentSource{URL: ""}}

		plugin, err := svc.GetPluginForApp(ctx, app)
		require.NoError(t, err)
		assert.Nil(t, plugin)
	})

	t.Run("returns error when plugin fetch fails", func(t *testing.T) {
		svc := newTestService(t) // no plugin.json available
		app := &mockAgenticApp{
			agentSource: &sweagentd.AgentSource{
				URL: testRepoURL,
				SHA: defaultTestSHA,
			},
		}

		_, err := svc.GetPluginForApp(ctx, app)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to get plugin for app")
	})
}

func TestGetCustomAgentForApp(t *testing.T) {
	ctx := context.Background()

	t.Run("returns custom agent for app", func(t *testing.T) {
		agentMD := "---\ndescription: Main agent\ntools:\n  - view\n---\nYou are the main agent."
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"app-plugin"}`)),
			spokestest.WithBlob("agents/main.agent.md", []byte(agentMD)),
			spokestest.WithCommitSHAAndBlob("main.agent.md", defaultTestSHA, []byte(agentMD)),
		)

		app := &mockAgenticApp{
			agentSource: &sweagentd.AgentSource{
				URL: testRepoURL,
				SHA: defaultTestSHA,
			},
		}

		agent, _, err := svc.GetCustomAgentForApp(ctx, app)
		require.NoError(t, err)
		require.NotNil(t, agent)
		assert.Equal(t, "main", agent.Name())
		assert.Equal(t, "Main agent", agent.Description())
		assert.Equal(t, "You are the main agent.", agent.Prompt())
		assert.Equal(t, []string{"view"}, agent.Tools())
	})

	t.Run("returns nil when app has no agent source", func(t *testing.T) {
		svc := newTestService(t)
		app := &mockAgenticApp{agentSource: nil}

		agent, _, err := svc.GetCustomAgentForApp(ctx, app)
		require.NoError(t, err)
		assert.Nil(t, agent)
	})

	t.Run("returns error when plugin has no main agent", func(t *testing.T) {
		svc := newTestService(t,
			spokestest.WithBlob("plugin.json", []byte(`{"name":"no-main"}`)),
			spokestest.WithBlob("agents/helper.md", []byte("---\ndescription: Not main\n---\nHelp.")),
		)

		app := &mockAgenticApp{
			agentSource: &sweagentd.AgentSource{
				URL: testRepoURL,
				SHA: defaultTestSHA,
			},
		}

		_, _, err := svc.GetCustomAgentForApp(ctx, app)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to get custom agent for app")
	})

	t.Run("returns error when plugin fetch fails", func(t *testing.T) {
		svc := newTestService(t) // no plugin.json
		app := &mockAgenticApp{
			agentSource: &sweagentd.AgentSource{
				URL: testRepoURL,
				SHA: defaultTestSHA,
			},
		}

		_, _, err := svc.GetCustomAgentForApp(ctx, app)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "failed to get custom agent for app")
	})
}

func TestGetPluginConfigValidationMessage(t *testing.T) {
	// Produce a real ErrConfigValidationError by parsing config with missing description
	_, configValidationErr := customagent.ParseConfigForSync("---\nname: test-agent\n---\nsome prompt", "test")
	require.Error(t, configValidationErr)

	tests := []struct {
		name            string
		err             error
		expectedMessage string
		expectedIsUser  bool
	}{
		{
			name:            "ErrConfigValidationError returns validation message",
			err:             configValidationErr,
			expectedMessage: "Invalid config: field \"description\" is required",
			expectedIsUser:  true,
		},
		{
			name:            "ErrInvalidPluginConfig with detail",
			err:             goerrors.Errorf("%w: missing plugin.json", ErrInvalidPluginConfig),
			expectedMessage: "Invalid plugin configuration: missing plugin.json",
			expectedIsUser:  true,
		},
		{
			name:            "ErrInvalidPluginConfig without detail",
			err:             ErrInvalidPluginConfig,
			expectedMessage: ErrInvalidPluginConfig.Error(),
			expectedIsUser:  true,
		},
		{
			name:            "ErrAgentNotFoundInPlugin with detail",
			err:             goerrors.Errorf("%w: agent \"my-agent\" not found in plugin \"my-plugin\"", ErrAgentNotFoundInPlugin),
			expectedMessage: "Agent not found in plugin: agent \"my-agent\" not found in plugin \"my-plugin\"",
			expectedIsUser:  true,
		},
		{
			name:            "ErrAgentNotFoundInPlugin without detail",
			err:             ErrAgentNotFoundInPlugin,
			expectedMessage: ErrAgentNotFoundInPlugin.Error(),
			expectedIsUser:  true,
		},
		{
			name:            "ErrFailedToGetPlugin with detail",
			err:             goerrors.Errorf("%w: network timeout", ErrFailedToGetPlugin),
			expectedMessage: "Failed to get plugin: network timeout",
			expectedIsUser:  false,
		},
		{
			name:            "ErrFailedToGetPlugin without detail",
			err:             ErrFailedToGetPlugin,
			expectedMessage: ErrFailedToGetPlugin.Error(),
			expectedIsUser:  false,
		},
		{
			name:            "ErrFailedToGetPluginCustomAgent with detail",
			err:             goerrors.Errorf("%w: failed to read agent config for \"bot\": file not found", ErrFailedToGetPluginCustomAgent),
			expectedMessage: "Failed to get plugin agent: failed to read agent config for \"bot\": file not found",
			expectedIsUser:  false,
		},
		{
			name:            "ErrFailedToGetPluginCustomAgent without detail",
			err:             ErrFailedToGetPluginCustomAgent,
			expectedMessage: ErrFailedToGetPluginCustomAgent.Error(),
			expectedIsUser:  false,
		},
		{
			name:            "unknown error returns generic message",
			err:             goerrors.New("something totally unexpected"),
			expectedMessage: "An unexpected error occurred while processing agent plugin configuration.",
			expectedIsUser:  false,
		},
		{
			name:            "wrapped ErrInvalidPluginConfig includes sentinel and detail",
			err:             goerrors.Errorf("outer wrapper: %w: repo not found: owner/repo", ErrInvalidPluginConfig),
			expectedMessage: "Invalid plugin configuration: repo not found: owner/repo",
			expectedIsUser:  true,
		},
		{
			name:            "double wrapped ErrFailedToGetPlugin includes sentinel and detail",
			err:             goerrors.Errorf("level2: %w", goerrors.Errorf("%w: connection refused", ErrFailedToGetPlugin)),
			expectedMessage: "Failed to get plugin: connection refused",
			expectedIsUser:  false,
		},
		{
			name:            "double wrapped ErrAgentNotFoundInPlugin includes sentinel and detail",
			err:             goerrors.Errorf("outer: %w", goerrors.Errorf("%w: agent \"bot\" not found in plugin \"myplugin\"", ErrAgentNotFoundInPlugin)),
			expectedMessage: "Agent not found in plugin: agent \"bot\" not found in plugin \"myplugin\"",
			expectedIsUser:  true,
		},
		{
			name:            "triple wrapped ErrInvalidPluginConfig includes sentinel and detail",
			err:             goerrors.Errorf("a: %w", goerrors.Errorf("b: %w", goerrors.Errorf("%w: bad json", ErrInvalidPluginConfig))),
			expectedMessage: "Invalid plugin configuration: bad json",
			expectedIsUser:  true,
		},
		{
			name:            "deeply wrapped ErrFailedToGetPluginCustomAgent includes sentinel and detail",
			err:             goerrors.Errorf("orchestrator: %w", goerrors.Errorf("plugin service: %w", goerrors.Errorf("%w: read timeout for \"agent-x\"", ErrFailedToGetPluginCustomAgent))),
			expectedMessage: "Failed to get plugin agent: read timeout for \"agent-x\"",
			expectedIsUser:  false,
		},
		{
			name:            "deeply wrapped ErrConfigValidationError returns validation message",
			err:             goerrors.Errorf("outer: %w", goerrors.Errorf("inner: %w", configValidationErr)),
			expectedMessage: "Invalid config: field \"description\" is required",
			expectedIsUser:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			msg, isUserError := GetPluginConfigValidationMessage(tt.err)
			assert.Equal(t, tt.expectedMessage, msg)
			assert.Equal(t, tt.expectedIsUser, isUserError)
		})
	}
}
