package plugins

import (
	"context"
	"encoding/json"
	"path"
	"strings"

	"github.com/github/sweagentd/internal/goerrors"
)

// marketplaceCandidatePaths are the candidate paths for marketplace.json within a marketplace repo,
// tried in order to match the CLI's behavior.
var marketplaceCandidatePaths = []string{
	"marketplace.json",
	".plugin/marketplace.json",
	".github/plugin/marketplace.json",
	".claude-plugin/marketplace.json",
}

// DefaultMarketplaceName is the name of the default marketplace used when no marketplace is specified.
const DefaultMarketplaceName = "copilot-plugins"

// defaultMarketplaces contains the default marketplace mappings that match the CLI's DEFAULT_MARKETPLACES.
var defaultMarketplaces = map[string]string{
	"copilot-plugins": "github/copilot-plugins",
	"awesome-copilot": "github/awesome-copilot",
}

// marketplaceJSON is the wire format for marketplace.json where plugins is an array.
// Used internally to marshal/unmarshal MarketplaceData.
type marketplaceJSON struct {
	Name     string              `json:"name"`
	Metadata marketplaceMetadata `json:"metadata"`
	Plugins  []PluginEntry       `json:"plugins"`
}

// marketplaceMetadata contains optional metadata fields from marketplace.json.
type marketplaceMetadata struct {
	PluginRoot string `json:"pluginRoot,omitempty"`
}

// MarketplaceData represents the parsed contents of a marketplace.json file.
// Plugins are stored as a map keyed by name for efficient lookup.
type MarketplaceData struct {
	Name       string
	PluginRoot string
	Plugins    map[string]PluginEntry
	// object ID of the marketplace.json file for future reference.
	OID string
}

// UnmarshalJSON converts the plugins array from the wire format to a map keyed by name.
func (m *MarketplaceData) UnmarshalJSON(data []byte) error {
	var raw marketplaceJSON
	err := json.Unmarshal(data, &raw)
	if err != nil {
		return err
	}
	m.Name = raw.Name
	m.PluginRoot = strings.TrimPrefix(raw.Metadata.PluginRoot, "./")
	m.Plugins = make(map[string]PluginEntry, len(raw.Plugins))
	for _, p := range raw.Plugins {
		m.Plugins[p.Name] = p
	}
	return nil
}

// MarshalJSON converts the plugins map back to the wire format (array).
func (m MarketplaceData) MarshalJSON() ([]byte, error) {
	plugins := make([]PluginEntry, 0, len(m.Plugins))
	for _, p := range m.Plugins {
		plugins = append(plugins, p)
	}
	return json.Marshal(marketplaceJSON{
		Name:     m.Name,
		Metadata: marketplaceMetadata{PluginRoot: m.PluginRoot},
		Plugins:  plugins,
	})
}

// PluginEntry represents a plugin entry in a marketplace.json file.
type PluginEntry struct {
	Name        string       `json:"name"`
	Description string       `json:"description,omitempty"`
	Source      PluginSource `json:"source"`
}

// PluginSource is a union type matching the CLI's PluginSourceSchema.
// Source can be:
//   - "github": use Repo (and optionally Ref, Path)
//   - "url": use URL (and optionally Ref, Path)
//   - any other string: a local path relative to the marketplace repo (e.g., "./plugins/foo")
type PluginSource struct {
	// Source is the type ("github", "url") or a local path string (e.g., "./plugins/foo").
	Source string
	// Repo is the owner/repo for source: "github".
	Repo string
	// URL is the git URL for source: "url".
	URL string
	// Ref is the optional git ref for "github" and "url" sources.
	Ref string
	// SHA is the optional git SHA for "github" and "url" sources.
	SHA string
	// Path is an optional subpath within the repo for "github" and "url" sources.
	Path string
}

// pluginSourceObjectJSON is the wire format for the object form of PluginSource.
type pluginSourceObjectJSON struct {
	Source string `json:"source"`
	Repo   string `json:"repo,omitempty"`
	URL    string `json:"url,omitempty"`
	Ref    string `json:"ref,omitempty"`
	SHA    string `json:"sha,omitempty"`
	Path   string `json:"path,omitempty"`
}

