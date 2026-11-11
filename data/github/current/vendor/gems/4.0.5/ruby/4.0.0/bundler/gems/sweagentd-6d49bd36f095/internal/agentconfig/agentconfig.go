// Package agentconfig provides the agent configuration structures and interfaces
// shared across different components of the system, such as custom agents and
// associated stores.
package agentconfig

// Scope constants define where an agent configuration originates from.
const (
	// ScopeJob indicates an agent whose config was passed directly via the Twirp API
	// for a specific job (e.g., triage-agent).
	// Prompt and Permissions are stored on the AgentConfig record in this case.
	ScopeJob = "job"
	// ScopeRepository indicates an agent defined in the repository's .github/agents/ directory.
	ScopeRepository = "repository"
	// ScopeOrganization indicates an agent defined in the organization's .github repository.
	ScopeOrganization = "organization"
	// ScopeEnterprise indicates an agent defined in the enterprise's config repository.
	ScopeEnterprise = "enterprise"
	// ScopePlugin indicates an agent defined in a plugin repository.
	ScopePlugin = "plugin"
)
