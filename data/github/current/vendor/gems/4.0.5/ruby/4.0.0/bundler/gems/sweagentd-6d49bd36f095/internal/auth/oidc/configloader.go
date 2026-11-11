package oidc

import (
	"context"
	"encoding/json"
	"errors"
	"maps"
	"slices"
	"time"

	"github.com/github/go-stats"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/auth/oidc/varfetcher"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"go.opentelemetry.io/otel/codes"
)

const platformConfigPath = ".github/copilot/settings.json"

const repoMCPJSONPath = ".mcp.json"

// ConfigLoader is responsible for loading OIDC configuration from various sources like settings.json
// and MCP server config, and mapping them to MCP server names and secret names for a repository.
type ConfigLoader struct {
	ffClient        featureflags.Client
	spokes          sweagentd.Spokes
	ghTwirp         githubtwirp.ClientInterface
	obsv            observability.Exporters
	variableFetcher varfetcher.VariableFetcher
	localOnly       bool
}

// NewConfigLoader creates a new ConfigLoader with the given dependencies.
func NewConfigLoader(ffClient featureflags.Client, spokesClient sweagentd.Spokes, ghTwirp githubtwirp.ClientInterface, obsv observability.Exporters, variableFetcher varfetcher.VariableFetcher) *ConfigLoader {
	return &ConfigLoader{
		ffClient:        ffClient,
		spokes:          spokesClient,
		ghTwirp:         ghTwirp,
		obsv:            obsv,
		variableFetcher: variableFetcher,
		localOnly:       false,
	}
}

// NewLocalConfigLoader creates a ConfigLoader that does not have access to GitHub and will not attempt
// to load any configuration from GitHub (e.g. from settings.json or MCP config). This is
// useful for testing or local development where the full GitHub environment is not available.
func NewLocalConfigLoader(ffClient featureflags.Client, obsv observability.Exporters, variableFetcher varfetcher.VariableFetcher) *ConfigLoader {
	return &ConfigLoader{
		ffClient:        ffClient,
		spokes:          nil,
		ghTwirp:         nil,
		obsv:            obsv,
		variableFetcher: variableFetcher,
		localOnly:       true,
	}
}

// mcpConfigProvider is satisfied by CustomAgent implementations that provide
// MCP server configuration.
type mcpConfigProvider interface {
	MCPConfig() mcpconfig.JSON
}

// MappedConfig represents the OIDC configuration mapped to MCP server names and secret names for a repository.
type MappedConfig struct {
	// Map of MCP server name to OIDC config entry for servers that have OIDC config.
	MCPServerNameMap map[string]*oidcconfig.ConfigEntry
	// Map of OIDC secret suffix to OIDC config entry for all OIDC configs, used for looking up by secret name.
	SecretMap map[string]*oidcconfig.ConfigEntry
}

func newMCPConfigEntry(name string, server mcpconfig.Server) (oidcconfig.ConfigEntry, error) {
	var serverURL string
	if server.Remote != nil {
		serverURL = server.URL
	}
	entry := oidcconfig.NewConfigEntryForMCP(name, serverURL, *server.Auth)
	if entry.Endpoints.Base != "" {
		// Validate post-resolution: all variables should be substituted by now.
		err := entry.Validate()
		if err != nil {
			return oidcconfig.ConfigEntry{}, goerrors.Errorf("auth.%w", err)
		}
		return entry, nil
	}

	if mcpconfig.IsRemote(server.Type) && serverURL != "" {
		sanitizedURL, err := sanitizeURL(serverURL)
		if err != nil {
			return oidcconfig.ConfigEntry{}, goerrors.Errorf("%w: invalid remote MCP server URL for %q: %w", ErrInvalidURL, name, err)
		}
		entry.Endpoints.Base = sanitizedURL.String()
	}

	// Validate post-resolution: all variables should be substituted by now.
	err := entry.Validate()
	if err != nil {
		return oidcconfig.ConfigEntry{}, goerrors.Errorf("auth.%w", err)
	}

	return entry, nil
}

