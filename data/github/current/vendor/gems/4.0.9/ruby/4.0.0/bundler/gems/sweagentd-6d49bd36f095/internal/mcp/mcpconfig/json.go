// Package mcpconfig provides structures and functions to handle a well-defined schema for MCP JSON configuration.
package mcpconfig

import (
	"encoding/json"
	"regexp"
	"strings"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/goerrors"
)

// ErrToolsFieldIsRequired is returned when the tools field is missing from a server under mcp-servers.
var ErrToolsFieldIsRequired = goerrors.New("tools field is required")

// JSON represents the MCP configuration schema. The string keys are server names, and the values are their configurations.
type JSON struct {
	Servers map[string]Server `json:"mcpServers"`
	GitHub  *GitHub           `json:"github,omitempty"`
}

// UnmarshalJSON custom unmarshals the JSON config to set the server name on
// each OIDC config entry. Server.UnmarshalJSON cannot do this because it does
// not have access to the map key (server name).
func (j *JSON) UnmarshalJSON(data []byte) error {
	type jsonAlias JSON
	var raw jsonAlias
	err := json.Unmarshal(data, &raw)
	if err != nil {
		return err
	}

	for name, srv := range raw.Servers {
		if srv.Auth == nil {
			continue
		}
		var serverURL string
		if srv.Remote != nil {
			serverURL = srv.URL
		}
		entry := oidcconfig.NewConfigEntryForMCP(name, serverURL, *srv.Auth)
		srv.Auth = &entry
		raw.Servers[name] = srv
	}

	*j = JSON(raw)
	return nil
}

// GitHub represents the GitHub-specific configuration like GitHub token permissions.
type GitHub struct {
	// Can be a string or map[string]string
	Permissions any `json:"permissions,omitempty"`
}

// Server represents the configuration for an individual MCP server.
type Server struct {
	*Local  `json:",omitempty"`
	*Remote `json:",omitempty"`

	Tools []string                `json:"tools"`
	Type  string                  `json:"type,omitempty"`
	Auth  *oidcconfig.ConfigEntry `json:"auth,omitempty"`
	// OIDCEnabled is true when the auth field was specified as boolean `true`
	// (shorthand for remote servers). Not serialized directly; custom
	// marshal/unmarshal handles it.
	OIDCEnabled bool `json:"-"`
}

// validateOIDC checks that the OIDC config is well-formed for the given server type.
// Endpoint URLs that contain variable references (e.g. $COPILOT_MCP_EXCHANGE_URL)
// are skipped during URL validation because variables are resolved after unmarshalling.
// Post-resolution validation must happen separately (see ConfigEntry.Validate).
func validateOIDC(entry *oidcconfig.ConfigEntry, serverType string) error {
	if entry == nil {
		return nil
	}
	if IsLocal(serverType) {
		if entry.Endpoints.Exchange == "" && entry.Endpoints.Base == "" {
			return goerrors.New("auth.endpoints.base or auth.endpoints.exchange is required for local servers")
		}
	}
	err := entry.ValidateSkippingVariableEndpoints(containsVariableReference)
	if err != nil {
		return goerrors.Errorf("auth.%w", err)
	}
	return nil
}

// Local represents the fields for a local server config
type Local struct {
	Command string            `json:"command"`
	Args    []string          `json:"args"`
	Env     map[string]string `json:"env,omitempty"`
}

// Remote represents the fields for a remote server config
type Remote struct {
	Type    string            `json:"type"`
	URL     string            `json:"url"`
	Headers map[string]string `json:"headers,omitempty"`
}

var (
	githubActionsSecretsRegex = regexp.MustCompile(`\$\{\{\s*secrets\.([A-Z0-9_]+)\s*\}\}`)
	githubActionsVarsRegex    = regexp.MustCompile(`\$\{\{\s*vars?\.([A-Z0-9_]+)\s*\}\}`)
)

// normalizeGitHubActionsSyntax converts GitHub Actions variable syntax to standard environment variable syntax
func normalizeGitHubActionsSyntax(input string) string {
	// Replace ${{ secrets.VAR_NAME }} with $VAR_NAME
	result := githubActionsSecretsRegex.ReplaceAllString(input, `$$$1`)
	// Replace ${{ vars.VAR_NAME }} with $VAR_NAME
	result = githubActionsVarsRegex.ReplaceAllString(result, `$$$1`)
	return result
}

