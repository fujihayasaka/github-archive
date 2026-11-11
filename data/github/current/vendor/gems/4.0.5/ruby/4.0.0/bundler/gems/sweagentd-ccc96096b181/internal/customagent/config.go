package customagent

import (
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/sweagentd"
	"gopkg.in/yaml.v3"
)

var (
	// ErrMalformedConfig is returned when the agent configuration is not well-formed markdown with proper frontmatter.
	ErrMalformedConfig = errors.New("malformed agent configuration")

	// ErrToolsFieldIsRequiredWithTip is returned when the tools field is missing from a server under mcp-servers.
	ErrToolsFieldIsRequiredWithTip = errors.New("invalid config: \"mcp-servers.<server>.tools\" is required")

	// ErrInvalidPermissionValue is returned when an invalid permission value is specified.
	ErrInvalidPermissionValue = errors.New("invalid config: invalid permissions value")

	// ErrInvalidPermission is returned when an invalid / unsupported permission is specified.
	ErrInvalidPermission = errors.New("invalid config: invalid permission")

	// MaxNameLength is the maximum length of the name field. 64 is the absolute max for tool names.
	// However, we need to account for a possible `.gh:`, prefix, so 60 keeps us under that.
	MaxNameLength = 60
	// MaxDescriptionLength is the maximum length of the description field. 1024 is the absolute max for tool
	// descriptions. However, the runtime adds a prefix we need to account for, so we set it to 1000 here.
	// See https://github.com/github/sweagentd/blob/1e0cef22c0392acf1750a189a52fecd35d0d4ef3/runtime/src/agents/agentPrimitives.ts#L808
	MaxDescriptionLength = 1000
	// MaxPromptLength is the maximum length of the prompt field.
	MaxPromptLength = 30000
	// MaxToolCount is the maximum number of tools that can be specified.
	MaxToolCount = 200
	// MaxToolNameLength is the maximum length of a tool name. 64 characters is the absolute max for a tool name
	// and we need to account for a possible __ replacement for `/` in the MCP server name
	MaxToolNameLength = 63
	// MaxMCPServerCount is the maximum number of MCP servers that can be specified.
	MaxMCPServerCount = 50
	// MaxArgumentHintLength is the maximum length of the argument-hint field.
	MaxArgumentHintLength = 200
	// MaxMetadataEntryCount is the maximum number of entries allowed in the metadata field.
	MaxMetadataEntryCount = 10
	// MaxMetadataKeyLength is the maximum length of a metadata key.
	MaxMetadataKeyLength = 50
	// MaxMetadataValueLength is the maximum length of a metadata value.
	MaxMetadataValueLength = 200
	// DefaultPermissions defines the default permissions for a custom agent if none are specified.
	// We are mirroring Action's permissions object, so we use a "-" in the names here, scopes use "_".
	DefaultPermissions = map[string]string{
		"actions":       "read",
		"contents":      "read",
		"issues":        "read",
		"metadata":      "read",
		"pull-requests": "read",
	}
	// AllowedPermissions defines the acceptable permission levels for the permissions field in the custom agent configuration.
	// Subset of: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#defining-access-for-the-github_token-scopes
	AllowedPermissions = []string{"actions", "contents", "issues", "metadata", "pull-requests", "workflows", "checks"}
	// AllowedPermissionValues defines the acceptable values for each permission scope.
	// Based on GitHub documentation: https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions
	// and what the current copilot-swe-agent global app has access to.
	AllowedPermissionValues = map[string][]string{
		"actions":       {"read", "write", "none"},
		"contents":      {"read", "write", "none"},
		"issues":        {"read", "write", "none"},
		"metadata":      {"read"}, // metadata only supports read access
		"pull-requests": {"read", "write", "none"},
		"workflows":     {"write", "none"},
		"checks":        {"read", "none"},
	}
)

const (
	// TargetEmpty is the target value for no specific target.
	TargetEmpty string = ""

	// TargetGitHubCopilot is the target value for GitHub Copilot.
	TargetGitHubCopilot string = "github-copilot"

	// TargetVSCode is the target value for VS Code.
	TargetVSCode string = "vscode"
)

// ValidTargetValues defines the acceptable values for the 'target' field in the custom agent configuration.
var ValidTargetValues = []string{TargetEmpty, TargetGitHubCopilot, TargetVSCode}

