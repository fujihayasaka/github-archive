package sweagentd

import (
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
)

// CustomAgentHandoff represents one of a list of handoffs in custom agent config for VS Code.
// https://code.visualstudio.com/docs/copilot/customization/custom-chat-modes#_header-optional
type CustomAgentHandoff struct {
	// Label is the display label for the handoff option.
	Label string `json:"label" yaml:"label"`
	// Agent is the identifier of the handoff agent.
	Agent string `json:"agent" yaml:"agent"`
	// Prompt is an optional prompt to provide context for the handoff.
	Prompt string `json:"prompt" yaml:"prompt"`
	// Send indicates whether to send the current conversation to the handoff agent.
	Send bool `json:"send" yaml:"send"`
}

// CustomAgentTriggers defines the events that a custom agent can respond to.
type CustomAgentTriggers struct {
	// We only want to exclude these if they are nil since non-nil but empty has
	// meaning in the Actions syntax
	Issues *CustomAgentTrigger `json:"issues,omitempty" yaml:"issues,omitempty"`
}

// CustomAgentTrigger is a base struct that defines a specific event type for a
// custom agent. Some events will have more properties
type CustomAgentTrigger struct {
	// Types is a list of event types that the agent should respond to.
	Types []string `json:"types,omitempty" yaml:"types,omitempty"`
}

// CustomAgent represents a specialized agent with specific configurations andcapabilities.
//
//nolint:interfacebloat // CustomAgent interface requires many methods to fully represent agent configuration
type CustomAgent interface {
	Name() string
	RepoOwnerID() int64
	RepoOwner() string
	RepoID() int64
	RepoName() string
	DisplayName() string
	Description() string
	Prompt() string
	Tools() []string
	Version() string
	MCPConfig() mcpconfig.JSON
	Target() string
	ConfigError() string
	Metadata() map[string]string
	ArgumentHint() string
	InferenceEnabled() bool
	Model() string
	Handoffs() []CustomAgentHandoff
	Permissions() map[string]string
	Triggers() CustomAgentTriggers
	// Scope returns the origin scope of the agent: "repo", "org", "enterprise", or "job".
	Scope() string

	// Functions
	ToDB() customagent.DBRecord
}