// filterMCPServers returns a shallow copy of cfg containing only the servers
// whose names are in filter. If filter is nil, cfg is returned unchanged
// (no filtering = process all servers).
func filterMCPServers(cfg mcpconfig.JSON, filter map[string]bool) mcpconfig.JSON {
	if filter == nil || len(cfg.Servers) == 0 {
		return cfg
	}
	filtered := mcpconfig.JSON{Servers: make(map[string]mcpconfig.Server, len(filter))}
	for name, server := range cfg.Servers {
		if filter[name] {
			filtered.Servers[name] = server
		}
	}
	return filtered
}

// Load gathers the OIDC configuration from settings.json and merges it with any inline OIDC
// entries found in the repo-level MCP server configuration. If
// CopilotSWEAgentOIDCUseRepoRootMCPJSON is enabled for the repo or user, repo-root .mcp.json
// OIDC entries are also merged. If agent is non-nil, its MCP config is merged in, with agent
// config taking precedence in case of conflicts. appMCPConfigs are MCP configurations from the
// agentic app's own plugin (use agentic app identity). additionalMCPConfigs are extra MCP
// configurations (e.g. from repo plugins) to merge after the repo-level MCP config and after repo
// .mcp.json when that feature flag is enabled, but before app and agent MCP configs.
//
// If serverFilter is non-nil, only MCP servers whose names are in the filter are resolved
// and processed; this avoids expensive variable fetching for servers that will not be used.
//
// Order of precedence for naming conflicts:
//
// settings.json (if enabled) < non-file repo mcp config < repo .mcp.json (if CopilotSWEAgentOIDCUseRepoRootMCPJSON is enabled) < additional MCP configs < app MCP configs < agent MCP config
//
// TODO (chuxel): Store the default branch SHA on job so we can pin to a specific version of repo artifacts
// TODO (chuxel): Repo level (non-file based) config is not versioned - do we accept that? Track a last updated date and fail if it was updated after the job started? Drop support?
// TODO (chuxel): Add caching or persistence so we don't have to fetch and parse the config on every request
func (c *ConfigLoader) Load(ctx context.Context, params ResolveConfigurationParams, serverFilter map[string]bool) ([]oidcconfig.ConfigEntry, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "oidc.ConfigLoader.Load")
	defer span.End()

	start := time.Now()

	entries, err := c.doLoad(ctx, params, serverFilter, start)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
	return entries, err
}