// ErrConfigValidationError is returned when there is a general error parsing the custom agent configuration.
type ErrConfigValidationError struct {
	attributes ConfigAttributes // Partial agent that was parsed before the error occurred
	err        error            // Wrapped error, if any
	message    string           // Used in the event there's no wrapped error
}

func (e *ErrConfigValidationError) Error() string {
	msg := e.message
	if e.err != nil {
		msg = e.err.Error()
	}
	return fmt.Sprintf("error parsing custom agent configuration: %s", msg)
}

// ValidationMessage returns just the message related to the validation failure rather than the full error string.
func (e *ErrConfigValidationError) ValidationMessage() string {
	msg := e.message
	if e.err != nil {
		msg = e.err.Error()
	}
	if msg == "" {
		return "Unknown validation error"
	}
	return strings.ToUpper(string(msg[0])) + msg[1:]
}

// Config returns a partially parsed Config from the error's attributes.
func (e *ErrConfigValidationError) Config() *Config {
	return &Config{attributes: e.attributes}
}

// Unwrap returns the wrapped error, if any.
func (e *ErrConfigValidationError) Unwrap() error {
	if e.err == nil {
		return goerrors.New(e.message)
	}
	return e.err
}

// Config represents the configuration for a custom agent, including its metadata and prompt.
type Config struct {
	attributes ConfigAttributes
}

// ConfigAttributes holds the attributes of a custom agent configuration.
type ConfigAttributes struct {
	DisplayName      string
	Description      string
	Prompt           string
	Tools            []string
	MCPConfig        mcpconfig.JSON
	Target           string
	Metadata         map[string]string
	ArgumentHint     string
	InferenceEnabled bool
	Model            string
	Handoffs         []sweagentd.CustomAgentHandoff
	Permissions      map[string]string
	Triggers         sweagentd.CustomAgentTriggers
}

// NewConfigWithAttributes creates a new Config instance with the provided attributes.
func NewConfigWithAttributes(attributes ConfigAttributes) *Config {
	return &Config{
		attributes: attributes,
	}
}

// newConfigFromContents creates a new Config instance with the provided base64 encoded contents.
func newConfigFromContents(contents, name string) (*Config, error) {
	attrs, err := parseConfig(contents, name)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse agent configuration: %w", err)
	}

	return &Config{attributes: attrs}, nil
}

// prompt returns the prompt for the custom agent
func (c *Config) prompt() string {
	return c.attributes.Prompt
}

// tools returns the list of tools for the custom agent
func (c *Config) tools() []string {
	return c.attributes.Tools
}

// mcpServers returns the raw MCP servers configuration
func (c *Config) mcpConfig() mcpconfig.JSON {
	return c.attributes.MCPConfig
}

const frontmatterIdentifier = "---"

// yamlData represents the YAML frontmatter metadata for a custom agent configuration.
type yamlData struct {
	Name         string                         `yaml:"name"`
	Description  string                         `yaml:"description"`
	Tools        any                            `yaml:"tools"`
	MCPServers   any                            `yaml:"mcp-servers"`
	Target       string                         `yaml:"target"`
	Metadata     map[string]string              `yaml:"metadata"`
	ArgumentHint string                         `yaml:"argument-hint"`
	Inference    *bool                          `yaml:"infer"`
	Model        string                         `yaml:"model"`
	Handoffs     []sweagentd.CustomAgentHandoff `yaml:"handoffs"`
	Triggers     sweagentd.CustomAgentTriggers  `yaml:"on"`
	Permissions  any                            `yaml:"permissions"`
}

func (y yamlData) tools() []string {
	// Support both Claude Code style comma separated string and VS Code / GitHub style with array of strings
	tools := []string{}
	switch v := y.Tools.(type) {
	case nil:
		return []string{"*"}
	case string:
		toolParts := strings.Split(v, ",")
		for _, tool := range toolParts {
			trimmed := strings.TrimSpace(tool)
			if trimmed != "" {
				tools = append(tools, trimmed)
			}
		}
		return tools
	case []any:
		for _, item := range v {
			if str, ok := item.(string); ok {
				tools = append(tools, str)
			}
		}
	}
	return tools
}

