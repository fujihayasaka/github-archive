package plugins

import (
	"context"
	"encoding/json"
	"errors"
	"maps"
	"path"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/gitrepo"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
)

// Service represents the plugins service, responsible for fetching plugin settings and resolving plugin repositories.
type Service struct {
	obsv            observability.Exporters
	spokes          sweagentd.Spokes
	ghtwirp         githubtwirp.ClientInterface
	githubServerURL string
}

// NewService creates a new instance of the plugins service struct.
// githubServerURL is the base URL of the GitHub server (e.g. "https://github.com").
func NewService(obsv observability.Exporters, spokes sweagentd.Spokes, ghtwirp githubtwirp.ClientInterface, githubServerURL string) *Service {
	return &Service{
		obsv:            obsv,
		spokes:          spokes,
		ghtwirp:         ghtwirp,
		githubServerURL: githubServerURL,
	}
}

const (
	// orgRepoName is the name of the org-level .github repository.
	orgRepoName = ".github"
	// orgSettingsPath is the path to plugin settings in org/enterprise repos.
	// Org/enterprise repos drop the .github/ prefix since we're already in the .github repo.
	orgSettingsPath = "copilot/settings.json"
)

// LoadRepoSettings loads plugin settings from the repository.
// It reads from both .github/copilot/settings.json and .claude/settings.json,
// merging them with .github/copilot taking precedence.
// Returns empty settings if no settings files exist.
//
// strictKnownMarketplaces is an admin-only allowlist control: it is only
// honored when supplied from enterprise managed settings, so any value
// declared at the repo level is stripped here before merging.
func (s *Service) LoadRepoSettings(ctx context.Context, repoID uint64) (*SettingsJSON, error) {
	result := emptySettings()

	// Read in priority order: .claude first (lower), .github/copilot second (overwrites)
	for _, settingsPath := range []string{".claude/settings.json", ".github/copilot/settings.json"} {
		settings, err := s.loadSettingsFromRepo(ctx, repoID, settingsPath)
		if err != nil {
			return nil, err
		}
		settings.StrictKnownMarketplaces = nil
		mergeSettings(result, settings)
	}

	return result, nil
}

// LoadOrgSettings loads plugin settings from the org's .github and .github-private repos.
// Reads from copilot/settings.json (no .github/ prefix since we're already in the .github repo).
func (s *Service) LoadOrgSettings(ctx context.Context, orgOwner string) (*SettingsJSON, error) {
	result := emptySettings()

	for _, repoName := range []string{orgRepoName, orgRepoName + "-private"} {
		repo, err := s.ghtwirp.GetRepoByName(ctx, orgOwner, repoName)
		if err != nil {
			if errors.Is(err, githubtwirp.ErrRepoNotFound) {
				continue
			}
			s.obsv.Logger.WithContext(ctx).WithError(err).Warn("failed to look up org repo: " + repoName)
			continue
		}
		if repo == nil {
			continue
		}
		repoID := uint64(repo.GetId())
		settings, err := s.loadSettingsFromRepo(ctx, repoID, orgSettingsPath)
		if err != nil {
			s.obsv.Logger.WithContext(ctx).WithError(err).Warn("failed to load org plugin settings from " + orgOwner + "/" + repoName)
			continue
		}
		// strictKnownMarketplaces is an enterprise-only admin control; ignore it at the org level.
		settings.StrictKnownMarketplaces = nil
		if repoName == orgRepoName {
			// Public .github repo: convert local specs to remote GitHub specs pointing to this repo,
			// since the runtime can clone public repos.
			convertLocalPluginSpecsToRemote(settings, orgOwner, repoName)
		} else {
			// Private .github-private repo: reject local specs — the runtime cannot clone private repos.
			rejectLocalPluginSpecs(settings, "local plugins from org .github-private sources cannot be used in the CCA environment")
		}
		mergeSettings(result, settings)
	}

	return result, nil
}

