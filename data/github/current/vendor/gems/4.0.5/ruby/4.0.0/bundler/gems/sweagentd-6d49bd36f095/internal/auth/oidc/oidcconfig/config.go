// Package oidcconfig defines the OIDC configuration types used for 3rd party
// MCP server token exchange. It is a leaf package with no dependencies on the
// parent oidc package, making it safe to import without risk of circular
// dependencies.
package oidcconfig

import (
	"encoding/json"
	"net/url"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/goerrors"
	"gopkg.in/yaml.v3"
)

// ErrInvalidConfig indicates that the settings.json configuration is malformed or invalid.
var ErrInvalidConfig = goerrors.New("oidc: invalid configuration")

const (
	// secretNamePrefix is the prefix for secrets declared in settings.json.
	secretNamePrefix = "GITHUB_COPILOT_OIDC_" //nolint:gosec // This is not a secret token, just the name of a variable prefix.
	// appSecretNamePrefix is the prefix for secrets from Agentic apps.
	appSecretNamePrefix = "GITHUB_AGENTIC_APP_OIDC_" //nolint:gosec // This is not a secret token, just the name of a variable prefix.
)

const (
	// GrantTypeClientCredentials is the OAuth 2.0 client credentials grant type,
	// used by some providers (for example, Azure AD) as a provider-specific or
	// legacy fallback mechanism for workload identity federation.
	GrantTypeClientCredentials = "client_credentials" //nolint:gosec // Not a credential; OAuth 2.0 grant type identifier.

	// GrantTypeJWTBearer is the RFC 7523 JWT Bearer grant type for workload
	// identity federation, where a platform-issued JWT is presented directly
	// as an authorization grant.
	GrantTypeJWTBearer = "urn:ietf:params:oauth:grant-type:jwt-bearer" //nolint:gosec // Not a credential; RFC 7523 grant type URI.

	// GrantTypeTokenExchange is the RFC 8693 grant type for token exchange.
	GrantTypeTokenExchange = "urn:ietf:params:oauth:grant-type:token-exchange" //nolint:gosec // Not a credential; RFC 8693 grant type URI.
)

// supportedGrantTypes is used for validating that the grant type specified in a ConfigEntry is one of the supported OAuth 2.0 grant types.
var supportedGrantTypes = []string{
	GrantTypeClientCredentials,
	GrantTypeJWTBearer,
	GrantTypeTokenExchange,
}

// Config represents the top-level structure of a settings.json file.
type Config struct {
	OIDCConfig []ConfigEntry `json:"oidcConfig"`
}

// ConfigSource identifies where a ConfigEntry originated, which determines
// the secret name prefix used for the entry.
type ConfigSource int

// ConfigSource values identify the origin of a ConfigEntry.
const (
	ConfigSourceSettings   ConfigSource = iota // settings.json
	ConfigSourceAgenticApp                     // Agentic app
	ConfigSourceMCPInline                      // MCP server inline config
)

// EndpointsConfig holds the endpoint URLs for token exchange.
type EndpointsConfig struct {
	Exchange string `json:"exchange,omitempty" yaml:"exchange,omitempty"`
	Revoke   string `json:"revoke,omitempty"   yaml:"revoke,omitempty"`
	Failure  string `json:"failure,omitempty"  yaml:"failure,omitempty"`
	Base     string `json:"base,omitempty"     yaml:"base,omitempty"`
}

// ValidateURLs checks that Exchange, Revoke, and Configuration URLs, if set, are valid URIs.
// If isVariable is non-nil and returns true for a URL value, that URL is
// skipped (it likely contains an unresolved variable reference).
func (e EndpointsConfig) ValidateURLs(isVariable func(string) bool) error {
	skip := func(s string) bool {
		return isVariable != nil && isVariable(s)
	}
	if e.Exchange != "" && !skip(e.Exchange) {
		_, err := url.ParseRequestURI(e.Exchange)
		if err != nil {
			return goerrors.Errorf("endpoints.exchange is invalid: %w", err)
		}
	}
	if e.Revoke != "" && !skip(e.Revoke) {
		_, err := url.ParseRequestURI(e.Revoke)
		if err != nil {
			return goerrors.Errorf("endpoints.revoke is invalid: %w", err)
		}
	}
	if e.Failure != "" && !skip(e.Failure) {
		_, err := url.ParseRequestURI(e.Failure)
		if err != nil {
			return goerrors.Errorf("endpoints.failure is invalid: %w", err)
		}
	}
	if e.Base != "" && !skip(e.Base) {
		_, err := url.ParseRequestURI(e.Base)
		if err != nil {
			return goerrors.Errorf("endpoints.base is invalid: %w", err)
		}
	}
	return nil
}

