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
	Scope       string // Scope indicates where the agent originates: "repo", "org", "enterprise", or "job"
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

// ArgumentHint returns the argument hint for the custom agent.
func (a *Agent) ArgumentHint() string {
	return a.cfg.attributes.ArgumentHint
}

// Metadata returns the metadata attributes for the custom agent.
func (a *Agent) Metadata() map[string]string {
	return a.cfg.attributes.Metadata
}

// InferenceEnabled indicates whether inference (i.e being selected as a tool) is enabled for the custom agent.
func (a *Agent) InferenceEnabled() bool {
	return a.cfg.attributes.InferenceEnabled
}

// Model returns the model specified for the custom agent.
// This property is passed through for VS Code compatibility today.
func (a *Agent) Model() string {
	return a.cfg.attributes.Model
}

// Handoffs returns the handoff configuration for the custom agent.
// This property is passed through for VS Code compatibility today.
func (a *Agent) Handoffs() []sweagentd.CustomAgentHandoff {
	return a.cfg.attributes.Handoffs
}

// Triggers returns the events configured for the custom agent.
func (a *Agent) Triggers() sweagentd.CustomAgentTriggers {
	return a.cfg.attributes.Triggers
}

// Permissions returns the permissions configured for the agent, but are not configurable for a standard agent.
func (a *Agent) Permissions() map[string]string {
	return DefaultPermissions
}

// Scope returns the origin scope of the agent: "repo", "org", "enterprise", or "job".
// Empty string is treated as "repo" for backward compatibility.
func (a *Agent) Scope() string {
	if a.metadata.Scope == "" {
		return customagent.ScopeRepo
	}
	return a.metadata.Scope
}

// ToDB converts the Agent to its database representation.
func (a *Agent) ToDB() customagent.DBRecord {
	return toDB(a)
}

// NewJobScopedAgent creates a new job-scoped PrivilegedAgent with the provided metadata and configuration.
// Job-scoped agents have their prompt and permissions passed via the Twirp API rather than loaded from a repository.
func NewJobScopedAgent(me Metadata, cfg *Config) *PrivilegedAgent {
	me.Scope = customagent.ScopeJob
	return &PrivilegedAgent{NewWithConfig(me, cfg)}
}

// MCPConfig returns the MCP configuration for a privileged agent.
func (a *PrivilegedAgent) MCPConfig() mcpconfig.JSON {
	return a.cfg.mcpConfig()
}

// Permissions returns the permissions configured for the privileged agent.
func (a *PrivilegedAgent) Permissions() map[string]string {
	return a.cfg.attributes.Permissions
}

// ToDB converts the PrivilegedAgent to its database representation.
// For job-scoped agents, Prompt and Permissions are stored on the record.
func (a *PrivilegedAgent) ToDB() customagent.DBRecord {
	record := toDB(a)
	// For job-scoped agents, store prompt and permissions directly
	if a.Scope() == customagent.ScopeJob {
		record.Prompt = a.Prompt()
		record.Permissions = a.Permissions()
	}
	return record
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
		Tools:       a.Tools(),
		MCPServers:  mcpToDB(a.MCPConfig()),
		Target:      a.Target(),
		Metadata:    a.Metadata(),
		Scope:       a.Scope(),
		// We are storing parsing errors on the job to aid in triage and include the
		// option for it to be processed when only the MCP portion of the config failed.
		ConfigError:      a.ConfigError(),
		InferenceEnabled: a.InferenceEnabled(),

		// Prompt and Permissions are only stored for job-scoped agents (handled in PrivilegedAgent.ToDB)
		// Triggers need to be stored elsewhere since they are used to determine when a job is created.
	}
}

// FromDB is the legacy implementation that converts a DBRecord representation to an Agent instance.
//
// Use customagent.Service.FromDB instead.
//
// TODO (chuxel): Drop this function once CopilotSWEAgentCustomAgentPermissions feature flag is fully rolled out.
//
//nolint:gocritic // hugeParam: db is a large struct but passed by value intentionally for DB record conversion
func FromDB(db customagent.DBRecord) sweagentd.CustomAgent {
	// TODO: remove "copilot" portion after this lands in prod to not break jobs currently enqueued when this merges. Going forward db.Name for default agent will be "".
	if db.Name == "" || db.Name == DefaultAgentName {
		return Copilot(db.RepoOwnerID, db.RepoID, db.RepoOwner, db.RepoName)
	}
	if db.Tools == nil {
		// We see nil tools in the DB despite the fact that the field is non-nullable
		// likely because it was nullable at one point, so handle that.
		db.Tools = []string{"*"}
	}

	// Determine scope - default to repo for backward compatibility
	scope := db.Scope
	if scope == "" {
		scope = customagent.ScopeRepo
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
			Scope:       scope,
		},
		cfg: &Config{
			attributes: ConfigAttributes{
				DisplayName:      db.DisplayName,
				Description:      db.Description,
				Tools:            db.Tools,
				MCPConfig:        mcpFromDB(db.MCPServers),
				Target:           db.Target,
				Metadata:         db.Metadata,
				InferenceEnabled: db.InferenceEnabled,
			},
		},
	}

	// For job-scoped agents, also load prompt and permissions from the record
	if scope == customagent.ScopeJob {
		agent.cfg.attributes.Prompt = db.Prompt
		agent.cfg.attributes.Permissions = db.Permissions
		return &PrivilegedAgent{agent}
	}

	// For other scopes, assume if MCP config is specified, it's a privileged agent
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
