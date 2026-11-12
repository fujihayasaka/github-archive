package plugins

import (
	"net/url"
	"strings"
)

// parsePluginSpec classifies a plugin specification string and extracts marketplace fields if needed.
// Supported formats:
//   - "owner/repo" or "owner/repo:path" - GitHub repository
//   - "https://...", "http://...", "ssh://...", "git@..." - Direct URL
//   - "plugin@marketplace" - Marketplace plugin
//   - ".", "./path", "/path" - Local path (relative to repo root)
//
// Note: "../path" inputs are recognized as local-path-shaped and classified as
// PluginSpecTypeLocal, but are rejected as unsafe by ResolvePluginRepos.
func parsePluginSpec(spec string) ParsedPluginSpec {
	spec = strings.TrimSpace(spec)

	// Check for local path — normalize leading "/" to "./" so downstream
	// code only deals with relative paths.
	if isLocalPathSpec(spec) {
		normalized := spec
		if strings.HasPrefix(normalized, "/") && !strings.HasPrefix(normalized, "//") {
			normalized = "." + normalized
		}
		return ParsedPluginSpec{
			Type:    PluginSpecTypeLocal,
			RawSpec: normalized,
		}
	}

	if strings.HasPrefix(spec, "https://") ||
		strings.HasPrefix(spec, "http://") ||
		strings.HasPrefix(spec, "ssh://") ||
		strings.HasPrefix(spec, "git@") {
		return ParsedPluginSpec{
			Type:    PluginSpecTypeURL,
			RawSpec: spec,
		}
	}

	// Check for the `owner/repo@<sha>` (or `owner/repo:path@<sha>`) SHA-pinned
	// GitHub form. Disambiguated from the marketplace form by requiring the
	// left side of the last `@` to look like a GitHub spec (contains `/`):
	// marketplace plugin names never contain `/`.
	if atIdx := strings.LastIndex(spec, "@"); atIdx > 0 {
		lhs := spec[:atIdx]
		rhs := spec[atIdx+1:]
		if rhs != "" && isGitHubSpec(lhs) {
			return ParsedPluginSpec{
				Type:    PluginSpecTypeGitHub,
				RawSpec: lhs,
				SHA:     rhs,
			}
		}
	}

	// Check for marketplace format (plugin@marketplace)
	// Format: plugin@marketplace where @ is not at the start
	if atIdx := strings.LastIndex(spec, "@"); atIdx > 0 {
		pluginName := spec[:atIdx]
		marketplace := spec[atIdx+1:]
		if marketplace != "" {
			return ParsedPluginSpec{
				Type:        PluginSpecTypeMarketplace,
				RawSpec:     spec,
				PluginName:  pluginName,
				Marketplace: marketplace,
			}
		}
	}

	if isGitHubSpec(spec) {
		return ParsedPluginSpec{
			Type:    PluginSpecTypeGitHub,
			RawSpec: spec,
		}
	}

	// Unknown format - treat as marketplace plugin with empty marketplace (default)
	// This matches CLI behavior where bare names like "my-plugin" resolve via default marketplace
	return ParsedPluginSpec{
		Type:        PluginSpecTypeMarketplace,
		RawSpec:     spec,
		PluginName:  spec,
		Marketplace: "", // Empty = use default marketplace
	}
}

// isGitHubSpec checks if spec matches "owner/repo" or "owner/repo:path" format.
func isGitHubSpec(spec string) bool {
	// Remove :path suffix if present
	if colonIdx := strings.LastIndex(spec, ":"); colonIdx > 0 {
		spec = spec[:colonIdx]
	}
	// Must be owner/repo format (exactly one slash)
	parts := strings.SplitN(spec, "/", 3)
	if len(parts) != 2 {
		return false
	}
	owner := strings.TrimSpace(parts[0])
	repo := strings.TrimSpace(strings.TrimSuffix(parts[1], ".git"))
	return owner != "" && repo != ""
}

