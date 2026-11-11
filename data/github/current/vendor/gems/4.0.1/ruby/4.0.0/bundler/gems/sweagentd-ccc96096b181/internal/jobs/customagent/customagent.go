// Package customagent defines the DBRecord struct representing a custom agent
// stored in the database.
package customagent

// Scope constants define where an agent configuration originates from.
const (
	// ScopeRepo indicates an agent defined in the repository's .github/agents/ directory.
	ScopeRepo = "repo"
	// ScopeOrg indicates an agent defined in the organization's .github repository.
	ScopeOrg = "org"
	// ScopeEnterprise indicates an agent defined in the enterprise's config repository.
	ScopeEnterprise = "enterprise"
	// ScopeJob indicates an agent whose config was passed directly via the Twirp API
	// for a specific job (e.g., triage-agent). Prompt and Permissions are stored on the record.
	ScopeJob = "job"
)

// DBRecord represents a record of a custom agent stored in the database.
type DBRecord struct {
	Name        string      `json:"name"`
	RepoOwner   string      `json:"repo_owner"`
	RepoOwnerID int64       `json:"repo_owner_id"`
	RepoName    string      `json:"repo_name"`
	RepoID      int64       `json:"repo_id"`
	DisplayName string      `json:"display_name"`
	Description string      `json:"description"`
	Tools       []string    `json:"tools"`
	Version     string      `json:"version"`
	MCPServers  []MCPServer `json:"mcp_servers"`
	Target      string      `json:"target"`
	// Metadata is included since we want this to flow into job telemetry
	Metadata map[string]string `json:"metadata"`
	// We are storing configuration errors on the job to aid in triage and include the
	// option for it to be processed when only the MCP portion of the config failed.
	ConfigError      string `json:"config_error,omitempty"`
	InferenceEnabled bool   `json:"inference"`

	// Scope indicates where the agent configuration originates from: "repo", "org", "enterprise", or "job".
	// Empty string defaults to "repo" for backward compatibility with existing records.
	Scope string `json:"scope,omitempty"`

	// Prompt is only populated for job-scoped agents where the config is passed via API.
	// For other scopes, the prompt is fetched from the repository at launch time.
	Prompt string `json:"prompt,omitempty"`

	// Permissions is only populated for job-scoped agents where the config is passed via API.
	// For other scopes, permissions are fetched from the repository at launch time.
	Permissions map[string]string `json:"permissions,omitempty"`

	// ArgumentHint is intentionally omitted since it is only used for display purposes.
	// Handoffs is omitted since it is not supported by CCA or the CLI currently.
	// Triggers need to be stored elsewhere since they are used to determine when a job is created.
}

// IsCopilot returns true if this DBRecord represents the default Copilot agent.
func (db *DBRecord) IsCopilot() bool {
	// TODO (belaltaher8): remove "copilot" portion after this lands in prod to not break jobs currently enqueued when this merges. Going forward db.Name for default agent will be "".
	return db.Name == "copilot" || db.Name == ""
}

// MCPServer represents a server configuration for the custom agent's
// MCP (Multi-Channel Platform).
type MCPServer struct {
	// Fields for both local and remote server types
	Name  string   `json:"name"`
	Type  string   `json:"type"`
	Tools []string `json:"tools"`
	// Fields specific to local server type
	Command string            `json:"command,omitempty"`
	Args    []string          `json:"args,omitempty"`
	Env     map[string]string `json:"env,omitempty"`
	// Fields specific to remote server type
	URL     string            `json:"url,omitempty"`
	Headers map[string]string `json:"headers,omitempty"`
}