func (c *ConfigLoader) doLoad(ctx context.Context, params ResolveConfigurationParams, serverFilter map[string]bool, start time.Time) ([]oidcconfig.ConfigEntry, error) {
	var resolver *variableResolver
	if c.variableFetcher != nil {
		resolver = newVariableResolver(c.variableFetcher, params.App, params.RepoID)
	}

	// 1. Load config from all the things

	var err error
	jsonCfg := &oidcconfig.Config{}
	if c.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentOIDCSettingsJSON, params.ActorID, params.RepoID) {
		// Load base OIDC config from settings.json if it exists
		jsonCfg, err = c.loadFromSettingsJSON(ctx, params.RepoID)
		if err != nil {
			c.recordLoadMetrics(ctx, "error", 0, time.Since(start))
			return nil, goerrors.Errorf("failed to load OIDC config from settings.json: %w", err)
		}
	}

	// Get repo config if any.
	rawRepoMCPCfg, mcpEnabled, err := c.loadRepoMCPConfigRaw(ctx, params.RepoID, params.ActorID)
	if err != nil {
		c.recordLoadMetrics(ctx, "error", 0, time.Since(start))
		return nil, goerrors.Errorf("failed to get repo (non-file) MCP OIDC config: %w", err)
	}
	if !mcpEnabled {
		// Return any non-MCP config if it exists
		c.recordLoadMetrics(ctx, "success", len(jsonCfg.OIDCConfig), time.Since(start))
		return jsonCfg.OIDCConfig, nil
	}

	// Load .mcp.json raw (if enabled)
	var rawRepoMCPJSON mcpconfig.JSON
	if c.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentOIDCUseRepoRootMCPJSON, params.ActorID, params.RepoID) {
		rawRepoMCPJSON, err = c.loadRepoMCPJSONFileRaw(ctx, params.RepoID)
		if err != nil {
			c.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to load OIDC config from repo .mcp.json")
		}
	}

	// Get agent MCP config (if present)
	var rawAgentMCPCfg mcpconfig.JSON
	if params.Agent != nil {
		if a, ok := params.Agent.(mcpConfigProvider); ok {
			rawAgentMCPCfg = a.MCPConfig()
		}
	}

	// 2. Filter MCP sources to only the servers we need before resolving variables,
	//    avoiding expensive variable fetching for servers that will not be used.

	additionalMCPConfigs := params.AdditionalMCPConfigs
	appMCPConfigs := params.AppMCPConfigs
	rawRepoMCPCfg = filterMCPServers(rawRepoMCPCfg, serverFilter)
	rawRepoMCPJSON = filterMCPServers(rawRepoMCPJSON, serverFilter)
	for i, cfg := range additionalMCPConfigs {
		additionalMCPConfigs[i] = filterMCPServers(cfg, serverFilter)
	}
	for i, cfg := range appMCPConfigs {
		appMCPConfigs[i] = filterMCPServers(cfg, serverFilter)
	}
	rawAgentMCPCfg = filterMCPServers(rawAgentMCPCfg, serverFilter)

	// 3. Fetch and resolve variables across ALL config sources at once so each
	//    variable is fetched at most once regardless of how many sources reference it.

	if resolver != nil {
		allConfigs := []mcpconfig.JSON{rawRepoMCPCfg, rawRepoMCPJSON}
		allConfigs = append(allConfigs, additionalMCPConfigs...)
		allConfigs = append(allConfigs, appMCPConfigs...)
		allConfigs = append(allConfigs, rawAgentMCPCfg)
		err := resolver.fetchVariables(ctx, allConfigs)
		if err != nil {
			c.recordLoadMetrics(ctx, "error", 0, time.Since(start))
			return nil, goerrors.Errorf("failed to fetch MCP config variables: %w", err)
		}
		rawRepoMCPCfg = resolver.resolve(rawRepoMCPCfg)
		rawRepoMCPJSON = resolver.resolve(rawRepoMCPJSON)
		for i, cfg := range additionalMCPConfigs {
			additionalMCPConfigs[i] = resolver.resolve(cfg)
		}
		for i, cfg := range appMCPConfigs {
			appMCPConfigs[i] = resolver.resolve(cfg)
		}
		rawAgentMCPCfg = resolver.resolve(rawAgentMCPCfg)
	}

	// 4. Merge config in order so that naming conflicts are resolved according to precedence rules,
	//    with later sources overwriting earlier ones.

	// Process repo MCP config into OIDC entries
	mcpOIDC, err := c.fromMCPJSON(rawRepoMCPCfg)
	if err != nil {
		c.recordLoadMetrics(ctx, "error", 0, time.Since(start))
		return nil, goerrors.Errorf("failed to process repo MCP OIDC config: %w", err)
	}

	// Merge repo .mcp.json OIDC entries
	if len(rawRepoMCPJSON.Servers) > 0 {
		repoMCPJSON, err := c.fromMCPJSON(rawRepoMCPJSON)
		if err != nil {
			c.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to load OIDC config from repo .mcp.json")
		} else {
			maps.Copy(mcpOIDC, repoMCPJSON)
		}
	}

	// Merge additional MCP configs — these servers overwrite repo servers with the same name (according to current rules).
	// Order matters, so given how map.Copy works, iterate in reverse order so that the top of the list takes precedence over those at the bottom.
	for _, mcpConfig := range slices.Backward(additionalMCPConfigs) {
		additionalOIDC, err := c.fromMCPJSON(mcpConfig)
		if err != nil {
			c.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to load OIDC config from additional MCP config")
			continue
		}
		maps.Copy(mcpOIDC, additionalOIDC)
	}

	// Merge app plugin MCP configs — these are from the agentic app's own plugin and use agentic app identity.
	// These should "win" over any previous MCP config entries with the same server name, but order also matter, so reverse again.
	for _, mcpConfig := range slices.Backward(appMCPConfigs) {
		appOIDC, err := c.fromAgenticAppMCPJSON(mcpConfig)
		if err != nil {
			c.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to load OIDC config from app MCP config")
			continue
		}
		maps.Copy(mcpOIDC, appOIDC)
	}

	// Merge custom agent MCP config — agent servers overwrite all others with the same name.
	if len(rawAgentMCPCfg.Servers) > 0 {
		var agentCfg map[string]oidcconfig.ConfigEntry
		if params.AgentFromApp {
			agentCfg, err = c.fromAgenticAppMCPJSON(rawAgentMCPCfg)
		} else {
			agentCfg, err = c.fromMCPJSON(rawAgentMCPCfg)
		}
		if err != nil {
			c.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to load OIDC config from agent MCP config")
		} else {
			maps.Copy(mcpOIDC, agentCfg)
		}
	}

	entries := slices.Collect(maps.Values(mcpOIDC))
	entries = append(entries, jsonCfg.OIDCConfig...)

	c.recordLoadMetrics(ctx, "success", len(entries), time.Since(start))
	return entries, nil
}

