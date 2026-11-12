// Package permissions provides types and functions for handling GitHub token permissions for MCP servers and bash
package permissions

import (
	"encoding/json"
	"errors"
	"maps"
	"slices"
	"strings"
	"unicode"

	"github.com/github/sweagentd/internal/goerrors"
)

var (
	// ErrInvalidPermissionValue is returned when an invalid permission value is specified.
	ErrInvalidPermissionValue = errors.New("invalid config: invalid permissions value")

	// ErrInvalidPermission is returned when an invalid / unsupported permission is specified.
	ErrInvalidPermission = errors.New("invalid config: invalid permission")

	// Default defines the default permissions for a custom agent if none are specified.
	// We are mirroring Action's permissions object, so we use a "-" in the names here, scopes use "_".
	Default = Permissions{
		permissions: map[string]string{
			"actions":       "read",
			"contents":      "read",
			"discussions":   "read",
			"issues":        "read",
			"metadata":      "read",
			"pull-requests": "read",
		},
	}

	// MCPWriteDefault is the read-write counterpart of [Default], used when
	// the `copilot_swe_agent_mcp_permission_gate` feature flag is enabled.
	// The runtime's PermissionGate prompts the user before each non-readOnly
	// MCP tool call, so it is safe to broaden the underlying token to
	// read-write while the flag is enabled. Mirrors the dotcom-side
	// `MCP_WRITE_GITHUB_TOKEN_PERMISSIONS` constant in
	// `app/api/internal/twirp/actions/core/v1/job_secrets_provider/copilot_swe_agent_job_secrets_provider.rb`.
	MCPWriteDefault = Permissions{
		permissions: map[string]string{
			"actions":       "write",
			"contents":      "write",
			"discussions":   "write",
			"issues":        "write",
			"metadata":      "read",
			"pull-requests": "write",
		},
	}

	// Unset defines a Permissions object with no permissions set.
	Unset = Permissions{
		permissions: map[string]string{},
	}

	// Allowed defines the acceptable permission levels for the permissions field in the custom agent configuration.
	// Subset of: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#defining-access-for-the-github_token-scopes
	Allowed = []string{"actions", "checks", "contents", "discussions", "issues", "metadata", "pull-requests", "security-events", "workflows"}
	// AllowedValues defines the acceptable values for each permission scope.
	// Based on GitHub documentation: https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions
	// and what the current copilot-swe-agent global app has access to.
	AllowedValues = map[string][]string{
		"actions":         {"read", "write", "none"},
		"checks":          {"read", "none"},
		"contents":        {"read", "write", "none"},
		"discussions":     {"read", "write", "none"},
		"issues":          {"read", "write", "none"},
		"metadata":        {"read"}, // metadata only supports read access
		"pull-requests":   {"read", "write", "none"},
		"security-events": {"read", "none"},
		"workflows":       {"write", "none"},
	}

	// None defines a Permissions object with only metadata read permission.
	// Unlike Unset, this indicates that the user explicitly set no other permissions.
	None = Permissions{
		permissions: map[string]string{
			"metadata": "read",
		},
	}
)

// Provider is satisfied by any type that can provide a Permissions object, such as CustomAgent or repo-level config structs.
type Provider interface {
	Permissions() Permissions
}

// Permissions represents the GitHub token permissions for MCP and bash configuration.
type Permissions struct {
	permissions map[string]string
}

// New creates a Permissions from a generic map or string. If nil is passed in, an
// empty permissions map is returned so that the caller can determine the correct behavior w/o pointers.
func New(mapOrString any) Permissions {
	switch v := mapOrString.(type) {
	case string:
		switch v {
		case "read-all":
			perms := make(map[string]string, len(Allowed))
			for _, perm := range Allowed {
				if slices.Contains(AllowedValues[perm], "read") {
					perms[perm] = "read"
				}
			}
			return Permissions{permissions: perms}
		case "write-all":
			perms := make(map[string]string, len(Allowed))
			for _, perm := range Allowed {
				if slices.Contains(AllowedValues[perm], "write") {
					perms[perm] = "write"
				} else {
					perms[perm] = "read"
				}
			}
			return Permissions{permissions: perms}
		default:
			return Unset
		}
	case map[string]string:
		// If we were sent an empty map, return empty permissions
		if len(v) == 0 {
			return Unset
		}
		// Normalize camelCase keys to dash-separated format
		normalized := normalizePermissionKeys(v)
		// Metadata must always be read
		normalized["metadata"] = "read"
		return Permissions{permissions: normalized}
	case map[string]any:
		// If we were sent an empty map, return empty permissions
		if len(v) == 0 {
			return Unset
		}
		// Convert map[string]any to map[string]string
		perms := map[string]string{}
		for key, val := range v {
			if str, ok := val.(string); ok {
				perms[key] = str
			}
		}
		// Normalize camelCase keys to dash-separated format
		normalized := normalizePermissionKeys(perms)
		// Metadata must always be read
		normalized["metadata"] = "read"
		return Permissions{permissions: normalized}
	case Permissions:
		return v
	default:
		// If nil or other value, return an object with no permissions set so caller can determine correct behavior
		return Unset
	}
}

