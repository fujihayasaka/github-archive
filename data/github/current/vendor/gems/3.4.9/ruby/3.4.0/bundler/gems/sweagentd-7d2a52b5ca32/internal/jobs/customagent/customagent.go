package customagent

// DBRecord represents a record of a custom agent stored in the database.
type DBRecord struct {
	Name        string      `json:"name"`
	RepoOwner   string      `json:"repo_owner"`
	RepoOwnerID int64       `json:"repo_owner_id"`
	RepoName    string      `json:"repo_name"`
	RepoID      int64       `json:"repo_id"`
	DisplayName string      `json:"display_name"`
	Description string      `json:"description"`
	Prompt      string      `json:"prompt"`
	Tools       []string    `json:"tools"`
	Version     string      `json:"version"`
	MCPServers  []MCPServer `json:"mcp_servers"`
	Target      string      `json:"target"`
	// We are storing configuration errors on the job to aid in triage and include the
	// option for it to be processed when only the MCP portion of the config failed.
	ConfigError string `json:"config_error,omitempty"`
}

// IsCopilot returns true if this DBRecord represents the default Copilot agent.
func (db *DBRecord) IsCopilot() bool {
	// TODO: Technically this name could be used by a customer, so we should update how we identify the default agent.
	// We should also update the customagent.Agent.IsCopilot method to match this logic as it updates.
	return db.Name == "copilot"
}

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
