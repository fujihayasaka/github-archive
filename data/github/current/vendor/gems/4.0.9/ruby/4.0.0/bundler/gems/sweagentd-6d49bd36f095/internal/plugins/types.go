// Package plugins provides plugin configuration loading and resolution for Copilot coding agent.
package plugins

import (
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
)

// PluginSpecType represents the type of plugin specification.
type PluginSpecType string

const (
	// PluginSpecTypeGitHub represents a GitHub repository plugin (owner/repo format).
	PluginSpecTypeGitHub PluginSpecType = "github"
	// PluginSpecTypeURL represents a direct URL plugin.
	PluginSpecTypeURL PluginSpecType = "url"
	// PluginSpecTypeMarketplace represents a marketplace plugin (plugin@marketplace format).
	PluginSpecTypeMarketplace PluginSpecType = "marketplace"
	// PluginSpecTypeLocal represents a local path plugin (./path or /path format).
	// Note: ../path inputs are classified as local but rejected as unsafe by ResolvePluginRepos.
	PluginSpecTypeLocal PluginSpecType = "local"
)

// Source type constants for include_sources URL parameter.
const (
	SourceTypeRepo       = "repo"
	SourceTypeOrg        = "org"
	SourceTypeEnterprise = "enterprise"
)

// ParsedPluginSpec represents a parsed plugin specification.
// The parser classifies the type and extracts marketplace fields if needed.
type ParsedPluginSpec struct {
	Type        PluginSpecType
	RawSpec     string
	PluginName  string // For marketplace type only
	Marketplace string // For marketplace type only
	// SHA is the optional FULL commit SHA the spec was pinned to via the `owner/repo@<sha>`
	// or `owner/repo:path@<sha>` syntax. Only set for PluginSpecTypeGitHub.
	SHA string
}

// SettingsJSON represents plugin settings as read from settings.json files
// at the repo, org, or enterprise level.
type SettingsJSON struct {
	// EnabledPlugins maps plugin spec strings to their enabled status.
	// Example: {"sentry@copilot-plugins": true, "owner/repo": false}
	EnabledPlugins map[string]bool `json:"enabledPlugins"`

	// ExtraKnownMarketplaces maps marketplace names to their source configuration.
	// Matches CLI's extraKnownMarketplaces schema with nested source object.
	ExtraKnownMarketplaces map[string]ExtraMarketplace `json:"extraKnownMarketplaces"`

	// StrictKnownMarketplaces is a policy gate: when set, only marketplaces matching
	// these sources may be used. Undefined/nil = no restrictions, empty slice = lockdown.
	// Only honored when set in enterprise managed settings.
	StrictKnownMarketplaces []MarketplaceSourceConfig `json:"strictKnownMarketplaces,omitempty"`

	// RejectedPlugins maps plugin spec strings to rejection reasons.
	// Populated during settings loading when a local plugin spec is found in a source where
	// the runtime cannot access it (org .github-private or enterprise repos).
	// These are emitted as ResolutionFailure entries by ResolvePluginRepos.
	// This field is not serialized to or deserialized from settings JSON files.
	RejectedPlugins map[string]string `json:"-"`
}

// ExtraMarketplace represents a marketplace configuration in extraKnownMarketplaces.
type ExtraMarketplace struct {
	Source MarketplaceSourceConfig `json:"source"`
}

// MarketplaceSourceConfig represents the source configuration for a marketplace entry in settings.json.
// Used both for actual marketplace sources (extraKnownMarketplaces) and for allowlist rules
// (strictKnownMarketplaces). Supported source types:
//   - "git":    full git URL with optional ref; URL must resolve to a GitHub repo
//   - "github": GitHub owner/repo shorthand with optional ref
type MarketplaceSourceConfig struct {
	// Source is the type: "git" or "github".
	Source string `json:"source"`
	// Path is an optional subdirectory within the marketplace repo.
	Path string `json:"path,omitempty"`
	// URL is used for "git" source type
	URL string `json:"url,omitempty"`
	// Repo is used for "github" source type (owner/repo format)
	Repo string `json:"repo,omitempty"`
	// Ref is the git ref (branch, tag, commit) for "git" and "github" types
	Ref string `json:"ref,omitempty"`
}

// PluginDTO represents a plugin that needs to be loaded by the runtime.
// For remote plugins: CloneURL is set, Path is the subpath within the cloned repo. If path is empty, the plugin is at the root of the repo.
// For local plugins: CloneURL is empty, Path is the local path (e.g., "./my-plugin").
// For failed resolutions: ResolutionFailure is set with a human-readable reason
type PluginDTO struct {
	// CloneURL is the git clone URL. Empty for local plugins and failed resolutions.
	CloneURL string `json:"clone_url,omitempty"`
	// Path is either:
	// - For remote plugins: the subpath within the cloned repo (empty = root)
	// - For local plugins: the local path relative to the working repo
	Path string `json:"path,omitempty"`
	// MarketplaceName is the name of the marketplace this plugin was resolved from.
	// Empty for direct GitHub/URL specs and local plugins.
	MarketplaceName string `json:"marketplace_name,omitempty"`
	// SHA is the git commit SHA to clone from. When set, the runtime fetches
	// exactly this commit instead of the default branch tip.
	SHA string `json:"sha,omitempty"`
	// Spec is the original plugin specification string from enabledPlugins (e.g., "sentry@copilot-plugins", "owner/repo").
	Spec string `json:"spec,omitempty"`
	// ResolutionFailure is a human-readable reason why the plugin could not be resolved.
	ResolutionFailure string `json:"resolution_failure,omitempty"`
}

// PluginMetadata contains metadata about a resolved plugin, including its source and identity.
// For failed resolutions, ResolutionFailure is set with a human-readable reason.
type PluginMetadata struct {
	// CloneURL is the git clone CloneURL. Empty for local plugins and failed resolutions.
	CloneURL string
	// Path is either:
	// - For remote plugins: the subpath within the cloned repo (empty = root)
	// - For local plugins: the local path relative to the working repo
	Path string
	// Ref is an optional git ref (branch, tag, or SHA) to pin the clone to.
	Ref string
	// SHA is an optional git SHA to pin the clone to.
	SHA string
	// MarketplaceName is the name of the marketplace if present
	MarketplaceName string
	// MarketplacePluginName is the name of the plugin in the marketplace (e.g. "sentry").
	MarketplacePluginName string
	// MarketplacePluginDescription is the description of the plugin in the marketplace.
	MarketplacePluginDescription string
	// Spec is the original plugin specification string from enabledPlugins.
	Spec string
	// ResolutionFailure is a human-readable reason why the plugin could not be resolved.
	ResolutionFailure string
}

// Plugin represents a plugin with its metadata and attributes.
type Plugin struct {
	Meta PluginMetadata
	Info PluginInfo
}

// PluginInfo contains detailed information about a plugin in a repository at a specific commit.
type PluginInfo struct {
	// Actual plugin name from plugin.json or inherited from marketplace metadata
	Name string `json:"name"`
	// Parse MCP servers from .mcp.json if found
	MCPServers map[string]mcpconfig.Server `json:"mcp_servers,omitzero"`
	// AgentPaths is a map of valid agent names to their file paths.
	AgentPaths map[string]string `json:"agent_names"`
	// Info about the repository the plugin is in
	RepoID    int64  `json:"repo_id"`
	RepoName  string `json:"repo_name"`
	RepoOwner string `json:"repo_owner"`
	// Git Object ID of the commit the for the plugin information
	OID string `json:"oid"`
}