// Validate checks that all permissions and their values are valid according to GitHub documentation.
func (p Permissions) Validate() error {
	for key, value := range p.permissions {
		allowedValues, ok := AllowedValues[key]
		if !ok {
			return goerrors.Errorf("%w %q", ErrInvalidPermission, key)
		}
		if !slices.Contains(allowedValues, value) {
			return goerrors.Errorf("%w %q for %q", ErrInvalidPermissionValue, value, key)
		}
	}
	return nil
}

// IsUnset checks if no permissions have been set
func (p Permissions) IsUnset() bool {
	// Since metadata is always set to read, an empty permissions object is equal to unset
	return len(p.permissions) == 0
}

// ToDotCom converts a permissions map to GitHub.com permissions format (replacing "-" with "_").
// Used here, in launcher, and in tests for validation. It validates that both permission keys and values are allowed based on GitHub documentation.
func (p Permissions) ToDotCom() (map[string]string, error) {
	err := p.Validate()
	if err != nil {
		return map[string]string{}, err
	}

	// Convert actions style "permissions" with a "-" to ghPerms with "_"
	ghPerms := make(map[string]string, len(p.permissions))
	for key, value := range p.permissions {
		// Skip "none" values as they don't need to be included in scopes
		if value == "none" {
			continue
		}
		ghPerms[strings.ReplaceAll(key, "-", "_")] = value
	}
	// Always set metadata read even if not specified
	ghPerms["metadata"] = "read"
	return ghPerms, nil
}

// ToMap returns the permissions as a map[string]string
func (p Permissions) ToMap() map[string]string {
	return maps.Clone(p.permissions)
}

// MarshalJSON custom marshals the underlying permissions map to JSON.
func (p Permissions) MarshalJSON() ([]byte, error) {
	return json.Marshal(p.permissions)
}

// UnmarshalJSON unmarshals the underlying permissions map from JSON.
func (p *Permissions) UnmarshalJSON(data []byte) error {
	var perms map[string]string
	err := json.Unmarshal(data, &perms)
	if err != nil {
		return err
	}
	// Normalize camelCase keys to dash-separated format
	p.permissions = normalizePermissionKeys(perms)
	return nil
}

// ResolvePermissions determines the effective permissions to use based on any provided and repo-level permissions.
func ResolvePermissions(agentProvided, repoLevel Permissions) Permissions {
	// If no permissions were provided, fall back to repo-level permissions or default if even those are not set
	if agentProvided.IsUnset() {
		if repoLevel.IsUnset() {
			return Default
		}
		return repoLevel
	}
	return agentProvided
}

// RestrictTriggeredMCPPermissions applies additional guardrails for triggered jobs.
// It is defense-in-depth against automation use cases that should not receive
// write access to actions/deployments on MCP-minted tokens.
func RestrictTriggeredMCPPermissions(perms Permissions) Permissions {
	restricted := perms.ToMap()
	if restricted["actions"] == "write" {
		restricted["actions"] = "read"
	}
	delete(restricted, "deployments")
	return Permissions{permissions: restricted}
}

// camelCaseToDash converts a camelCase string to dash-separated (kebab-case).
// For example: "pullRequests" -> "pull-requests"
func camelCaseToDash(s string) string {
	if s == "" {
		return s
	}

	var result strings.Builder
	result.Grow(len(s) + 2) // Allocate enough space for potential dashes

	for i, r := range s {
		if unicode.IsUpper(r) && i > 0 {
			_ = result.WriteByte('-')
			_, _ = result.WriteRune(unicode.ToLower(r))
		} else {
			_, _ = result.WriteRune(unicode.ToLower(r))
		}
	}

	return result.String()
}

// normalizePermissionKeys converts any camelCase permission keys to dash-separated format.
// Returns a new map with translated keys.
func normalizePermissionKeys(perms map[string]string) map[string]string {
	normalized := make(map[string]string, len(perms))
	for key, value := range perms {
		normalized[camelCaseToDash(key)] = value
	}
	return normalized
}