// extractNWO extracts the owner, repository name, and optional subpath from a GitHub reference.
// Accepts bare "owner/repo", "owner/repo:path" format, and full URLs (https, http, ssh, git@).
// Strips .git suffix. Returns ("", "", "") if the input is malformed or the URL host does not match githubServerURL.
// The subpath component is only extracted from bare "owner/repo:path" format, not from URLs.
func extractNWO(input, githubServerURL string) (owner, repo, subpath string) {
	input = strings.TrimSpace(input)
	if input == "" {
		return "", "", ""
	}

	if strings.HasPrefix(input, "git@") {
		return extractNWOFromGitAt(input, githubServerURL)
	}
	if strings.Contains(input, "://") {
		return extractNWOFromSchemeURL(input, githubServerURL)
	}
	return extractNWOFromBareSpec(input)
}

// extractNWOFromGitAt handles git@host:owner/repo.git format.
func extractNWOFromGitAt(input, githubServerURL string) (owner, repo, subpath string) {
	serverHost := parseHostname(githubServerURL)
	if serverHost == "" {
		return "", "", ""
	}
	rawURL := strings.TrimSuffix(strings.TrimPrefix(input, "git@"), ".git")
	colonIdx := strings.Index(rawURL, ":")
	if colonIdx <= 0 {
		return "", "", ""
	}
	if strings.ToLower(rawURL[:colonIdx]) != serverHost {
		return "", "", ""
	}
	owner, repo = splitOwnerRepo(rawURL[colonIdx+1:])
	return owner, repo, ""
}

// extractNWOFromSchemeURL handles https://, http://, ssh:// URLs.
func extractNWOFromSchemeURL(input, githubServerURL string) (owner, repo, subpath string) {
	serverHost := parseHostname(githubServerURL)
	if serverHost == "" {
		return "", "", ""
	}
	rawURL := strings.TrimSuffix(input, ".git")
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return "", "", ""
	}
	if strings.ToLower(parsed.Hostname()) != serverHost {
		return "", "", ""
	}
	// Reject URLs with query parameters or fragments
	if parsed.RawQuery != "" || parsed.Fragment != "" {
		return "", "", ""
	}
	owner, repo = splitOwnerRepo(strings.TrimPrefix(parsed.Path, "/"))
	return owner, repo, ""
}

// extractNWOFromBareSpec handles "owner/repo" and "owner/repo:path" format.
func extractNWOFromBareSpec(input string) (owner, repo, subpath string) {
	if colonIdx := strings.LastIndex(input, ":"); colonIdx > 0 {
		subpath = input[colonIdx+1:]
		input = input[:colonIdx]
	}
	input = strings.TrimSuffix(input, ".git")
	owner, repo = splitOwnerRepo(input)
	if owner == "" || repo == "" {
		return "", "", ""
	}
	return owner, repo, subpath
}

// parseHostname extracts the lowercased hostname from a URL string.
func parseHostname(rawURL string) string {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	return strings.ToLower(parsed.Hostname())
}

// splitOwnerRepo splits "owner/repo" into its components. Returns ("", "") if invalid.
// Requires exactly two non-empty segments (no extra path segments, trailing slashes, or dot-segments).
func splitOwnerRepo(pathStr string) (owner, repo string) {
	// Strip trailing slash
	pathStr = strings.TrimRight(pathStr, "/")
	parts := strings.Split(pathStr, "/")
	if len(parts) != 2 {
		return "", ""
	}
	owner, repo = parts[0], parts[1]
	if owner == "" || repo == "" {
		return "", ""
	}
	// Reject dot-segments
	if owner == "." || owner == ".." || repo == "." || repo == ".." {
		return "", ""
	}
	return owner, repo
}

// isLocalPathSpec returns true if spec looks like a local path reference
// (current dir, parent dir, or absolute path).
func isLocalPathSpec(spec string) bool {
	return spec == "." || spec == ".." ||
		strings.HasPrefix(spec, "./") ||
		strings.HasPrefix(spec, "../") ||
		strings.HasPrefix(spec, "/")
}

// isUnsafePath returns true if a path.Clean'd path escapes via traversal ("..") or is absolute ("/").
func isUnsafePath(cleaned string) bool {
	return strings.HasPrefix(cleaned, "..") || strings.HasPrefix(cleaned, "/")
}
