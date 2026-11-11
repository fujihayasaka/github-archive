// Package customagent provides functionality for managing custom agents.
// A custom agent is a specialized configuration that lives at .github/agents/<custom_agent_name> in the repository.
// It is used to customize the behavior of the Copilot Agent for specific tasks or workflows.
package customagent

import (
	"context"

	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/sweagentd"
)

// Metadata contains the basic information about a custom agent.
type Metadata struct {
	Name        string
	RepoID      int64
	RepoOwner   string
	RepoOwnerID int64
	RepoName    string
	Version     string
	ConfigError string
	Filename    string // Filename is used for logging and testing
}

// Agent represents a custom agent that has specific user-defined configurations.
type Agent struct {
	metadata Metadata
	cfg      *Config
}

// PrivilegedAgent represents an organization/enterprise-level custom agent with extended capabilities.
type PrivilegedAgent struct {
	*Agent
}

// FromRepo creates a new Agent instance by fetching the configuration from the specified repository for the given metadata.
func FromRepo(ctx context.Context, me Metadata, repo *Repository, errorOnInvalidConfig bool) (*Agent, error) {
	return repo.agent(ctx, me, errorOnInvalidConfig)
}

// NewWithConfig creates a new Agent instance with the provided metadata and configuration.
// This is useful when the configuration is already known and does not need to be fetched from the repository.
func NewWithConfig(me Metadata, cfg *Config) *Agent {
	return &Agent{
		metadata: me,
		cfg:      cfg,
	}
}

// Name returns the name of the custom agent. This is a programmatic friendly name.
func (a *Agent) Name() string {
	return a.metadata.Name
}

// RepoOwner returns the owner of the repository where the custom agent is defined.
func (a *Agent) RepoOwner() string {
	return a.metadata.RepoOwner
}

// RepoOwnerID returns the owner ID of the repository where the custom agent is defined.
func (a *Agent) RepoOwnerID() int64 {
	return a.metadata.RepoOwnerID
}

// RepoName returns the name of the repository where the custom agent is defined.
func (a *Agent) RepoName() string {
	return a.metadata.RepoName
}

// RepoID returns the ID of the repository where the custom agent is defined.
func (a *Agent) RepoID() int64 {
	return a.metadata.RepoID
}

// DisplayName returns the display name of the custom agent. This is a user-friendly name.
func (a *Agent) DisplayName() string {
	return a.cfg.attributes.DisplayName
}

// Description returns the description of the custom agent.
func (a *Agent) Description() string {
	return a.cfg.attributes.Description
}

// Prompt returns the prompt template used by the custom agent.
func (a *Agent) Prompt() string {
	return a.cfg.attributes.Prompt
}

// Tools returns the list of tools configured for this agent.
func (a *Agent) Tools() []string {
	return a.cfg.tools()
}

// Version of the agent configuration - will be the SHA of the config file in the repo.
func (a *Agent) Version() string {
	return a.metadata.Version
}

// Target product the agent is expected to work within. By default this is empty which means it works everywhere.
func (a *Agent) Target() string {
	return a.cfg.attributes.Target
}

// ConfigError returns the configuration error message for the agent, if any.
func (a *Agent) ConfigError() string {
	return a.metadata.ConfigError
}

// MCPConfig for an unprivileged agent should always be empty.
func (a *Agent) MCPConfig() mcpconfig.JSON {
	return mcpconfig.JSON{Servers: map[string]mcpconfig.Server{}}
}

// IsCopilot checks if the agent is the default Copilot agent.
func (a *Agent) IsCopilot() bool {
	// TODO: Technically this name could be used by a customer, so we should update how we identify the default agent.
	// We should also update the DBRecord.IsCopilot method to match this logic as it updates.
	return a.Name() == DefaultAgentName
}

// ToDB converts the Agent to its database representation. It uses a shared helper toDB function that PrivilegedAgent also uses.
// This ensures that both types are converted consistently rather than having to have separate implementations for each type.
func (a *Agent) ToDB() customagent.DBRecord {
	return toDB(a)
}

// MCPConfig returns the MCP configuration for a privileged agent.
func (a *PrivilegedAgent) MCPConfig() mcpconfig.JSON {
	return a.cfg.mcpConfig()
}