func (c *ConfigLoader) recordLoadMetrics(ctx context.Context, status string, entryCount int, duration time.Duration) {
	tags := stats.Tags{"status": status}
	c.obsv.Increment(ctx, "oidc.config_load.count", tags)
	c.obsv.DistributionMs(ctx, "oidc.config_load.latency_ms", tags, duration)
	c.obsv.Distribution(ctx, "oidc.config_load.entries", tags, float64(entryCount))
}

// loadRepoMCPJSONFileRaw reads the .mcp.json file from the repository root via spokes
// and returns the parsed MCP configuration without any variable resolution.
func (c *ConfigLoader) loadRepoMCPJSONFileRaw(ctx context.Context, repoID int64) (mcpconfig.JSON, error) {
	if c.localOnly {
		return mcpconfig.JSON{}, nil
	}

	data, _, err := c.spokes.ReadBlob(ctx, uint64(repoID), repoMCPJSONPath)
	if err != nil {
		if errors.Is(err, spokes.ErrNotFound) {
			return mcpconfig.JSON{}, nil
		}
		return mcpconfig.JSON{}, goerrors.Errorf("failed to read .mcp.json: %w", err)
	}
	if data == nil {
		return mcpconfig.JSON{}, nil
	}

	var mcpCfg mcpconfig.JSON
	err = json.Unmarshal(data, &mcpCfg)
	if err != nil {
		return mcpconfig.JSON{}, goerrors.Errorf("failed to unmarshal .mcp.json: %w", err)
	}

	return mcpCfg, nil
}

// loadRepoMCPConfigRaw fetches and parses the MCP configuration JSON from the SweagentdAPI
// without any variable resolution.
func (c *ConfigLoader) loadRepoMCPConfigRaw(ctx context.Context, repoID, actorID int64) (mcpconfig.JSON, bool, error) {
	if c.localOnly {
		return mcpconfig.JSON{}, true, nil
	}

	resp, err := c.ghTwirp.SweagentdAPI().MCPConfigurationForRepository(ctx, &sweagentdv1.MCPConfigurationForRepositoryRequest{
		RepositoryId: uint64(repoID),
		UserId:       uint64(actorID),
	})
	if err != nil {
		return mcpconfig.JSON{}, false, goerrors.Errorf("failed to fetch MCP configuration: %w", err)
	}

	if !resp.IsMcpEnabled {
		return mcpconfig.JSON{}, false, nil
	}

	cfgStr := resp.McpConfigurationJson
	if cfgStr == "" {
		return mcpconfig.JSON{}, true, nil
	}

	var mcpCfg mcpconfig.JSON
	err = json.Unmarshal([]byte(cfgStr), &mcpCfg)
	if err != nil {
		return mcpconfig.JSON{}, false, goerrors.Errorf("failed to parse MCP configuration JSON: %w", err)
	}

	return mcpCfg, true, nil
}