// UnmarshalJSON handles the union type: plain string or object.
// If the value is a plain string, it is stored directly in Source (treated as a local path).
func (p *PluginSource) UnmarshalJSON(data []byte) error {
	var s string
	err := json.Unmarshal(data, &s)
	if err == nil {
		p.Source = s
		return nil
	}
	var obj pluginSourceObjectJSON
	err = json.Unmarshal(data, &obj)
	if err != nil {
		return err
	}
	p.Source = obj.Source
	p.Repo = obj.Repo
	p.URL = obj.URL
	p.Ref = obj.Ref
	p.SHA = obj.SHA
	p.Path = obj.Path
	return nil
}

// MarshalJSON marshals PluginSource back to the wire format.
// If Source is "github" or "url", marshals as an object. Otherwise marshals as a plain string.
func (p PluginSource) MarshalJSON() ([]byte, error) {
	if p.Source == "github" || p.Source == "url" {
		return json.Marshal(pluginSourceObjectJSON(p))
	}
	return json.Marshal(p.Source)
}

// resolveMarketplacePlugin resolves a marketplace plugin spec to a PluginMetadata.
// It fetches the marketplace.json and looks up the plugin source.
// Returns (nil, reason, nil) when resolution fails without err
func (s *Service) resolveMarketplacePlugin(
	ctx context.Context,
	parsed ParsedPluginSpec,
	marketplaces map[string]MarketplaceSourceConfig,
	cache map[string]*MarketplaceData,
) (*PluginMetadata, string, error) {
	marketplaceName := parsed.Marketplace
	if marketplaceName == "" {
		// Matches the CLI behavior: use the default marketplace if none is specified
		marketplaceName = DefaultMarketplaceName
	}

	marketplaceSource, ok := marketplaces[marketplaceName]
	// Ensure this maps to a known marketplace (Default + ExtraKnownMarketplaces )
	if !ok {
		return nil, "unknown marketplace: " + marketplaceName, nil
	}

	// In case multiple plugins come from the same marketplace
	marketplaceData, ok := cache[marketplaceName]
	if !ok {
		var fetchReason string
		var err error
		marketplaceData, fetchReason, err = s.fetchMarketplaceData(ctx, marketplaceSource)
		if err != nil {
			return nil, "", err
		}
		cache[marketplaceName] = marketplaceData
		if marketplaceData == nil {
			return nil, fetchReason, nil
		}
	}

	if marketplaceData == nil {
		// Cache hit but data was nil — a previous fetch for this marketplace already failed.
		// The first plugin from this marketplace already got the specific reason;
		// subsequent plugins get a generic message.
		return nil, "marketplace data could not be fetched", nil
	}

	pluginEntry, ok := marketplaceData.Plugins[parsed.PluginName]
	if !ok {
		return nil, "plugin \"" + parsed.PluginName + "\" not found in marketplace \"" + marketplaceName + "\"", nil
	}

	meta, reason := resolvePluginSource(marketplaceSource, marketplaceData, pluginEntry, s.githubServerURL)
	if meta != nil {
		meta.MarketplaceName = marketplaceData.Name
	}
	return meta, reason, nil
}

// fetchMarketplaceData fetches and parses marketplace.json from a marketplace source.
// Returns (nil, reason, nil) when the marketplace cannot be fetched — reason explains why.
func (s *Service) fetchMarketplaceData(ctx context.Context, source MarketplaceSourceConfig) (*MarketplaceData, string, error) {
	var input string
	switch source.Source {
	case "github":
		input = source.Repo
	case "git":
		input = source.URL
	default:
		return nil, "unsupported marketplace source type: " + source.Source, nil
	}

	owner, repoName, _ := extractNWO(input, s.githubServerURL)
	if owner == "" || repoName == "" {
		if source.Source == "git" {
			return nil, "marketplace git URL is not hosted on GitHub — CCA can only fetch marketplace data from GitHub repositories", nil
		}
		return nil, "invalid marketplace repo format: " + input, nil
	}

	repo, err := s.ghtwirp.GetRepoByName(ctx, owner, repoName)
	if err != nil {
		return nil, "", err
	}
	if repo == nil {
		return nil, "marketplace repository not found: " + owner + "/" + repoName, nil
	}
	repoID := uint64(repo.GetId())

	candidatePaths, reason := marketplaceCandidatePathsFor(source.Path)
	if reason != "" {
		return nil, reason, nil
	}

	var oid string
	if source.Ref == "" {
		oid, err = s.spokes.GetDefaultBranchOID(ctx, repoID)
	} else {
		oid, err = s.spokes.GetObjectIDForRef(ctx, repoID, source.Ref)
	}
	if err != nil {
		return nil, "", goerrors.Errorf("failed to resolve ref: %w", err)
	}

	// Does one spokes call for all locations to improve latency
	blobs, err := s.spokes.ReadBlobsByPaths(ctx, repoID, oid, candidatePaths)
	if err != nil {
		return nil, "", err
	}
	for _, blob := range blobs {
		if len(blob) == 0 {
			continue
		}
		var data MarketplaceData
		unmarshalErr := json.Unmarshal(blob, &data)
		if unmarshalErr != nil {
			return nil, "", unmarshalErr
		}
		data.OID = oid
		return &data, "", nil
	}
	suffix := ""
	if source.Path != "" {
		suffix = " (path: " + source.Path + ")"
	}
	return nil, "marketplace.json not found in repository " + owner + "/" + repoName + suffix, nil
}