// LoadEnterpriseSettings loads plugin settings from the enterprise's .github repo.
// Uses the EnterpriseAgents twirp call to resolve the enterprise repo ID.
func (s *Service) LoadEnterpriseSettings(ctx context.Context, ownerID uint64) (*SettingsJSON, error) {
	req := &sweagentdv1.EnterpriseAgentsRequest{
		FindAgentsBy: &sweagentdv1.EnterpriseAgentsRequest_OwnerId{
			OwnerId: ownerID,
		},
	}

	enterpriseResp, err := s.ghtwirp.SweagentdAPI().EnterpriseAgents(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) && twirpErr.Code() == twirp.NotFound {
			return emptySettings(), nil
		}
		return nil, err
	}

	repoID := enterpriseResp.GetRepositoryId()
	if repoID == 0 {
		return emptySettings(), nil
	}

	settings, err := s.loadSettingsFromRepo(ctx, repoID, orgSettingsPath)
	if err != nil {
		return nil, err
	}
	// Enterprise repos are always private — reject local specs the runtime cannot clone.
	rejectLocalPluginSpecs(settings, "local plugins from enterprise sources cannot be used in the CCA environment")
	return settings, nil
}

// LoadMergedSettings loads and merges plugin settings from repo, org, and enterprise levels.
// Merge priority: enterprise > org > repo (enterprise wins on collision).
// This is the inverse of custom agents/skills where repo takes priority.
// For plugins, higher-level admins (enterprise/org) can enforce or block plugin usage.
func (s *Service) LoadMergedSettings(ctx context.Context, repoID, ownerID uint64, ownerName string, includeSources []string) (*SettingsJSON, error) {
	if len(includeSources) == 0 {
		includeSources = []string{SourceTypeRepo, SourceTypeOrg, SourceTypeEnterprise}
	}

	result := emptySettings()

	// Load repo settings first (lowest priority base)
	if slices.Contains(includeSources, SourceTypeRepo) {
		repoSettings, err := s.LoadRepoSettings(ctx, repoID)
		if err != nil {
			return nil, err
		}
		mergeSettings(result, repoSettings)
	}

	// Org overwrites repo
	if slices.Contains(includeSources, SourceTypeOrg) {
		orgSettings, err := s.LoadOrgSettings(ctx, ownerName)
		if err != nil {
			s.obsv.Logger.WithContext(ctx).WithError(err).Warn("failed to load org plugin settings")
		} else {
			mergeSettings(result, orgSettings)
		}
	}

	// Enterprise overwrites everything
	if slices.Contains(includeSources, SourceTypeEnterprise) {
		enterpriseSettings, err := s.LoadEnterpriseSettings(ctx, ownerID)
		if err != nil {
			s.obsv.Logger.WithContext(ctx).WithError(err).Warn("failed to load enterprise plugin settings")
		} else {
			mergeSettings(result, enterpriseSettings)
		}
	}

	return result, nil
}

