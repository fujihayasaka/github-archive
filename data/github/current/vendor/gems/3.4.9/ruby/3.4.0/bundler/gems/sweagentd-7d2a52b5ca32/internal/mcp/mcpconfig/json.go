// Package mcpconfig provides structures and functions to handle a well-defined schema for MCP JSON configuration.
package mcpconfig

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
)

// ErrToolsFieldIsRequired is returned when the tools field is missing from a server under mcp-servers.
var ErrToolsFieldIsRequired = errors.New("tools field is required")

// JSON represents the MCP configuration schema. The string keys are server names, and the values are their configurations.
type JSON struct {
	Servers map[string]Server `json:"mcpServers"`
}

// Server represents the configuration for an individual MCP server.
type Server struct {
	*Local  `json:",omitempty"`
	*Remote `json:",omitempty"`

	Tools []string `json:"tools"`
	Type  string   `json:"type,omitempty"`
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
		Tools *[]string `json:"tools"`
		Type  string    `json:"type"`
	}
	err := json.Unmarshal(data, &temp)
	if err != nil {
		return err
	}

	if temp.Tools == nil {
		return ErrToolsFieldIsRequired
	}

	s.Tools = *temp.Tools
	s.Type = temp.Type

	if IsLocal(s.Type) {
		var local Local
		err := json.Unmarshal(data, &local)
		if err != nil {
			return err
		}
		// We can't validate beyond this since args could be empty and env is optional
		if local.Command == "" {
			return errors.New("command is required for local server types")
		}
		local.Command = normalizeGitHubActionsSyntax(local.Command)
		local.Args = normalizeStringSlice(local.Args)
		local.Env = normalizeStringMap(local.Env)
		s.Local = &local
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
			return errors.New("url is required for remote server types")
		}
		remote.URL = normalizeGitHubActionsSyntax(remote.URL)
		remote.Headers = normalizeStringMap(remote.Headers)
		s.Remote = &remote
		return nil
	}

	return fmt.Errorf("invalid server type: %v", s.Type)
}

// MarshalJSON custom marshals the McpServerConfig based on which configuration is set.
func (s Server) MarshalJSON() ([]byte, error) {
	if s.Local != nil {
		temp := struct {
			Tools   []string          `json:"tools"`
			Type    string            `json:"type,omitempty"`
			Command string            `json:"command"`
			Args    []string          `json:"args"`
			Env     map[string]string `json:"env,omitempty"`
		}{
			Tools:   s.Tools,
			Type:    s.Type,
			Command: s.Command,
			Args:    s.Args,
			Env:     s.Env,
		}
		return json.Marshal(temp)
	}

	if s.Remote != nil {
		temp := struct {
			Tools   []string          `json:"tools"`
			Type    string            `json:"type"`
			URL     string            `json:"url"`
			Headers map[string]string `json:"headers,omitempty"`
		}{
			Tools:   s.Tools,
			Type:    s.Type,
			URL:     s.URL,
			Headers: s.Headers,
		}
		return json.Marshal(temp)
	}
	return nil, errors.New("must have either local or remote MCP config")
}

// IsLocal checks if the server type is local or default (empty).
func IsLocal(typeString string) bool {
	return typeString == "local" || typeString == "stdio" || typeString == ""
}

// IsRemote checks if the server type is remote (http or sse).
func IsRemote(typeString string) bool {
	return typeString == "http" || typeString == "sse"
}
