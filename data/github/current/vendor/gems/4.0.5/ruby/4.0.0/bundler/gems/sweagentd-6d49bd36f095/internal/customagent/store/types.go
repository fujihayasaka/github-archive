// Package store defines the interfaces and types for persisting custom agent
// configurations to a database. Each agent scope (repository, organization, enterprise)
// uses its own container but shares the same interface and record types.
package store

import (
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/sweagentd"
)

// AgentAncestor represents the ancestor scope of an agent configuration.
type AgentAncestor struct {
	// Scope is one of "repository", "organization", or "enterprise".
	Scope string `json:"scope"`
	// ScopeID is the ID of the ancestor scope.
	ScopeID int64 `json:"scope_id"`
}

// AgentRecord represents a custom agent configuration document stored in CosmosDB.
// Each record corresponds to a single agent config file within a scope (repository, organization, or enterprise).
type AgentRecord struct {
	// ID is a UUID generated on first sync.
	ID string `json:"id"`
	// ScopeID is the CosmosDB partition key. Its meaning depends on the container:
	//   - Repository container:   the repo ID
	//   - Organization container: the org (owner) ID
	//   - Enterprise container:   the business ID (from Hydro Repository.business_id)
	ScopeID int64 `json:"scope_id"`
	// Ancestors holds the ancestor scopes of this agent configuration.
	Ancestors []AgentAncestor `json:"ancestors,omitempty"`
	// Path is the file path to the config file (e.g., ".github/agents/my-agent.md").
	Path string `json:"path"`
	// Config holds the full parsed agent configuration.
	Config AgentConfig `json:"config"`
	// TreeOID is the commit SHA of the source file.
	TreeOID string `json:"tree_oid"`
	// CreatedAt is the unix timestamp of first detection.
	CreatedAt int64 `json:"created_at"`
	// SyncedAt is the unix timestamp of the last sync.
	SyncedAt int64 `json:"synced_at"`
	// UpdatedAt is the unix timestamp of the last update to the record.
	UpdatedAt int64 `json:"_ts,omitempty"`
	// SyncError is an error message if the last sync failed.
	SyncError string `json:"sync_error,omitempty"`
	// ETag is the CosmosDB ETag used for optimistic concurrency control.
	ETag *azcore.ETag `json:"_etag,omitempty"`
}

// SetTimestamps sets CreatedAt (if zero) and SyncedAt to the current time.
func (r *AgentRecord) SetTimestamps() {
	now := time.Now().Unix()
	if r.CreatedAt == 0 {
		r.CreatedAt = now
	}
	r.SyncedAt = now
}

// AgentConfig holds the full parsed configuration for a custom agent.
// This is stored as a nested JSON object within the AgentRecord document.
type AgentConfig struct {
	Name        string `json:"name"`
	DisplayName string `json:"display_name"`
	Description string `json:"description"`

	Tools                  []string                       `json:"tools"`
	MCPServers             []MCPServer                    `json:"mcp_servers"`
	Target                 string                         `json:"target,omitempty"`
	Metadata               map[string]string              `json:"metadata,omitempty"`
	ArgumentHint           string                         `json:"argument_hint,omitempty"`
	InferenceEnabled       bool                           `json:"infer"`
	DisableModelInvocation bool                           `json:"disable_model_invocation"`
	UserInvocable          bool                           `json:"user_invocable"`
	Model                  string                         `json:"model,omitempty"`
	Handoffs               []sweagentd.CustomAgentHandoff `json:"handoffs,omitempty"`

	Permissions permissions.Permissions       `json:"permissions"`
	Triggers    sweagentd.CustomAgentTriggers `json:"triggers"`

	// GitHubMCPToolsets configures which toolsets are enabled on the built-in GitHub MCP server.
	GitHubMCPToolsets []string `json:"github_mcp_toolsets,omitempty"`

	// Skills is the list of skill names to preload into this agent's context.
	Skills []string `json:"skills,omitempty"`

	// Prompt is only populated for job-scoped agents where the config is passed via API.
	// For other scopes, the prompt is fetched from the repository at launch time.
	Prompt string `json:"prompt,omitempty"`
}

// MCPServer represents a server configuration for the custom agent's
// MCP (Multi-Context Protocol).
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
