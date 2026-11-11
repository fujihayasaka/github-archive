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
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/sweagentd"
	"gopkg.in/yaml.v3"
)

var (
	// ErrMalformedConfig is returned when the agent configuration is not well-formed markdown with proper frontmatter.
	ErrMalformedConfig = errors.New("malformed agent configuration")

	// ErrToolsFieldIsRequiredWithTip is returned when the tools field is missing from a server under mcp-servers.
	ErrToolsFieldIsRequiredWithTip = errors.New("invalid config: \"mcp-servers.<server>.tools\" is required")

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
	// MaxModelLength is the maximum length of the model field.
	MaxModelLength = 200
	// MaxMetadataEntryCount is the maximum number of entries allowed in the metadata field.
	MaxMetadataEntryCount = 10
	// MaxMetadataKeyLength is the maximum length of a metadata key.
	MaxMetadataKeyLength = 50
	// MaxMetadataValueLength is the maximum length of a metadata value.
	MaxMetadataValueLength = 200
	// MaxToolsetCount is the maximum number of toolsets that can be specified.
	MaxToolsetCount = 50
	// MaxToolsetNameLength is the maximum length of a toolset name.
	MaxToolsetNameLength = 63
	// MaxSkillCount is the maximum number of skills that can be specified.
	MaxSkillCount = 50
	// MaxSkillNameLength is the maximum length of a skill name. 64 characters is the absolute max
	// for a skill name per the runtime schema (see runtime/src/skills/types.ts).
	MaxSkillNameLength = 64
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

// Attributes returns the partially parsed ConfigAttributes from the error.
// This is used by the sync service to persist partial configs with SyncError.
func (e *ErrConfigValidationError) Attributes() ConfigAttributes {
	return e.attributes
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
	DisplayName            string
	Description            string
	Prompt                 string
	Tools                  []string
	MCPConfig              mcpconfig.JSON
	Target                 string
	Metadata               map[string]string
	ArgumentHint           string
	InferenceEnabled       bool
	DisableModelInvocation bool
	UserInvocable          bool
	Model                  string
	Handoffs               []sweagentd.CustomAgentHandoff
	Permissions            permissions.Permissions
	GitHubMCPToolsets      []string
	Triggers               sweagentd.CustomAgentTriggers
	Skills                 []string
}

// NewConfigWithAttributes creates a new Config instance with the provided attributes.
//
//nolint:gocritic // hugeParam: attributes is a large struct but passed by value intentionally for Config construction
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
	Name                   string                         `yaml:"name"`
	Description            string                         `yaml:"description"`
	Tools                  any                            `yaml:"tools"`
	MCPServers             any                            `yaml:"mcp-servers"`
	Target                 string                         `yaml:"target"`
	Metadata               map[string]string              `yaml:"metadata"`
	ArgumentHint           string                         `yaml:"argument-hint"`
	Infer                  *bool                          `yaml:"infer"`                    // TODO: deprecate this field
	DisableModelInvocation *bool                          `yaml:"disable-model-invocation"` // New field to replace Inference
	UserInvocable          *bool                          `yaml:"user-invocable"`
	Model                  string                         `yaml:"model"`
	Handoffs               []sweagentd.CustomAgentHandoff `yaml:"handoffs"`
	Triggers               sweagentd.CustomAgentTriggers  `yaml:"on"`
	GitHub                 yamlGitHub                     `yaml:"github"`
	Skills                 []string                       `yaml:"skills"`
}

// yamlGitHub represents the github-specific configuration in the YAML frontmatter.
type yamlGitHub struct {
	Permissions any      `yaml:"permissions"`
	Toolsets    []string `yaml:"toolsets"`
}

func (y *yamlData) tools() []string {
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
	default:
		// Do nothing - make linter happy
	}
	return tools
}

func (y *yamlData) permissions() permissions.Permissions {
	return permissions.New(y.GitHub.Permissions)
}

func (y *yamlData) toolsets() []string {
	if len(y.GitHub.Toolsets) == 0 {
		return nil
	}
	result := make([]string, len(y.GitHub.Toolsets))
	for i, t := range y.GitHub.Toolsets {
		result[i] = strings.ReplaceAll(t, "-", "_")
	}
	return result
}

// infer will soon be deprecated in favor of DisableModelInvocation but is still supported for backwards compatibility.
func (y *yamlData) infer() bool {
	return !y.disableModelInvocation()
}

func (y *yamlData) disableModelInvocation() bool {
	if y.DisableModelInvocation != nil {
		return *y.DisableModelInvocation
	}
	if y.Infer != nil {
		return !*y.Infer
	}
	return false
}

func (y *yamlData) userInvocable() bool {
	if y.UserInvocable != nil {
		return *y.UserInvocable
	}
	return true
}

func (y *yamlData) mcpConfig(tools []string) (mcpconfig.JSON, error) {
	if y.MCPServers == nil {
		return mcpconfig.JSON{}, nil
	}

	y.fixMissingToolsField(tools)
	normalizeYAMLKeys(y.MCPServers)

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
		return mcpconfig.JSON{}, goerrors.Errorf("invalid MCP config: %w", err)
	}

	for _, server := range servers.Servers {
		if server.Tools == nil {
			return mcpconfig.JSON{}, ErrToolsFieldIsRequiredWithTip
		}
	}

	return servers, nil
}

