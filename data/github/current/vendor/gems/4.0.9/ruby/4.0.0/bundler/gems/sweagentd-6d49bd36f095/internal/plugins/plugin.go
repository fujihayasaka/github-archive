package plugins

import (
	"context"
	"encoding/json"
	"errors"
	"path"
	"slices"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/sweagentd"
)

// pluginManifestCandidatePaths are the candidate paths for plugin.json within a plugin directory,
// tried in priority order matching the runtime's PLUGIN_MANIFEST_DIRS at:
// https://github.com/github/copilot-agent-runtime/blob/5ef5dcd94c34125747573e71d1a24b360dcfb68b/src/plugins/utils.ts#L18
var pluginManifestCandidatePaths = []string{
	".plugin/plugin.json",
	"plugin.json",
	".github/plugin/plugin.json",
	".claude-plugin/plugin.json",
}

var (
	// ErrFailedToGetPlugin is returned when the plugin could not be retrieved.
	ErrFailedToGetPlugin = goerrors.New("failed to get plugin")
	// ErrFailedToGetPluginCustomAgent is returned when the plugin agent could not be retrieved.
	ErrFailedToGetPluginCustomAgent = goerrors.New("failed to get plugin agent")
	// ErrAgentNotFoundInPlugin is returned when the requested agent is not found in the plugin.
	ErrAgentNotFoundInPlugin = goerrors.New("agent not found in plugin")
	// ErrInvalidPluginConfig is returned when there is an issue with the plugin configuration (e.g. missing or invalid plugin.json).
	ErrInvalidPluginConfig = goerrors.New("invalid plugin configuration")

	userErrors = []error{
		ErrAgentNotFoundInPlugin,
		ErrInvalidPluginConfig,
	}
)

// pluginManifestJSON is a partial parse of plugin.json to extract agent paths and plugin name.
type pluginManifestJSON struct {
	Name       string `json:"name,omitempty"`
	Agents     any    `json:"agents,omitempty"`
	MCPServers any    `json:"mcpServers,omitempty"`
}

// PluginJSON represents the parsed plugin.json manifest for a plugin.
type PluginJSON struct {
	Name   string   `json:"name,omitempty"`
	Agents []string `json:"agents,omitempty"`
	// MCPJSONPath is set when mcpServers is a string path in plugin.json.
	MCPJSONPath string `json:"-"`
	// InlineMCPServers is set when mcpServers is an inline object in plugin.json.
	InlineMCPServers map[string]mcpconfig.Server `json:"-"`
}

// UnmarshalJSON converts the plugins array from the wire format to a map keyed by name.
func (p *PluginJSON) UnmarshalJSON(data []byte) error {
	var raw pluginManifestJSON
	err := json.Unmarshal(data, &raw)
	if err != nil {
		return err
	}
	p.Name = raw.Name
	switch v := raw.Agents.(type) {
	case string:
		p.Agents = []string{v}
	case []any:
		agents := []string{}
		for _, item := range v {
			if str, ok := item.(string); ok {
				agents = append(agents, str)
			}
		}
		p.Agents = agents
	default:
		// Do nothing if the agents field is not a string or array
	}

	// mcpServers can be a string path or an inline object
	switch v := raw.MCPServers.(type) {
	case string:
		p.MCPJSONPath = v
	case map[string]any:
		// Re-marshal and unmarshal through mcpconfig.JSON to get proper typing
		wrapped := map[string]any{"mcpServers": v}
		b, marshalErr := json.Marshal(wrapped)
		if marshalErr != nil {
			return marshalErr
		}
		var mcpJSON mcpconfig.JSON
		unmarshalErr := json.Unmarshal(b, &mcpJSON)
		if unmarshalErr != nil {
			return unmarshalErr
		}
		p.InlineMCPServers = mcpJSON.Servers
	default:
		// Do nothing if the mcpServers field is not a string or object
	}
	return nil
}

// GetPlugin fetches config info about a given plugin in a repository.
func (s *Service) GetPlugin(ctx context.Context, meta PluginMetadata) (*Plugin, error) {
	// Get actual config data
	cfg, err := s.getPluginConfig(ctx, meta)
	if err != nil {
		return nil, goerrors.Errorf("%w: %w", ErrFailedToGetPlugin, err)
	}

	return &Plugin{
		Meta: meta,
		Info: cfg,
	}, nil
}