// ResolvePluginRepos resolves enabled plugins to a list of PluginMetadata that need to be loaded by the runtime.
// Each enabled plugin spec produces exactly one entry — either a successful one with CloneURL or a failure one
// with ResolutionFailure. Duplicate clone URLs are not deduped here; the runtime handles clone deduplication.
func (s *Service) ResolvePluginRepos(ctx context.Context, settings *SettingsJSON) ([]PluginMetadata, error) {
	if settings == nil || (len(settings.EnabledPlugins) == 0 && len(settings.RejectedPlugins) == 0) {
		return nil, nil
	}

	// Build combined marketplaces map (defaults + extra from settings)
	marketplaces := make(map[string]MarketplaceSourceConfig)
	for name, repo := range defaultMarketplaces {
		marketplaces[name] = MarketplaceSourceConfig{
			Source: "github",
			Repo:   repo,
		}
	}
	for name, extra := range settings.ExtraKnownMarketplaces {
		if extra.Source.Source == "directory" {
			s.obsv.Logger.WithContext(ctx).Warn("skipping directory marketplace '" + name + "': not supported in ephemeral CCA environment")
			continue
		}
		marketplaces[name] = extra.Source
	}

	marketplaceCache := make(map[string]*MarketplaceData)
	var metaList []PluginMetadata

	// Emit resolution failures for pre-rejected plugins (e.g., local specs from non-repo sources).
	for spec, reason := range settings.RejectedPlugins {
		metaList = append(metaList, PluginMetadata{Spec: spec, ResolutionFailure: reason})
	}

	for spec, enabled := range settings.EnabledPlugins {
		if !enabled {
			continue
		}

		parsed := parsePluginSpec(spec)

		switch parsed.Type {
		case PluginSpecTypeGitHub:
			owner, repo, path := extractNWO(parsed.RawSpec, s.githubServerURL)
			if owner == "" || repo == "" {
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "invalid GitHub plugin spec: could not extract owner and repo",
				})
				continue
			}
			if parsed.SHA != "" && !gitrepo.IsValidSHA(parsed.SHA) {
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "invalid GitHub plugin spec: '@' must be followed by a full commit SHA (40 or 64 chars)",
				})
				continue
			}
			cloneURL := strings.TrimRight(s.githubServerURL, "/") + "/" + owner + "/" + repo
			metaList = append(metaList, PluginMetadata{CloneURL: cloneURL, Path: path, SHA: parsed.SHA, Spec: spec})

		case PluginSpecTypeURL:
			cloneURL := parsed.RawSpec
			if cloneURL == "" {
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "empty remote URL",
				})
				continue
			}
			if owner, repo, _ := extractNWO(cloneURL, s.githubServerURL); owner == "" || repo == "" {
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "plugin url is not hosted on GitHub",
				})
				continue
			}
			metaList = append(metaList, PluginMetadata{CloneURL: cloneURL, Spec: spec})

		case PluginSpecTypeMarketplace:
			if parsed.PluginName == "" {
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "empty plugin name",
				})
				continue
			}
			if !isMarketplaceAllowed(parsed, marketplaces, settings.StrictKnownMarketplaces) {
				s.obsv.Logger.WithContext(ctx).Warn("marketplace not allowed by strictKnownMarketplaces policy: " + spec)
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "marketplace not allowed by strictKnownMarketplaces policy",
				})
				continue
			}
			resolved, reason, err := s.resolveMarketplacePlugin(ctx, parsed, marketplaces, marketplaceCache)
			if err != nil {
				s.obsv.Logger.WithContext(ctx).WithError(err).Warn("failed to resolve marketplace plugin: " + spec)
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "unexpected error resolving marketplace plugin",
				})
				continue
			}
			if resolved == nil {
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: reason,
				})
				continue
			}
			resolved.Spec = spec
			// Validate that the resolved clone URL (of plugin, not marketplace) is on GitHub
			if owner, repo, _ := extractNWO(resolved.CloneURL, s.githubServerURL); owner == "" || repo == "" {
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "resolved plugin source is not hosted on GitHub",
				})
				continue
			}
			metaList = append(metaList, *resolved)

		case PluginSpecTypeLocal:
			localPath := parsed.RawSpec
			cleaned := path.Clean(localPath)
			if isUnsafePath(cleaned) {
				s.obsv.Logger.WithContext(ctx).Warn("rejecting invalid local plugin path: " + localPath)
				metaList = append(metaList, PluginMetadata{
					Spec:              spec,
					ResolutionFailure: "invalid local plugin path: absolute or traversal paths are not allowed",
				})
				continue
			}
			metaList = append(metaList, PluginMetadata{Path: localPath, Spec: spec})

		default:
			s.obsv.Logger.WithContext(ctx).Warn("unknown plugin spec type: " + string(parsed.Type))
			metaList = append(metaList, PluginMetadata{
				Spec:              spec,
				ResolutionFailure: "unrecognized plugin spec format",
			})
		}
	}

	return metaList, nil
}

// loadSettingsFromRepo reads a settings JSON blob from a single path in a repo.
// Returns empty settings if the path is not found or the blob is malformed.
// Used by all three loaders (repo, org, enterprise); callers are responsible
// for any source-specific post-processing such as stripping
// strictKnownMarketplaces or rejecting/converting local plugin specs.
func (s *Service) loadSettingsFromRepo(ctx context.Context, repoID uint64, settingsPath string) (*SettingsJSON, error) {
	blob, _, err := s.spokes.ReadBlob(ctx, repoID, settingsPath)
	if err != nil {
		if errors.Is(err, spokes.ErrNotFound) {
			return emptySettings(), nil
		}
		return nil, err
	}

	var settings SettingsJSON
	err = json.Unmarshal(blob, &settings)
	if err != nil {
		s.obsv.Logger.WithContext(ctx).WithError(err).Warn("ignoring malformed " + settingsPath)
		return emptySettings(), nil
	}

	if settings.EnabledPlugins == nil {
		settings.EnabledPlugins = make(map[string]bool)
	}
	if settings.ExtraKnownMarketplaces == nil {
		settings.ExtraKnownMarketplaces = make(map[string]ExtraMarketplace)
	}
	return &SettingsJSON{
		EnabledPlugins:          settings.EnabledPlugins,
		ExtraKnownMarketplaces:  settings.ExtraKnownMarketplaces,
		StrictKnownMarketplaces: settings.StrictKnownMarketplaces,
		RejectedPlugins:         make(map[string]string),
	}, nil
}