func (y yamlData) permissions() map[string]string {
	// Support both string and map[string]string for permissions
	switch v := y.Permissions.(type) {
	case string:
		switch v {
		case "read-all":
			perms := make(map[string]string, len(AllowedPermissions))
			for _, perm := range AllowedPermissions {
				if slices.Contains(AllowedPermissionValues[perm], "read") {
					perms[perm] = "read"
				}
			}
			return perms
		case "write-all":
			perms := make(map[string]string, len(AllowedPermissions))
			for _, perm := range AllowedPermissions {
				if slices.Contains(AllowedPermissionValues[perm], "write") {
					perms[perm] = "write"
				} else {
					perms[perm] = "read"
				}
			}
			return perms
		default:
			return DefaultPermissions
		}
	case map[string]any:
		// Convert map[string]any to map[string]string
		perms := map[string]string{}
		for key, val := range v {
			if str, ok := val.(string); ok {
				perms[key] = str
			}
		}
		// Metadata must always be read
		perms["metadata"] = "read"
		return perms
	default:
		return DefaultPermissions
	}
}

func (y yamlData) mcpConfig(tools []string) (mcpconfig.JSON, error) {
	if y.MCPServers == nil {
		return mcpconfig.JSON{}, nil
	}

	y.fixMissingToolsField(tools)

	wrappedServers := map[string]any{
		"mcpServers": y.MCPServers,
	}
	jsonBytes, err := json.Marshal(wrappedServers)
	if err != nil {
		return mcpconfig.JSON{}, goerrors.Errorf("invalid MCP config: %w", err)
	}

	var servers mcpconfig.JSON
	err = json.Unmarshal(jsonBytes, &servers)
	if err != nil {
		if errors.Is(err, mcpconfig.ErrToolsFieldIsRequired) {
			return mcpconfig.JSON{}, ErrToolsFieldIsRequiredWithTip
		}
		return mcpconfig.JSON{}, goerrors.Errorf("invalid MCP config: %w", err)
	}

	return servers, nil
}

func (y yamlData) fixMissingToolsField(tools []string) {
	serversMap, ok := y.MCPServers.(map[string]any)
	if !ok {
		return
	}

	referencedServers := map[string]bool{}
	for _, tool := range tools {
		parts := strings.Split(tool, "/")
		if len(parts) < 2 {
			continue // Skip any tools we couldn't find a server name for
		}
		serverName := parts[0]
		referencedServers[serverName] = true
	}

	for serverName := range referencedServers {
		serverEntry, exists := serversMap[serverName]
		if !exists {
			continue // Server not defined in mcp-servers
		}
		serverProps, ok := serverEntry.(map[string]any)
		if !ok {
			continue // Invalid server entry format
		}
		if _, hasTools := serverProps["tools"]; !hasTools {
			// Add default tools field
			serverProps["tools"] = []string{"*"}
		}
	}
}