// loadFromSettingsJSON fetches and parses the OIDC configuration from the repository's
// .github/copilot/settings.json file. Returns nil if the file does not exist or
// cannot be parsed.
func (c *ConfigLoader) loadFromSettingsJSON(ctx context.Context, repoID int64) (*oidcconfig.Config, error) {
	// We do not want to error out if spokes is nil since we will do this for tests, but we should log
	if c.localOnly {
		return &oidcconfig.Config{}, nil
	}

	data, _, err := c.spokes.ReadBlob(ctx, uint64(repoID), platformConfigPath)
	if err != nil {
		if errors.Is(err, spokes.ErrNotFound) {
			return &oidcconfig.Config{}, nil
		}
		return nil, goerrors.Errorf("failed to read settings.json: %w", err)
	}
	if data == nil {
		return &oidcconfig.Config{}, nil
	}

	cfg, err := oidcconfig.ParseConfig(data, oidcconfig.ConfigSourceSettings)
	if err != nil {
		return &oidcconfig.Config{}, goerrors.Errorf("failed to parse OIDC config from settings.json: %w", err)
	}

	return cfg, nil
}

// fromMCPJSON converts OIDC configuration entries from the MCP JSON config into a map of MCP server name to OIDC config entry.
func (c *ConfigLoader) fromMCPJSON(mcpJSON mcpconfig.JSON) (map[string]oidcconfig.ConfigEntry, error) {
	configs := make(map[string]oidcconfig.ConfigEntry, len(mcpJSON.Servers))
	for name, server := range mcpJSON.Servers {
		if server.Auth == nil {
			continue
		}
		if server.Tools == nil {
			server.Tools = []string{"*"}
		}
		entry, err := newMCPConfigEntry(name, server)
		if err != nil {
			return nil, goerrors.Errorf("failed to create MCP config entry for server %s: %w", name, err)
		}
		configs[name] = entry
	}
	return configs, nil
}

// fromAgenticAppMCPJSON creates a new OIDC config entry from an MCP server  definition that should be
// executed in the context of the agentic app rather than the platform identity.
func (c *ConfigLoader) fromAgenticAppMCPJSON(mcpJSON mcpconfig.JSON) (map[string]oidcconfig.ConfigEntry, error) {
	configs, err := c.fromMCPJSON(mcpJSON)
	if err != nil {
		// Pass through errors from fromMCPJSON
		return nil, err
	}
	for name, entry := range configs {
		entry.SetUseAgenticAppIdentity(true)
		configs[name] = entry
	}
	return configs, nil
}

// variableResolver extracts variable references from MCP configs, fetches
// their values via a VariableFetcher (which handles concurrent API calls
// internally), and caches the results locally so that each variable is
// fetched at most once.
//
// TODO (chuxel): Use our cache store instead of just storing this info in memory.
type variableResolver struct {
	fetch  varfetcher.VariableFetcher
	app    sweagentd.AgenticApp
	repoID int64
	cache  map[string]string
}

func newVariableResolver(fetch varfetcher.VariableFetcher, app sweagentd.AgenticApp, repoID int64) *variableResolver {
	return &variableResolver{fetch: fetch, app: app, repoID: repoID, cache: make(map[string]string)}
}

// fetchVariables extracts variable references from configs and fetches any
// values not already present in the cache via a single batch call.
func (r *variableResolver) fetchVariables(ctx context.Context, configs []mcpconfig.JSON) error {
	var names []string
	seen := make(map[string]bool)
	for _, cfg := range configs {
		for _, name := range mcpconfig.ExtractServiceProcessedVariableReferences(cfg) {
			if _, ok := r.cache[name]; !ok && !seen[name] {
				names = append(names, name)
				seen[name] = true
			}
		}
	}
	if len(names) == 0 {
		return nil
	}
	fetched, err := r.fetch(ctx, r.app, r.repoID, names)
	if err != nil {
		return err
	}
	maps.Copy(r.cache, fetched)
	return nil
}

// resolve returns a copy of cfg with cached variable values substituted.
func (r *variableResolver) resolve(cfg mcpconfig.JSON) mcpconfig.JSON {
	if r.cache == nil {
		r.cache = make(map[string]string)
	}
	return mcpconfig.ResolveServiceProcessedVariables(cfg, r.cache)
}