// marketplaceCandidatePathsFor returns the candidate marketplace.json locations within a
// marketplace repo. When prefix is empty, the default top-level candidates are returned.
// When prefix is non-empty (from MarketplaceSourceConfig.Path), each candidate is joined
// under that prefix. Returns (nil, reason) if the prefix is unsafe (absolute or traversing).
func marketplaceCandidatePathsFor(prefix string) ([]string, string) {
	if prefix == "" {
		return marketplaceCandidatePaths, ""
	}
	cleaned := path.Clean(prefix)
	if isUnsafePath(cleaned) {
		return nil, "invalid marketplace path: absolute or traversal paths are not allowed"
	}
	if cleaned == "." {
		return marketplaceCandidatePaths, ""
	}
	out := make([]string, len(marketplaceCandidatePaths))
	for i, p := range marketplaceCandidatePaths {
		out[i] = path.Join(cleaned, p)
	}
	return out, ""
}

// resolvePluginSource converts a marketplace PluginEntry to a PluginMetadata.
// marketplaceSource is needed to derive the clone URL for local plugins.
// pluginRoot is the optional base directory from marketplace metadata, prepended to local paths.
// Returns (nil, reason) when the source cannot be resolved.
func resolvePluginSource(marketplaceSource MarketplaceSourceConfig, marketplaceData *MarketplaceData, entry PluginEntry, githubServerURL string) (*PluginMetadata, string) {
	source := entry.Source
	pluginRoot := marketplaceData.PluginRoot
	meta := &PluginMetadata{
		MarketplacePluginName:        entry.Name,
		MarketplacePluginDescription: entry.Description,
	}

	if source.Source == "github" && source.Repo != "" {
		meta.CloneURL = strings.TrimRight(githubServerURL, "/") + "/" + source.Repo
		meta.Path = source.Path
		meta.Ref = source.Ref
		meta.SHA = source.SHA
		return meta, ""
	}

	if source.Source == "url" && source.URL != "" {
		meta.CloneURL = source.URL
		meta.Path = source.Path
		meta.Ref = source.Ref
		meta.SHA = source.SHA
		return meta, ""
	}

	// Plain string: local path relative to the marketplace repo
	if source.Source != "" {
		// Resolve the local plugin path relative to the plugin root, if provided
		localPath := source.Source
		if pluginRoot != "" {
			cleanedRoot := path.Clean(pluginRoot)
			cleanedLocal := path.Clean(strings.TrimPrefix(localPath, "./"))
			if isUnsafePath(cleanedRoot) || isUnsafePath(cleanedLocal) {
				// Don't allow path traversal outside of the plugin root
				return nil, "plugin path traversal detected: " + localPath
			}
			localPath = path.Join(cleanedRoot, cleanedLocal)
		}
		cleaned := path.Clean(localPath)
		// Don't allow path traversal outside of the plugin root
		if isUnsafePath(cleaned) {
			return nil, "plugin path traversal detected: " + localPath
		}
		meta.Path = cleaned
		// Set the clone URL based on the marketplace source
		switch marketplaceSource.Source {
		case "github":
			meta.CloneURL = strings.TrimRight(githubServerURL, "/") + "/" + marketplaceSource.Repo
			meta.SHA = marketplaceData.OID
		case "git":
			meta.CloneURL = marketplaceSource.URL
			meta.SHA = marketplaceData.OID
		default:
			return nil, "unsupported marketplace source type: " + marketplaceSource.Source
		}
		return meta, ""
	}

	return nil, "plugin has empty source configuration"
}