// ConfigEntry represents a single OIDC token exchange configuration entry.
type ConfigEntry struct {
	// SecretSuffix is the suffix portion of the full secret name. For
	// settings.json and Agentic app entries this determines the environment
	// variable exposed to the agent (e.g. "GITHUB_COPILOT_OIDC_" + suffix).
	// For MCP inline entries, the serverName is used where possible instead.
	SecretSuffix     string          `json:"secretSuffix,omitempty"     yaml:"secret-suffix,omitempty"`
	Audience         string          `json:"audience"                   yaml:"audience"`
	Scope            string          `json:"scope,omitempty"            yaml:"scope,omitempty"`
	Resource         string          `json:"resource,omitempty"         yaml:"resource,omitempty"`
	ClientID         string          `json:"client,omitempty"           yaml:"client,omitempty"`
	GrantType        string          `json:"grantType,omitempty"        yaml:"grant-type,omitempty"` // Entra ID doesn't support RFC 8693 token exchange, so client_credentials is used as a fallback.
	Endpoints        EndpointsConfig `json:"endpoints,omitzero"         yaml:"endpoints,omitempty"`
	AgentOnlySubject bool            `json:"agentOnlySubject,omitempty" yaml:"agent-only-subject,omitempty"`
	RepoOnlySubject  bool            `json:"repoOnlySubject,omitempty"  yaml:"repo-only-subject,omitempty"`
	PublicClient     *bool           `json:"publicClient,omitempty"     yaml:"public-client,omitempty"`
	RedirectPort     int             `json:"redirectPort,omitempty"     yaml:"redirect-port,omitempty"`
	// Private fields below are not serialized; set by constructor functions based on config source
	source                ConfigSource
	serverName            string
	serverURL             string
	useAgenticAppIdentity bool // true when this entry should use the agentic app's identity in subject claims
}

// NewConfigEntryForAgenticApp creates a new config entry for an Agentic app, which uses a different secret name prefix.
// Entries from agentic apps always use the agent's identity in subject claims.
func NewConfigEntryForAgenticApp(entry ConfigEntry) ConfigEntry {
	entry.source = ConfigSourceAgenticApp
	entry.useAgenticAppIdentity = true
	return entry
}

// NewConfigEntry creates a new config entry for settings.json-declared OIDC entries.
func NewConfigEntry(entry ConfigEntry) ConfigEntry {
	entry.source = ConfigSourceSettings
	return entry
}

// NewConfigEntryForMCP creates a new config entry for OIDC entries derived from
// MCP server inline configuration. This config may be applied just to the
// authorization header or via GITHUB_COPILOT_OIDC_MCP_TOKEN (and suffixed variants
// like GITHUB_COPILOT_OIDC_MCP_TOKEN_MY_SVC) for local servers. However, this
// name is managed by the runtime MCP client rather than in sweagentd.
func NewConfigEntryForMCP(serverName, serverURL string, entry ConfigEntry) ConfigEntry {
	entry.source = ConfigSourceMCPInline
	entry.serverName = serverName
	entry.serverURL = serverURL
	entry.SecretSuffix = ""
	return entry
}

// UnmarshalJSON implements custom JSON unmarshalling to support "scopes" as an
// alias for "scope" given how easy it is to accidentally use one in place of the other.
func (e *ConfigEntry) UnmarshalJSON(data []byte) error {
	type configEntryAlias ConfigEntry
	var raw configEntryAlias
	err := json.Unmarshal(data, &raw)
	if err != nil {
		return err
	}
	*e = ConfigEntry(raw)

	if e.Scope == "" {
		var extra struct {
			Scope string `json:"scopes"`
		}
		err = json.Unmarshal(data, &extra)
		if err == nil && extra.Scope != "" {
			e.Scope = extra.Scope
		}
	}
	return nil
}

// UnmarshalYAML implements custom YAML unmarshalling to support "scopes" as an
// alias for "scope".
func (e *ConfigEntry) UnmarshalYAML(value *yaml.Node) error {
	type configEntryAlias ConfigEntry
	var raw configEntryAlias
	err := value.Decode(&raw)
	if err != nil {
		return err
	}
	*e = ConfigEntry(raw)

	if e.Scope == "" {
		var extra struct {
			Scope string `yaml:"scopes"`
		}
		err = value.Decode(&extra)
		if err == nil && extra.Scope != "" {
			e.Scope = extra.Scope
		}
	}
	return nil
}

// Validate checks that the ConfigEntry's core fields are well-formed:
// audience is required, endpoint URLs (if set) are valid.
func (e *ConfigEntry) Validate() error {
	return e.ValidateSkippingVariableEndpoints(nil)
}

// ValidateSkippingVariableEndpoints checks that the ConfigEntry's core fields
// are well-formed, optionally skipping URL validation for endpoint strings where
// isVariable returns true. This allows callers to defer URL validation for
// endpoint values that contain unresolved variable references.
func (e *ConfigEntry) ValidateSkippingVariableEndpoints(isVariable func(string) bool) error {
	if e.GrantType != "" && !slices.Contains(supportedGrantTypes, e.GrantType) {
		return goerrors.Errorf("unsupported grantType %q", e.GrantType)
	}
	if e.RedirectPort < 0 || e.RedirectPort > 65535 {
		return goerrors.Errorf("redirectPort must be between 0 and 65535")
	}
	err := e.Endpoints.ValidateURLs(isVariable)
	if err != nil {
		return err
	}
	return nil
}