// normalizeStringSlice applies GitHub Actions syntax normalization to a slice of strings
func normalizeStringSlice(slice []string) []string {
	if slice == nil {
		return nil
	}
	normalized := make([]string, len(slice))
	for i, str := range slice {
		normalized[i] = normalizeGitHubActionsSyntax(str)
	}
	return normalized
}

// normalizeStringMap applies GitHub Actions syntax normalization to a map of strings
func normalizeStringMap(m map[string]string) map[string]string {
	if m == nil {
		return nil
	}
	normalized := make(map[string]string, len(m))
	for key, value := range m {
		// Normalize values, not keys
		normalizedValue := normalizeGitHubActionsSyntax(value)
		normalized[key] = normalizedValue
	}
	return normalized
}

// UnmarshalJSON custom unmarshals the McpServerConfig to handle different server types.
func (s *Server) UnmarshalJSON(data []byte) error {
	var temp struct {
		Tools *[]string       `json:"tools"`
		Type  string          `json:"type"`
		Auth  json.RawMessage `json:"auth"`
		OIDC  json.RawMessage `json:"oidc"`
	}
	err := json.Unmarshal(data, &temp)
	if err != nil {
		return err
	}

	// "auth" is the primary key; "oidc" is a compatibility alias.
	authRaw := temp.Auth
	if len(authRaw) == 0 || string(authRaw) == "null" {
		authRaw = temp.OIDC
	}

	if temp.Tools != nil {
		s.Tools = *temp.Tools
	}

	s.Type = temp.Type

	// Handle auth field: can be boolean `true` (shorthand) or a full config object.
	if len(authRaw) > 0 && string(authRaw) != "null" {
		var oidcBool bool
		if json.Unmarshal(authRaw, &oidcBool) == nil {
			if oidcBool {
				s.OIDCEnabled = true
				s.Auth = &oidcconfig.ConfigEntry{}
			}
			// auth: false is treated the same as absent
		} else {
			var entry oidcconfig.ConfigEntry
			err := json.Unmarshal(authRaw, &entry)
			if err != nil {
				return err
			}
			s.Auth = &entry
		}
	}

	if IsLocal(s.Type) {
		if s.OIDCEnabled {
			return goerrors.New("auth: true is only supported for remote server types")
		}

		var local Local
		err := json.Unmarshal(data, &local)
		if err != nil {
			return err
		}
		// We can't validate beyond this since args could be empty and env is optional
		if local.Command == "" {
			return goerrors.New("command is required for local server types")
		}
		local.Command = normalizeGitHubActionsSyntax(local.Command)
		local.Args = normalizeStringSlice(local.Args)
		local.Env = normalizeStringMap(local.Env)
		s.Local = &local

		err = validateOIDC(s.Auth, s.Type)
		if err != nil {
			return goerrors.Errorf("local server: %w", err)
		}
		return nil
	}

	if IsRemote(s.Type) {
		var remote Remote
		err := json.Unmarshal(data, &remote)
		if err != nil {
			return err
		}
		// We can't validate beyond this since headers is optional
		if remote.URL == "" {
			return goerrors.New("url is required for remote server types")
		}
		remote.URL = normalizeGitHubActionsSyntax(remote.URL)
		remote.Headers = normalizeStringMap(remote.Headers)
		s.Remote = &remote

		// Skip detailed OIDC validation for oidc: true; endpoints and
		// audience will be resolved via discovery at runtime.
		if !s.OIDCEnabled {
			err = validateOIDC(s.Auth, s.Type)
			if err != nil {
				return goerrors.Errorf("remote server: %w", err)
			}
		}
		return nil
	}

	return goerrors.Errorf("invalid server type: %v", s.Type)
}