// ToDB converts the Agent to its database representation. It uses a shared helper toDB function that Agent also uses.
// This ensures that both types are converted consistently rather than having to have separate implementations for each type.
func (a *PrivilegedAgent) ToDB() customagent.DBRecord {
	return toDB(a)
}

func toDB(a sweagentd.CustomAgent) customagent.DBRecord {
	return customagent.DBRecord{
		Name:        a.Name(),
		RepoOwnerID: a.RepoOwnerID(),
		RepoOwner:   a.RepoOwner(),
		RepoID:      a.RepoID(),
		RepoName:    a.RepoName(),
		Version:     a.Version(),
		DisplayName: a.DisplayName(),
		Description: a.Description(),
		Prompt:      a.Prompt(),
		Tools:       a.Tools(),
		MCPServers:  mcpToDB(a.MCPConfig()),
		Target:      a.Target(),
		// We are storing parsing errors on the job to aid in triage and include the
		// option for it to be processed when only the MCP portion of the config failed.
		ConfigError: a.ConfigError(),
	}
}

// FromDB converts a DBRecord representation to an Agent instance.
func FromDB(db customagent.DBRecord) sweagentd.CustomAgent {
	// Adapt to legacy data by ensuring defaults are always applied
	if db.Name == "" || db.Name == DefaultAgentName {
		return Copilot(db.RepoOwnerID, db.RepoID, db.RepoOwner, db.RepoName)
	}
	if db.Tools == nil {
		// We see nil tools in the DB despite the fact that the field is non-nullable
		// likely because it was nullable at one point, so handle that.
		db.Tools = []string{"*"}
	}

	agent := &Agent{
		metadata: Metadata{
			Name:        db.Name,
			RepoOwnerID: db.RepoOwnerID,
			RepoOwner:   db.RepoOwner,
			RepoID:      db.RepoID,
			RepoName:    db.RepoName,
			Version:     db.Version,
			ConfigError: db.ConfigError,
		},
		cfg: &Config{
			attributes: ConfigAttributes{
				DisplayName: db.DisplayName,
				Description: db.Description,
				Prompt:      db.Prompt,
				Tools:       db.Tools,
				MCPConfig:   mcpFromDB(db.MCPServers),
				Target:      db.Target,
			},
		},
	}

	// Assume if MCP config is specified, it's a privileged agent
	if len(db.MCPServers) > 0 {
		return &PrivilegedAgent{agent}
	}

	return agent
}

func mcpToDB(config mcpconfig.JSON) []customagent.MCPServer {
	var out []customagent.MCPServer
	for name, server := range config.Servers {
		switch {
		case mcpconfig.IsLocal(server.Type):
			out = append(out, customagent.MCPServer{
				Name:    name,
				Type:    server.Type,
				Tools:   server.Tools,
				Command: server.Command,
				Args:    server.Args,
				Env:     server.Env,
			})

		case mcpconfig.IsRemote(server.Type):
			out = append(out, customagent.MCPServer{
				Name:    name,
				Type:    server.Type,
				Tools:   server.Tools,
				URL:     server.URL,
				Headers: server.Headers,
			})

		default:
			continue // TODO(josebalius): should this fail?
		}
	}

	return out
}

func mcpFromDB(dbServers []customagent.MCPServer) mcpconfig.JSON {
	out := mcpconfig.JSON{
		Servers: make(map[string]mcpconfig.Server),
	}
	for _, dbServer := range dbServers {
		out.Servers[dbServer.Name] = makeMCPServer(dbServer)
	}

	return out
}

func makeMCPServer(dbServer customagent.MCPServer) mcpconfig.Server {
	server := mcpconfig.Server{
		Type:  dbServer.Type,
		Tools: dbServer.Tools,
	}

	switch {
	case mcpconfig.IsLocal(dbServer.Type):
		server.Local = &mcpconfig.Local{
			Command: dbServer.Command,
			Args:    dbServer.Args,
			Env:     dbServer.Env,
		}

	case mcpconfig.IsRemote(dbServer.Type):
		server.Remote = &mcpconfig.Remote{
			URL:     dbServer.URL,
			Headers: dbServer.Headers,
		}

	default:
		// TODO(josebalius): should this fail?
	}

	return server
}