// parseConfig parses the custom agent configuration from the given markdown content.
// ErrConfigValidationError will be returned for validation errors with details including a partially filled ConfigAttributes.
func parseConfig(contents, name string) (ConfigAttributes, error) {
	md := strings.TrimSpace(contents)

	// We only support LF line endings for frontmatter parsing, so normalize CRLF to LF
	md = strings.ReplaceAll(md, "\r\n", "\n")

	// Check if content starts with frontmatter delimiter
	if !strings.HasPrefix(md, frontmatterIdentifier+"\n") {
		return ConfigAttributes{}, goerrors.Errorf("%w: markdown content must start with YAML frontmatter delimited by '---'", ErrMalformedConfig)
	}

	// Find the closing frontmatter delimiter
	lines := strings.Split(md, "\n")

	var frontmatterEnd int

	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == frontmatterIdentifier {
			frontmatterEnd = i
			break
		}
	}

	if frontmatterEnd == 0 {
		return ConfigAttributes{}, goerrors.Errorf("%w: could not find closing '---' delimiter for YAML frontmatter", ErrMalformedConfig)
	}

	// Extract frontmatter and prompt
	frontmatter := strings.Join(lines[1:frontmatterEnd], "\n")

	// Parse YAML frontmatter
	var meta yamlData

	err := yaml.Unmarshal([]byte(frontmatter), &meta)
	if err != nil {
		return ConfigAttributes{}, goerrors.Errorf("%w: failed to parse YAML frontmatter: %w", ErrMalformedConfig, err)
	}

	// Extract prompt (everything after the closing ---)
	var prompt string
	if frontmatterEnd+1 < len(lines) {
		prompt = strings.TrimSpace(strings.Join(lines[frontmatterEnd+1:], "\n"))
	}

	// Set attributes so we can return what they are set to in case of validation error
	attr := ConfigAttributes{
		DisplayName:      meta.Name,
		Description:      meta.Description,
		Tools:            meta.tools(),
		Target:           strings.TrimSpace(meta.Target),
		Prompt:           prompt,
		Metadata:         meta.Metadata,
		ArgumentHint:     meta.ArgumentHint,
		InferenceEnabled: meta.Inference == nil || *meta.Inference, // Enable by default, disable only if explicitly set to false
		Model:            meta.Model,
		Handoffs:         meta.Handoffs,
		Triggers:         meta.Triggers,
		Permissions:      meta.permissions(),
	}

	// TODO: Add validations for Triggers once we're past the PoC stage

	// Validate fields according to SPEC
	if strings.TrimSpace(attr.DisplayName) == "" {
		attr.DisplayName = name
	}
	if len(attr.DisplayName) > MaxNameLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"name\" exceeds max length of %d", MaxNameLength)}
	}
	if strings.TrimSpace(attr.Description) == "" {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: "invalid config: field \"description\" is required"}
	}
	if utf8.RuneCountInString(attr.Description) > MaxDescriptionLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"description\" exceeds max length of %d", MaxDescriptionLength)}
	}
	if utf8.RuneCountInString(attr.Prompt) > MaxPromptLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"prompt\" exceeds max length of %d", MaxPromptLength)}
	}
	if len(attr.Tools) > MaxToolCount {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: more than %d tools specified", MaxToolCount)}
	}
	for _, tool := range attr.Tools {
		if utf8.RuneCountInString(tool) > MaxToolNameLength {
			return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: tool name exceeds max length of %d", MaxToolNameLength)}
		}
	}
	mcpConfig, err := meta.mcpConfig(attr.Tools)
	if err != nil {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, err: err}
	}
	attr.MCPConfig = mcpConfig
	if len(mcpConfig.Servers) > MaxMCPServerCount {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: more than %d MCP servers specified", MaxMCPServerCount)}
	}

	// Validate ArgumentHint constraint
	if utf8.RuneCountInString(attr.ArgumentHint) > MaxArgumentHintLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"argument-hint\" exceeds max length of %d", MaxArgumentHintLength)}
	}

	// Validate Metadata constraints
	if len(attr.Metadata) > MaxMetadataEntryCount {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: metadata has more than %d entries", MaxMetadataEntryCount)}
	}
	for k, v := range attr.Metadata {
		if utf8.RuneCountInString(k) > MaxMetadataKeyLength {
			return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: metadata key exceeds max length of %d", MaxMetadataKeyLength)}
		}
		if utf8.RuneCountInString(v) > MaxMetadataValueLength {
			return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: metadata value exceeds max length of %d", MaxMetadataValueLength)}
		}
	}

	// Validate Permissions
	err = validatePermissions(attr.Permissions)
	if err != nil {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, err: err}
	}

	// Validate the optional target field - DO THIS LAST so that all other fields are returned in the error
	if !slices.Contains(ValidTargetValues, strings.TrimSpace(meta.Target)) {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: "invalid config: bad value for \"target\""}
	}
	return attr, nil
}

func validatePermissions(permissions map[string]string) error {
	for key, value := range permissions {
		allowedValues, ok := AllowedPermissionValues[key]
		if !ok {
			return goerrors.Errorf("%w %q", ErrInvalidPermission, key)
		}
		if !slices.Contains(allowedValues, value) {
			return goerrors.Errorf("%w %q for %q", ErrInvalidPermissionValue, value, key)
		}
	}
	return nil
}

// PermissionsToDotComPermissions converts a permissions map to GitHub.com permissions format (replacing "-" with "_").
// Used here, in launcher, and in tests for validation. It validates that both permission keys and values are allowed based on GitHub documentation.
func PermissionsToDotComPermissions(permissions map[string]string) (map[string]string, error) {
	if len(permissions) == 0 {
		permissions = DefaultPermissions
	} else {
		err := validatePermissions(permissions)
		if err != nil {
			return nil, err
		}
	}
	// Convert actions style "permissions" with a "-" to ghPerms with "_"
	ghPerms := make(map[string]string, len(permissions))
	for key, value := range permissions {
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