// MarshalJSON custom marshals the McpServerConfig based on which configuration is set.
// It emits auth config under both "auth" and "oidc" keys for backward compatibility
// with older runtimes that still read "oidc".
// TODO: Remove the "oidc" alias once the runtime has fully migrated to "auth".
func (s Server) MarshalJSON() ([]byte, error) {
	var data []byte
	var err error

	switch {
	case s.Local != nil:
		temp := struct {
			Tools   []string                `json:"tools"`
			Type    string                  `json:"type,omitempty"`
			Command string                  `json:"command"`
			Args    []string                `json:"args"`
			Env     map[string]string       `json:"env,omitempty"`
			Auth    *oidcconfig.ConfigEntry `json:"auth,omitempty"`
		}{
			Tools:   s.Tools,
			Type:    s.Type,
			Command: s.Command,
			Args:    s.Args,
			Env:     s.Env,
			Auth:    s.Auth,
		}
		data, err = json.Marshal(temp)
	case s.Remote != nil:
		if s.OIDCEnabled {
			temp := struct {
				Tools   []string          `json:"tools"`
				Type    string            `json:"type"`
				URL     string            `json:"url"`
				Headers map[string]string `json:"headers,omitempty"`
				Auth    bool              `json:"auth"`
			}{
				Tools:   s.Tools,
				Type:    s.Type,
				URL:     s.URL,
				Headers: s.Headers,
				Auth:    true,
			}
			data, err = json.Marshal(temp)
		} else {
			temp := struct {
				Tools   []string                `json:"tools"`
				Type    string                  `json:"type"`
				URL     string                  `json:"url"`
				Headers map[string]string       `json:"headers,omitempty"`
				Auth    *oidcconfig.ConfigEntry `json:"auth,omitempty"`
			}{
				Tools:   s.Tools,
				Type:    s.Type,
				URL:     s.URL,
				Headers: s.Headers,
				Auth:    s.Auth,
			}
			data, err = json.Marshal(temp)
		}
	default:
		return nil, goerrors.New("must have either local or remote MCP config")
	}

	if err != nil {
		return nil, err
	}

	// If there's no auth config, nothing to duplicate.
	if s.Auth == nil && !s.OIDCEnabled {
		return data, nil
	}

	// Copy "auth" value to "oidc" for backward compatibility.
	var m map[string]json.RawMessage
	err = json.Unmarshal(data, &m)
	if err != nil {
		return nil, err
	}
	if authVal, ok := m["auth"]; ok {
		m["oidc"] = authVal
	}
	return json.Marshal(m)
}

// IsLocal checks if the server type is local or default (empty).
func IsLocal(typeString string) bool {
	return typeString == "local" || typeString == "stdio" || typeString == ""
}

// IsRemote checks if the server type is remote (http or sse).
func IsRemote(typeString string) bool {
	return typeString == "http" || typeString == "sse"
}

// ExtractServiceProcessedVariableReferences scans selected fields in MCP server
// configuration and returns a slice of variable names that start with COPILOT_MCP_ and are
// referenced via one of:
//   - ${{ vars.VAR_NAME }}
//   - ${VAR_NAME}
//   - ${VAR_NAME:-default}
//   - $VAR_NAME
//
// The extraction is intentionally limited to fields used for processing within
// sweagentd like OIDC token exchange processing. These are variables only (no secrets).
func ExtractServiceProcessedVariableReferences(cfg JSON) []string {
	refs := make(map[string]bool)
	for _, server := range cfg.Servers {
		if server.Remote != nil {
			extractVarRefsFromString(server.URL, refs)
		}
		if server.Auth == nil {
			continue
		}
		extractVarRefsFromString(server.Auth.Audience, refs)
		extractVarRefsFromString(server.Auth.Scope, refs)
		extractVarRefsFromString(server.Auth.Resource, refs)
		extractVarRefsFromString(server.Auth.ClientID, refs)
		extractVarRefsFromString(server.Auth.Endpoints.Exchange, refs)
		extractVarRefsFromString(server.Auth.Endpoints.Revoke, refs)
		extractVarRefsFromString(server.Auth.Endpoints.Failure, refs)
		extractVarRefsFromString(server.Auth.Endpoints.Base, refs)
	}
	var result []string
	for ref := range refs {
		if strings.HasPrefix(ref, "COPILOT_MCP_") {
			result = append(result, ref)
		}
	}
	return result
}

// serviceProcessedVarRefRegex combines patterns for GitHub Actions vars syntax,
// brace-delimited shell syntax, and bare shell syntax to extract variable
// references in three forms:
//  1. ${{ vars.VAR_NAME }} — GitHub Actions variable syntax (group 1)
//
// 2. ${VAR_NAME}          — brace-delimited shell syntax (group 2)
// 3. ${VAR_NAME:-default} — brace-delimited shell syntax with default (groups 2,3)
// 4. $VAR_NAME            — bare shell syntax (group 4)
var serviceProcessedVarRefRegex = regexp.MustCompile(
	`\$\{\{\s*vars?\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}` + // group 1: ${{ vars.X }}
		`|\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}` + // groups 2,3: ${X} / ${X:-default}
		`|\$([A-Za-z_][A-Za-z0-9_]*)`) // group 4: $X

