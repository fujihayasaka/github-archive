package customagent

import (
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/permissions"
)

// CopilotAgent represents the default Copilot custom agent.
type CopilotAgent struct {
	*Agent
}

// Copilot is a convenience function to create a Copilot Agent instance.
// It initializes the Agent with the default Copilot configuration.
// It mostly provides a noop capability throughout the system that are using
// custom agents. Its possible that it grows in the future to provide
// more functionality at the service level to the agent orchestrations.
func Copilot(repoOwnerID, repoID int64, repoOwner, repoName string) *CopilotAgent {
	m := Metadata{
		Name:        "",
		RepoID:      repoID,
		RepoOwner:   repoOwner,
		RepoOwnerID: repoOwnerID,
		RepoName:    repoName,
		Scope:       agentconfig.ScopeRepository,
	}
	attrs := ConfigAttributes{
		DisplayName: "",
		Tools:       []string{"*"},
		Permissions: permissions.Unset, // Use unset permissions so repo-level can kick in
	}

	return &CopilotAgent{
		Agent: NewWithConfig(m, NewConfigWithAttributes(attrs)),
	}
}

// DefaultAgentName is the name of the default Copilot agent.
const DefaultAgentName = "copilot"

// DefaultAgentDisplayName is the display name of the default Copilot agent.
const DefaultAgentDisplayName = "Copilot"
