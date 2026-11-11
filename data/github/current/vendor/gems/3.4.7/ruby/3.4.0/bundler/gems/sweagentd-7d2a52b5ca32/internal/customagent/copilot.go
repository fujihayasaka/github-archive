package customagent

// Copilot is a convenience function to create a Copilot Agent instance.
// It initializes the Agent with the default Copilot configuration.
// It mostly provides a noop capability throughout the system that are using
// custom agents. Its possible that it grows in the future to provide
// more functionality at the service level to the agent orchestrations.
func Copilot(repoOwnerID, repoID int64, repoOwner, repoName string) *Agent {
	m := Metadata{
		Name:        DefaultAgentName,
		RepoID:      repoID,
		RepoOwner:   repoOwner,
		RepoOwnerID: repoOwnerID,
		RepoName:    repoName,
	}
	attrs := ConfigAttributes{
		DisplayName: DefaultAgentDisplayName,
		Tools:       []string{"*"},
	}

	return NewWithConfig(m, NewConfigWithAttributes(attrs))
}

// DefaultAgentName is the name of the default Copilot agent.
const DefaultAgentName = "copilot"

// DefaultAgentDisplayName is the display name of the default Copilot agent.
const DefaultAgentDisplayName = "Copilot"
