package customagent

import (
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"gopkg.in/yaml.v3"
)

var (
	// ErrMalformedConfig is returned when the agent configuration is not well-formed markdown with proper frontmatter.
	ErrMalformedConfig = errors.New("malformed agent configuration")

	// ErrTargetIsVSCode is returned when the target field is set to a value that should not be picked up by CCA or the CLI.
	ErrTargetIsVSCode = errors.New("config is for VS Code only")

	// ErrToolsFieldIsRequiredWithTip is returned when the tools field is missing from a server under mcp-servers.
	ErrToolsFieldIsRequiredWithTip = errors.New("invalid config: \"mcp-servers.<server>.tools\" is required")

	// MaxNameLength is the maximum length of the name field.
	MaxNameLength = 100
	// MaxDescriptionLength is the maximum length of the description field. 1024 is the absolute max for tool
	// descriptions. However, the runtime adds a prefix we need to account for, so we set it to 1000 here.
	// See https://github.com/github/sweagentd/blob/1e0cef22c0392acf1750a189a52fecd35d0d4ef3/runtime/src/agents/agentPrimitives.ts#L808
	MaxDescriptionLength = 1000
	// MaxPromptLength is the maximum length of the prompt field.
	MaxPromptLength = 30000
	// MaxToolCount is the maximum number of tools that can be specified.
	MaxToolCount = 200
	// MaxToolNameLength is the maximum length of a tool name.
	MaxToolNameLength = 100
	// MaxMCPServerCount is the maximum number of MCP servers that can be specified.
	MaxMCPServerCount = 50
)

// ValidTargetValues defines the acceptable values for the 'target' field in the custom agent configuration.
var ValidTargetValues = []string{"", "github-copilot", "vscode"}

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
		return errors.New(e.message)
	}
	return e.err
}

// Config represents the configuration for a custom agent, including its metadata and prompt.
type Config struct {
	attributes ConfigAttributes
}

// ConfigAttributes holds the attributes of a custom agent configuration.
type ConfigAttributes struct {
	DisplayName string
	Description string
	Prompt      string
	Tools       []string
	MCPConfig   mcpconfig.JSON
	Target      string
}

// NewConfigWithAttributes creates a new Config instance with the provided attributes.
func NewConfigWithAttributes(attributes ConfigAttributes) *Config {
	return &Config{
		attributes: attributes,
	}
}

// newConfigFromContents creates a new Config instance with the provided base64 encoded contents.
func newConfigFromContents(contents, defaultName string) (*Config, error) {
	attrs, err := parseConfig(contents, defaultName)
	if err != nil {
		return nil, fmt.Errorf("failed to parse agent configuration: %w", err)
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
	Name        string `yaml:"name"`
	Description string `yaml:"description"`
	Tools       any    `yaml:"tools"`
	MCPServers  any    `yaml:"mcp-servers"`
	Target      string `yaml:"target"`
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
		return mcpconfig.JSON{}, fmt.Errorf("invalid MCP config: %w", err)
	}

	var servers mcpconfig.JSON
	err = json.Unmarshal(jsonBytes, &servers)
	if err != nil {
		if errors.Is(err, mcpconfig.ErrToolsFieldIsRequired) {
			return mcpconfig.JSON{}, ErrToolsFieldIsRequiredWithTip
		}
		return mcpconfig.JSON{}, fmt.Errorf("invalid MCP config: %w", err)
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
func parseConfig(contents, defaultName string) (ConfigAttributes, error) {
	md := strings.TrimSpace(contents)

	// We only support LF line endings for frontmatter parsing, so normalize CRLF to LF
	md = strings.ReplaceAll(md, "\r\n", "\n")

	// Check if content starts with frontmatter delimiter
	if !strings.HasPrefix(md, frontmatterIdentifier+"\n") {
		return ConfigAttributes{}, fmt.Errorf("%w: markdown content must start with YAML frontmatter delimited by '---'", ErrMalformedConfig)
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
		return ConfigAttributes{}, fmt.Errorf("%w: could not find closing '---' delimiter for YAML frontmatter", ErrMalformedConfig)
	}

	// Extract frontmatter and prompt
	frontmatter := strings.Join(lines[1:frontmatterEnd], "\n")

	// Parse YAML frontmatter
	var meta yamlData

	err := yaml.Unmarshal([]byte(frontmatter), &meta)
	if err != nil {
		return ConfigAttributes{}, fmt.Errorf("%w: failed to parse YAML frontmatter: %w", ErrMalformedConfig, err)
	}

	// Extract prompt (everything after the closing ---)
	var prompt string
	if frontmatterEnd+1 < len(lines) {
		prompt = strings.TrimSpace(strings.Join(lines[frontmatterEnd+1:], "\n"))
	}

	// Set attributes so we can return what they are set to in case of validation error
	attr := ConfigAttributes{
		DisplayName: meta.Name,
		Description: meta.Description,
		Tools:       meta.tools(),
		Target:      strings.TrimSpace(meta.Target),
		Prompt:      prompt,
	}

	// Validate fields according to SPEC
	if strings.TrimSpace(attr.DisplayName) == "" {
		attr.DisplayName = defaultName
	}
	if len(attr.DisplayName) > MaxNameLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"name\" exceeds max length of %d", MaxNameLength)}
	}
	if strings.TrimSpace(attr.Description) == "" {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: "invalid config: field \"description\" is required"}
	}
	if len(attr.Description) > MaxDescriptionLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"description\" exceeds max length of %d", MaxDescriptionLength)}
	}
	if len(attr.Prompt) > MaxPromptLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"prompt\" exceeds max length of %d", MaxPromptLength)}
	}
	if len(attr.Tools) > MaxToolCount {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: more than %d tools specified", MaxToolCount)}
	}
	for _, tool := range attr.Tools {
		if len(tool) > MaxToolNameLength {
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

	// Validate the optional target field
	if !slices.Contains(ValidTargetValues, strings.TrimSpace(meta.Target)) {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: "invalid config: bad value for \"target\""}
	}

	// If target is 'vscode', reject it with a specific error even though it's a valid value
	if attr.Target == "vscode" {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, err: ErrTargetIsVSCode}
	}

	return attr, nil
}