// GetPluginAgent fetches a custom agent from a plugin repository and returns it
// as a PrivilegedAgent with extended capabilities (MCP config, custom permissions).
func (s *Service) GetPluginAgent(ctx context.Context, plugin *Plugin, agentName string) (sweagentd.CustomAgent, error) {
	info := plugin.Info
	agentPath, ok := info.AgentPaths[agentName]
	if !ok {
		// Try appending the plugin name to the agent name
		agentPath, ok = info.AgentPaths[plugin.Info.Name+"/"+agentName]
		if !ok {
			return nil, goerrors.Errorf("%w: agent %q not found in plugin %q", ErrAgentNotFoundInPlugin, agentName, plugin.Info.Name)
		}
	}

	// Form metadata for the custom agent
	m := customagent.Metadata{
		Name:      agentName,
		RepoID:    info.RepoID,
		RepoOwner: info.RepoOwner,
		RepoName:  info.RepoName,
		Filename:  path.Base(agentPath),
		Version:   info.OID,
		Scope:     agentconfig.ScopePlugin,
	}

	// Read the config from the path
	rawConfig, err := s.spokes.ReadBlobByObjectIDPath(ctx, uint64(info.RepoID), info.OID, agentPath)
	if err != nil {
		return nil, goerrors.Errorf("%w: failed to read agent config for %q: %w", ErrFailedToGetPluginCustomAgent, agentName, err)
	}

	// Parse the config for the agent
	attrs, err := customagent.ParseConfigForSync(string(rawConfig), agentName)
	if err != nil {
		var configError *customagent.ErrConfigValidationError
		if errors.As(err, &configError) {
			return nil, goerrors.Errorf("%w: invalid custom agent config for %q: %w", ErrInvalidPluginConfig, agentName, err)
		}
		return nil, goerrors.Errorf("%w: failed to parse agent config for %q: %w", ErrFailedToGetPluginCustomAgent, agentName, err)
	}

	agent := customagent.NewWithConfig(m, customagent.NewConfigWithAttributes(attrs))
	return customagent.NewPrivilegedAgent(agent), nil
}