func (y *yamlData) fixMissingToolsField(tools []string) {
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

// ParseConfigForSync parses a custom agent configuration from markdown content
// for use by the agent sync service. On validation errors, an
// *ErrConfigValidationError is returned which embeds the partially parsed
// attributes. Callers should use errors.As to check for this error type and
// call its Attributes() method to retrieve the partial ConfigAttributes.
// The returned ConfigAttributes value will be zero on error.
func ParseConfigForSync(contents, name string) (ConfigAttributes, error) {
	return parseConfig(contents, name)
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
		DisplayName:            meta.Name,
		Description:            meta.Description,
		Tools:                  meta.tools(),
		Target:                 strings.TrimSpace(meta.Target),
		Prompt:                 prompt,
		Metadata:               meta.Metadata,
		ArgumentHint:           meta.ArgumentHint,
		InferenceEnabled:       meta.infer(),                  // TODO: deprecate this field after we change the runtime to use DisableModelInvocation
		DisableModelInvocation: meta.disableModelInvocation(), // Defaults to false meaning the model selected the custom agent as a tool is enabled
		UserInvocable:          meta.userInvocable(),          // Defaults to true meaning the custom agent can be selected by a user
		Model:                  meta.Model,
		Handoffs:               meta.Handoffs,
		Triggers:               meta.Triggers,
		Permissions:            meta.permissions(),
		GitHubMCPToolsets:      meta.toolsets(),
		Skills:                 meta.Skills,
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

	// Validate Model constraint
	if utf8.RuneCountInString(attr.Model) > MaxModelLength {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: \"model\" exceeds max length of %d", MaxModelLength)}
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
	err = attr.Permissions.Validate()
	if err != nil {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, err: err}
	}

	// Validate Toolsets
	if len(attr.GitHubMCPToolsets) > MaxToolsetCount {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: more than %d toolsets specified", MaxToolsetCount)}
	}
	for _, toolset := range attr.GitHubMCPToolsets {
		if utf8.RuneCountInString(toolset) > MaxToolsetNameLength {
			return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: toolset name exceeds max length of %d", MaxToolsetNameLength)}
		}
	}

	// Validate Skills
	if len(attr.Skills) > MaxSkillCount {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: more than %d skills specified", MaxSkillCount)}
	}
	for _, skill := range attr.Skills {
		if utf8.RuneCountInString(skill) > MaxSkillNameLength {
			return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: fmt.Sprintf("invalid config: skill name exceeds max length of %d", MaxSkillNameLength)}
		}
	}

	// Validate the optional target field - DO THIS LAST so that all other fields are returned in the error
	if !slices.Contains(ValidTargetValues, strings.TrimSpace(meta.Target)) {
		return ConfigAttributes{}, &ErrConfigValidationError{attributes: attr, message: "invalid config: bad value for \"target\""}
	}
	return attr, nil
}

// yamlToJSONKeys maps YAML-style kebab-case keys used in ConfigEntry to their
// JSON camelCase equivalents. Only fields whose YAML and JSON names differ are
// listed; single-word fields like "audience" are the same in both formats.
var yamlToJSONKeys = map[string]string{
	"secret-suffix":      "secretSuffix",
	"grant-type":         "grantType",
	"agent-only-subject": "agentOnlySubject",
	"repo-only-subject":  "repoOnlySubject",
	"public-client":      "publicClient",
	"redirect-port":      "redirectPort",
}

// normalizeYAMLKeys renames YAML-style kebab-case OIDC/Auth keys to their JSON
// camelCase equivalents, but only within "oidc" and "auth" config blocks.
// This avoids rewriting similarly named keys in unrelated maps such as
// per-server headers and env.
func normalizeYAMLKeys(v any) {
	normalizeYAMLKeysWithDepth(v, 0, false)
}

func normalizeYAMLKeysWithDepth(v any, depth int, inAuthBlock bool) {
	const maxDepth = 5
	if depth >= maxDepth {
		return
	}

	switch typed := v.(type) {
	case map[string]any:
		if inAuthBlock {
			renameKeys(typed, yamlToJSONKeys)
		}
		for key, child := range typed {
			childInAuthBlock := inAuthBlock || key == "oidc" || key == "auth"
			normalizeYAMLKeysWithDepth(child, depth+1, childInAuthBlock)
		}
	case []any:
		for _, item := range typed {
			normalizeYAMLKeysWithDepth(item, depth+1, inAuthBlock)
		}
	default:
		// Do nothing - no need to normalize
	}
}

func renameKeys(m map[string]any, keyMap map[string]string) {
	for yamlKey, jsonKey := range keyMap {
		val, ok := m[yamlKey]
		if !ok {
			continue
		}
		if _, exists := m[jsonKey]; !exists {
			m[jsonKey] = val
		}
		delete(m, yamlKey)
	}
}
