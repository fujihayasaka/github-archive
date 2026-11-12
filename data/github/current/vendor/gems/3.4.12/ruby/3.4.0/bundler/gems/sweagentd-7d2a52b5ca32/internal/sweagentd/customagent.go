package sweagentd

import (
	"strings"

	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
)

// CustomAgent represents a specialized agent with specific configurations and capabilities.
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

	// Functions
	ToDB() customagent.DBRecord
	IsCopilot() bool // Returns whether this is the default agent

	// Deprecated - instructions are applied by the runtime now
	// TODO: Remove this method along with the callback API v2 feature flag
	Instructions() CustomAgentInstructions
}

// Deprecated - instructions are applied by the runtime now
// TODO: Remove this method along with the callback API v2 feature flag
type CustomAgentInstructions interface {
	WritePrompt(sb *strings.Builder)
	RemovePrompt(problemStatement string) string
}