func extractVarRefsFromString(s string, refs map[string]bool) {
	for _, groups := range serviceProcessedVarRefRegex.FindAllStringSubmatch(s, -1) {
		name, _ := parseServiceProcessedVariableReference(groups, nil)
		if name != "" {
			refs[name] = true
		}
	}
}

// ResolveServiceProcessedVariables returns a copy of cfg with variable references replaced
// in select fields (like OIDC fields) by the corresponding values from vars. It handles four reference forms:
//   - ${{ vars.VAR_NAME }} (GitHub Actions syntax)
//   - ${VAR_NAME}          (brace-delimited)
//   - ${VAR_NAME:-default} (brace-delimited with default)
//   - $VAR_NAME            (bare)
//
// Only variables starting with COPILOT_MCP_ are processed.
func ResolveServiceProcessedVariables(cfg JSON, vars map[string]string) JSON {
	// Filter to only include variables starting with COPILOT_MCP_
	filteredVars := make(map[string]string)
	for k, v := range vars {
		if strings.HasPrefix(k, "COPILOT_MCP_") {
			filteredVars[k] = v
		}
	}
	if len(filteredVars) == 0 && len(ExtractServiceProcessedVariableReferences(cfg)) == 0 {
		return cfg
	}
	resolved := JSON{
		GitHub: cfg.GitHub,
	}
	if cfg.Servers != nil {
		resolved.Servers = make(map[string]Server, len(cfg.Servers))
		for name, server := range cfg.Servers {
			resolved.Servers[name] = resolveServiceProcessedVarsForServer(server, filteredVars)
		}
	}
	return resolved
}

func resolveServiceProcessedVarsForServer(s Server, vars map[string]string) Server {
	out := s
	if out.Remote != nil {
		remote := *out.Remote
		remote.URL = resolveVarString(remote.URL, vars)
		out.Remote = &remote
	}
	if out.Auth == nil {
		return out
	}
	entry := *out.Auth
	if out.Remote != nil {
		entry.SetServerURL(out.URL)
	}
	entry.Audience = resolveVarString(entry.Audience, vars)
	entry.Scope = resolveVarString(entry.Scope, vars)
	entry.Resource = resolveVarString(entry.Resource, vars)
	entry.ClientID = resolveVarString(entry.ClientID, vars)
	entry.Endpoints.Exchange = resolveVarString(entry.Endpoints.Exchange, vars)
	entry.Endpoints.Revoke = resolveVarString(entry.Endpoints.Revoke, vars)
	entry.Endpoints.Failure = resolveVarString(entry.Endpoints.Failure, vars)
	entry.Endpoints.Base = resolveVarString(entry.Endpoints.Base, vars)
	out.Auth = &entry
	return out
}

// resolveVarString replaces variable references in s with values from vars.
func resolveVarString(s string, vars map[string]string) string {
	return serviceProcessedVarRefRegex.ReplaceAllStringFunc(s, func(match string) string {
		groups := serviceProcessedVarRefRegex.FindStringSubmatch(match)
		indices := serviceProcessedVarRefRegex.FindStringSubmatchIndex(match)
		name, defaultValue := parseServiceProcessedVariableReference(groups, indices)
		if val, ok := vars[name]; ok {
			return val
		}
		if defaultValue != nil {
			return *defaultValue
		}
		return match
	})
}

// containsVariableReference reports whether s contains a variable reference
// matching one of the supported syntaxes (${{ vars.X }}, ${X}, ${X:-default}, $X).
func containsVariableReference(s string) bool {
	return serviceProcessedVarRefRegex.MatchString(s)
}

func parseServiceProcessedVariableReference(groups []string, indices []int) (string, *string) {
	switch {
	case len(groups) > 1 && groups[1] != "":
		return groups[1], nil // ${{ vars.X }}
	case len(groups) > 2 && groups[2] != "":
		if len(groups) > 3 && len(indices) > 6 && indices[6] != -1 {
			return groups[2], &groups[3] // ${X:-default}
		}
		return groups[2], nil // ${X}
	case len(groups) > 4 && groups[4] != "":
		return groups[4], nil // $X
	default:
		return "", nil
	}
}