// GetPluginForApp attempts to resolve a custom agent for the given agentic app using the provided plugin service.
func (s *Service) GetPluginForApp(ctx context.Context, app sweagentd.AgenticApp) (*Plugin, error) {
	// If the resolved agent is copilot and there's no agentic app source, return
	agentSource := app.AgentSource()
	if agentSource == nil || agentSource.URL == "" {
		return nil, nil
	}

	plugin, err := s.GetPlugin(ctx, PluginMetadata{
		CloneURL: agentSource.URL,
		SHA:      agentSource.SHA,
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to get plugin for app: %w", err)
	}
	return plugin, nil
}

// GetCustomAgentForApp attempts to resolve a custom agent for the given agentic app using the provided plugin service.
func (s *Service) GetCustomAgentForApp(ctx context.Context, app sweagentd.AgenticApp) (sweagentd.CustomAgent, *Plugin, error) {
	plugin, err := s.GetPluginForApp(ctx, app)
	if err != nil {
		return nil, nil, goerrors.Errorf("failed to get custom agent for app: %w", err)
	}

	// If no plugin was found for the app, return
	if plugin == nil {
		return nil, nil, nil
	}

	pluginAgent, err := s.GetPluginAgent(ctx, plugin, "main")
	if err != nil {
		return nil, plugin, goerrors.Errorf("failed to get custom agent for app: %w", err)
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("loaded agentic app custom agent",
		kvp.Int64("agent_id", app.AppID()),
		kvp.String("app_name", app.AppName()),
		kvp.String("repo", plugin.Info.RepoOwner+"/"+plugin.Info.RepoName),
		kvp.String("sha", plugin.Info.OID),
	)

	return pluginAgent, plugin, nil
}

// resolveRepoIDAndOIDFromMetadata resolves the repository ID from a GitHub URL via ghtwirp and
// the commit OID. If ref is empty, the default branch OID is used.
func (s *Service) resolveRepoIDAndOIDFromMetadata(ctx context.Context, owner, repoName string, meta PluginMetadata) (uint64, string, error) {
	repo, err := s.ghtwirp.GetRepoByName(ctx, owner, repoName)
	if err != nil {
		return 0, "", goerrors.Errorf("%w: failed to resolve repo %s/%s: %w", ErrFailedToGetPlugin, owner, repoName, err)
	}
	if repo == nil {
		return 0, "", goerrors.Errorf("%w: repo not found: %s/%s", ErrFailedToGetPlugin, owner, repoName)
	}
	repoID := uint64(repo.GetId())

	if meta.SHA != "" {
		return repoID, meta.SHA, nil
	}

	var oid string
	if meta.Ref == "" {
		oid, err = s.spokes.GetDefaultBranchOID(ctx, repoID)
	} else {
		oid, err = s.spokes.GetObjectIDForRef(ctx, repoID, meta.Ref)
	}
	if err != nil {
		return 0, "", goerrors.Errorf("%w: failed to resolve ref: %w", ErrFailedToGetPlugin, err)
	}

	return repoID, oid, nil
}

// getPluginConfig fetches plugin config using spokes to read from the repository.
// It returns the config along with the plugin name and marketplace name parsed from manifests.
func (s *Service) getPluginConfig(ctx context.Context, meta PluginMetadata) (PluginInfo, error) {
	if meta.CloneURL == "" {
		return PluginInfo{}, goerrors.Errorf("%w: missing clone URL for plugin - unable to process non-repository plugins", ErrInvalidPluginConfig)
	}

	// Block on repositories that do not match the current github instance (based on the git URL)
	owner, repoName, _ := extractNWO(meta.CloneURL, s.githubServerURL)
	if owner == "" || repoName == "" {
		return PluginInfo{}, goerrors.Errorf("%w: invalid source URL %q: could not extract owner and repo", ErrInvalidPluginConfig, meta.CloneURL)
	}

	repoID, oid, err := s.resolveRepoIDAndOIDFromMetadata(ctx, owner, repoName, meta)
	if err != nil {
		return PluginInfo{}, err
	}

	info := PluginInfo{
		RepoID:    int64(repoID),
		RepoName:  repoName,
		RepoOwner: owner,
		OID:       oid,
	}

	// Read plugin.json and optionally .mcp.json
	pj, mcp, err := s.readPluginArtifacts(ctx, repoID, oid, meta)
	if err != nil {
		return PluginInfo{}, err
	}
	info.Name = pj.Name
	if len(mcp.Servers) > 0 {
		info.MCPServers = mcp.Servers
	}

	// Get agent paths (if any)
	agents, err := s.readPluginAgentNames(ctx, repoID, oid, pj, meta)
	if err != nil {
		return PluginInfo{}, err
	}
	info.AgentPaths = agents

	return info, nil
}

// readPluginArtifacts gets plugin.json and MCP server config from the repository.
// MCP config is resolved from plugin.json's mcpServers field: inline object, string
// path, or defaults to ".mcp.json"  / ".github/mcp.json" when absent.
func (s *Service) readPluginArtifacts(ctx context.Context, repoID uint64, oid string, meta PluginMetadata) (PluginJSON, mcpconfig.JSON, error) {
	candidatePaths := make([]string, 0, len(pluginManifestCandidatePaths))
	for _, p := range pluginManifestCandidatePaths {
		cleaned := path.Clean(p)
		if cleaned == "." || isUnsafePath(cleaned) {
			continue
		}
		candidatePaths = append(candidatePaths, joinPluginPath(meta, cleaned))
	}

	blobs, err := s.spokes.ReadBlobsByPaths(ctx, repoID, oid, candidatePaths)
	if err != nil {
		return PluginJSON{}, mcpconfig.JSON{}, err
	}

	// Resolve plugin.json
	var pj *PluginJSON
	for _, blob := range blobs {
		if len(blob) == 0 {
			continue
		}
		var parsed PluginJSON
		unmarshalErr := json.Unmarshal(blob, &parsed)
		if unmarshalErr != nil {
			return PluginJSON{}, mcpconfig.JSON{}, goerrors.Errorf("%w: invalid plugin.json: %w", ErrInvalidPluginConfig, unmarshalErr)
		}
		pj = &parsed
		break
	}
	if pj == nil {
		return PluginJSON{}, mcpconfig.JSON{}, goerrors.Errorf("%w: no valid plugin.json found", ErrInvalidPluginConfig)
	}
	if pj.Name == "" && meta.MarketplaceName != "" {
		pj.Name = meta.MarketplacePluginName
	}

	// Resolve MCP config from plugin.json's mcpServers field.
	// When absent, default to loading ".mcp.json" or ".github/mcp.json".
	mcp, err := s.readPluginMCPServers(ctx, repoID, oid, pj, meta)
	if err != nil {
		return PluginJSON{}, mcpconfig.JSON{}, err
	}

	return *pj, mcp, nil
}

// readPluginMCPServers resolves MCP server configuration from plugin.json's mcpServers field.
// It handles three cases: inline object, string path to a JSON file, or defaults to
// ".mcp.json" / ".github/mcp.json" (tried in order) when absent.
func (s *Service) readPluginMCPServers(ctx context.Context, repoID uint64, oid string, pj *PluginJSON, meta PluginMetadata) (mcpconfig.JSON, error) {
	// Inline mcpServers object — use directly
	if pj.InlineMCPServers != nil {
		mcp := mcpconfig.JSON{Servers: pj.InlineMCPServers}
		applyDefaultTools(&mcp)
		return mcp, nil
	}

	// Determine which file(s) to load: explicit path or defaults
	mcpPaths := []string{joinPluginPath(meta, ".mcp.json"), joinPluginPath(meta, ".github/mcp.json")}
	if pj.MCPJSONPath != "" {
		cleanPath := path.Clean(strings.TrimPrefix(pj.MCPJSONPath, "./"))
		if cleanPath != "." && !strings.HasPrefix(cleanPath, "..") && !strings.HasPrefix(cleanPath, "/") {
			mcpPaths = []string{joinPluginPath(meta, cleanPath)}
		}
	}

	mcpBlobs, err := s.spokes.ReadBlobsByPaths(ctx, repoID, oid, mcpPaths)
	if err != nil {
		pathDesc := mcpPaths[0]
		if pj.MCPJSONPath != "" {
			pathDesc = pj.MCPJSONPath
		}
		return mcpconfig.JSON{}, goerrors.Errorf("%w: failed to read MCP config file %q: %w", ErrFailedToGetPlugin, pathDesc, err)
	}

	// Use the first non-empty blob found
	for i, blob := range mcpBlobs {
		if len(blob) == 0 {
			continue
		}
		var mcp mcpconfig.JSON
		unmarshalErr := json.Unmarshal(blob, &mcp)
		if unmarshalErr != nil {
			source := mcpPaths[i]
			if pj.MCPJSONPath != "" {
				source = pj.MCPJSONPath
			}
			return mcpconfig.JSON{}, goerrors.Errorf("%w: invalid MCP config at %q: %w", ErrInvalidPluginConfig, source, unmarshalErr)
		}
		applyDefaultTools(&mcp)
		return mcp, nil
	}

	return mcpconfig.JSON{}, nil
}

// applyDefaultTools sets tools to ["*"] for any server that doesn't specify tools.
func applyDefaultTools(mcp *mcpconfig.JSON) {
	for name, server := range mcp.Servers {
		if server.Tools == nil {
			server.Tools = []string{"*"}
			mcp.Servers[name] = server
		}
	}
}

func (s *Service) readPluginAgentNames(ctx context.Context, repoID uint64, oid string, pluginJSON PluginJSON, meta PluginMetadata) (map[string]string, error) {
	agentPaths := pluginJSON.Agents
	if len(agentPaths) == 0 {
		agentPaths = []string{"agents"}
	}
	candidatePaths := make([]string, len(agentPaths))
	for i, p := range agentPaths {
		candidatePaths[i] = joinPluginPath(meta, p)
	}

	// List agent files from each directory
	agentsByName := make(map[string]string)
	for _, agentDir := range candidatePaths {
		dirPath := agentDir
		if !strings.HasSuffix(dirPath, "/") {
			dirPath += "/"
		}
		objs, err := s.spokes.ListTreesByObjectID(ctx, repoID, oid, dirPath)
		if err != nil {
			if errors.Is(err, spokes.ErrNotFound) {
				continue
			}
			return nil, err
		}
		for _, obj := range objs {
			if obj.IsDir {
				continue
			}
			name := path.Base(obj.Path)
			if !strings.HasSuffix(name, ".md") {
				continue
			}
			agentName := strings.TrimSuffix(strings.TrimSuffix(name, ".md"), ".agent")
			if agentName == "" {
				continue
			}
			agentsByName[agentName] = obj.Path
		}
	}
	return agentsByName, nil
}

func joinPluginPath(meta PluginMetadata, p string) string {
	if meta.Path == "" {
		return p
	}
	return path.Join(meta.Path, p)
}

// GetPluginConfigValidationMessage extracts a user-friendly error message from a plugin config error
// and whether or not the error is a user error. It handles custom agent config validation errors
// and strips wrapping prefixes from other known plugin config errors.
func GetPluginConfigValidationMessage(err error) (string, bool) {
	// Handle config errors for custom agents which are already set up to be surfaced directly.
	var configError *customagent.ErrConfigValidationError
	if errors.As(err, &configError) {
		return configError.ValidationMessage(), true
	}
	// Cut out all the wrapping prefixes and return the message after this section of the errors string in other cases
	for _, p := range []error{ErrInvalidPluginConfig, ErrAgentNotFoundInPlugin, ErrFailedToGetPlugin, ErrFailedToGetPluginCustomAgent} {
		if !errors.Is(err, p) {
			continue
		}
		userError := slices.Contains(userErrors, p)
		msg := err.Error()
		msgIdx := strings.Index(msg, p.Error()+":")
		if msgIdx == -1 {
			return p.Error(), userError
		}
		return strings.ToUpper(string(msg[msgIdx])) + msg[msgIdx+1:], userError
	}

	return "An unexpected error occurred while processing agent plugin configuration.", false
}