func emptySettings() *SettingsJSON {
	return &SettingsJSON{
		EnabledPlugins:         make(map[string]bool),
		ExtraKnownMarketplaces: make(map[string]ExtraMarketplace),
		RejectedPlugins:        make(map[string]string),
	}
}

// mergeSettings merges one SettingsJSON into another.
// Later calls overwrite earlier values (used for priority ordering).
func mergeSettings(dst, src *SettingsJSON) {
	maps.Copy(dst.EnabledPlugins, src.EnabledPlugins)
	maps.Copy(dst.ExtraKnownMarketplaces, src.ExtraKnownMarketplaces)
	maps.Copy(dst.RejectedPlugins, src.RejectedPlugins)
	if src.StrictKnownMarketplaces != nil {
		dst.StrictKnownMarketplaces = src.StrictKnownMarketplaces
	}
}

// rejectLocalPluginSpecs moves any enabled local plugin specs from settings.EnabledPlugins
// to settings.RejectedPlugins with the given reason. Used to block local plugins from
// sources the runtime cannot clone (org .github-private and enterprise repos).
func rejectLocalPluginSpecs(settings *SettingsJSON, reason string) {
	for spec, enabled := range settings.EnabledPlugins {
		if !enabled {
			continue
		}
		parsed := parsePluginSpec(spec)
		if parsed.Type != PluginSpecTypeLocal {
			continue
		}
		delete(settings.EnabledPlugins, spec)
		settings.RejectedPlugins[spec] = reason
	}
}

// convertLocalPluginSpecsToRemote rewrites enabled local plugin specs in settings.EnabledPlugins
// to GitHub specs (owner/repo or owner/repo:path) pointing to the given org repo. Used for
// local plugins defined in a public org .github repo, which the runtime can clone.
func convertLocalPluginSpecsToRemote(settings *SettingsJSON, orgOwner, repoName string) {
	for spec, enabled := range settings.EnabledPlugins {
		parsed := parsePluginSpec(spec)
		if parsed.Type != PluginSpecTypeLocal {
			continue
		}
		cleanedPath := path.Clean(parsed.RawSpec)
		var newSpec string
		if cleanedPath == "." {
			// Local spec referring to the repo root — bare owner/repo with no path suffix
			newSpec = orgOwner + "/" + repoName
		} else {
			newSpec = orgOwner + "/" + repoName + ":" + cleanedPath
		}
		delete(settings.EnabledPlugins, spec)
		settings.EnabledPlugins[newSpec] = enabled
	}
}

// isMarketplaceAllowed checks whether a marketplace plugin is permitted by the strictKnownMarketplaces policy.
// Returns true if:
//   - strictKnownMarketplaces is nil (no restrictions)
//   - the marketplace's source config matches at least one entry in the strict list
//
// Returns false if:
//   - strictKnownMarketplaces is set but empty (lockdown — no marketplaces allowed)
//   - the marketplace is not in the known marketplaces map (can't resolve its source)
//   - the marketplace's source doesn't match any entry in the strict list
//
// Default marketplaces (e.g. copilot-plugins) are always allowed, including under
// lockdown — the allowlist governs user-added marketplaces, not built-in ones.
func isMarketplaceAllowed(parsed ParsedPluginSpec, marketplaces map[string]MarketplaceSourceConfig, strict []MarketplaceSourceConfig) bool {
	if strict == nil {
		return true
	}

	marketplaceName := parsed.Marketplace
	// Default marketplaces (empty name or a known default) are always allowed
	if marketplaceName == "" {
		return true
	}
	if _, isDefault := defaultMarketplaces[marketplaceName]; isDefault {
		return true
	}

	source, ok := marketplaces[marketplaceName]
	if !ok {
		return false
	}

	for _, allowed := range strict {
		if sourceMatches(source, allowed) {
			return true
		}
	}

	return false
}

// sourceMatches reports whether the marketplace source matches the allowlist rule.
// The first argument is the marketplace's actual source (from extraKnownMarketplaces);
// the second is an entry from strictKnownMarketplaces.
//
// Supported rule types:
//   - "github": exact match on Repo (case-insensitive), Ref, and Path.
//   - "git":    exact match on URL, Ref, and Path.
func sourceMatches(source, rule MarketplaceSourceConfig) bool {
	if source.Source != rule.Source {
		return false
	}
	switch source.Source {
	case "github":
		return strings.EqualFold(source.Repo, rule.Repo) && source.Ref == rule.Ref && source.Path == rule.Path
	case "git":
		return source.URL == rule.URL && source.Ref == rule.Ref && source.Path == rule.Path
	default:
		return false
	}
}