// Source returns the origin of this config entry.
func (e *ConfigEntry) Source() ConfigSource {
	return e.source
}

// UseAgenticAppIdentity reports whether this entry should use the agentic app's
// identity (installation ID) when possible rather than the platform identity.
func (e *ConfigEntry) UseAgenticAppIdentity() bool {
	return e.useAgenticAppIdentity
}

// SetUseAgenticAppIdentity marks this entry as using the agentic app's identity in
// subject claims. This is set during config loading for entries that originate
// from the agentic app's own MCP config or plugin.
func (e *ConfigEntry) SetUseAgenticAppIdentity(v bool) {
	e.useAgenticAppIdentity = v
}

// ServerName returns the MCP server name for entries from MCP inline config.
// Returns empty for non-MCP entries.
func (e *ConfigEntry) ServerName() string {
	return e.serverName
}

// ServerURL returns the MCP server URL for entries from MCP inline config.
//
// Returns empty for non-MCP entries.
func (e *ConfigEntry) ServerURL() string {
	return e.serverURL
}

// SetServerURL sets MCP server URL for entries from MCP inline config.
func (e *ConfigEntry) SetServerURL(url string) {
	e.serverURL = url
}

// UseClientCredentials reports whether this entry should use the OAuth 2.0
// client credentials grant type (with client assertion) instead of the default
// RFC 8693 token exchange.
func (e *ConfigEntry) UseClientCredentials() bool {
	return e.GrantType == GrantTypeClientCredentials
}

// UseJWTBearer reports whether this entry should use the RFC 7523 JWT Bearer
// grant type, where a platform-issued JWT is presented directly as an
// authorization grant for workload identity federation.
func (e *ConfigEntry) UseJWTBearer() bool {
	return e.GrantType == GrantTypeJWTBearer
}

// UseIDTokenExchange reports whether this entry should use the RFC 8693 token
// exchange grant type, where the platform-issued ID token is exchanged for
// an access token at the integrator's token endpoint.
func (e *ConfigEntry) UseIDTokenExchange() bool {
	return e.GrantType == GrantTypeTokenExchange
}

// IsPublicClient reports whether this entry is a public client (no client
// secret). Defaults to true when not explicitly set.
func (e *ConfigEntry) IsPublicClient() bool {
	return e.PublicClient == nil || *e.PublicClient
}

// FullSecretName returns the complete secret name with prefix for this config entry.
func (e *ConfigEntry) FullSecretName() string {
	if e.SecretSuffix == "" || e.source == ConfigSourceMCPInline {
		return ""
	}
	if e.source == ConfigSourceAgenticApp {
		return appSecretNamePrefix + e.SecretSuffix
	}
	return secretNamePrefix + e.SecretSuffix
}

// ParseConfig parses and validates a settings.json configuration from raw JSON bytes.
func ParseConfig(data []byte, configSource ConfigSource) (*Config, error) {
	var cfg Config
	err := json.Unmarshal(data, &cfg)
	if err != nil {
		return nil, goerrors.Errorf("oidc: failed to parse config: %w", err)
	}
	err = cfg.Validate()
	if err != nil {
		return nil, err
	}
	// Set the config source for all entries
	for i := range cfg.OIDCConfig {
		cfg.OIDCConfig[i].source = configSource
	}
	return &cfg, nil
}

// Validate checks that the configuration is well-formed.
func (c *Config) Validate() error {
	if len(c.OIDCConfig) == 0 {
		return goerrors.Errorf("%w: no oidcConfig entries", ErrInvalidConfig)
	}

	seen := make(map[string]bool)
	for i, entry := range c.OIDCConfig {
		if entry.SecretSuffix == "" {
			return goerrors.Errorf("%w: entry %d missing secretSuffix", ErrInvalidConfig, i)
		}
		if seen[entry.SecretSuffix] {
			return goerrors.Errorf("%w: duplicate secretSuffix %q", ErrInvalidConfig, entry.SecretSuffix)
		}
		seen[entry.SecretSuffix] = true

		err := entry.Validate()
		if err != nil {
			return goerrors.Errorf("%w: entry %q %v", ErrInvalidConfig, entry.SecretSuffix, err)
		}
	}
	return nil
}

// ParseSecretNameSuffix extracts the suffix from a full secret name, if it has a known prefix.
func ParseSecretNameSuffix(secretName string) string {
	if suffix, ok := strings.CutPrefix(secretName, appSecretNamePrefix); ok {
		return suffix
	}
	if suffix, ok := strings.CutPrefix(secretName, secretNamePrefix); ok {
		return suffix
	}
	return secretName
}

// IsValidSecretName checks if the given secret name starts with a valid prefix
// for OIDC secrets sent via secret_names. Only settings.json and Agentic app
// prefixes are accepted; MCP inline entries must use mcp_server_names instead.
func IsValidSecretName(secretName string) bool {
	return strings.HasPrefix(secretName, secretNamePrefix) ||
		strings.HasPrefix(secretName, appSecretNamePrefix)
}
