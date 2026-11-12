package agenthttp

import (
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/sweagentd"
)

// jobDTO represents the agent configuration and the work unit that the agent will execute.
type jobDTO struct {
	ID                             string
	ProblemStatement               problemStatementDTO `json:"problem_statement"`
	CustomAgent                    customAgentDTO      `json:"custom_agent,omitempty"`
	AvailableCustomAgents          []customAgentDTO    `json:"available_custom_agents,omitempty"`
	OrganizationCustomInstructions string              `json:"organization_custom_instructions,omitempty"`
}

type problemStatementDTO struct {
	Content string `json:"content"`
}

// customAgentDTO is currently the same as customagent.customAgentDTO, but keeping separate in case we want to diverge later
type customAgentDTO struct {
	Name        string                      `json:"name"`
	RepoOwnerID int64                       `json:"repo_owner_id"`
	RepoOwner   string                      `json:"repo_owner"`
	RepoID      int64                       `json:"repo_id"`
	RepoName    string                      `json:"repo_name"`
	DisplayName string                      `json:"display_name"`
	Description string                      `json:"description"`
	Prompt      string                      `json:"prompt,omitempty"`
	Tools       []string                    `json:"tools"`
	Version     string                      `json:"version"`
	MCPServers  map[string]mcpconfig.Server `json:"mcp_servers,omitempty"`
	// We are intentionally excluding Target and ConfigError since we will
	// not send something to the runtime that it cannot process.
}

func makeCustomAgentDTO(agent sweagentd.CustomAgent, includePrompt bool) customAgentDTO {
	dto := customAgentDTO{
		Name:        agent.Name(),
		RepoOwnerID: agent.RepoOwnerID(),
		RepoOwner:   agent.RepoOwner(),
		RepoID:      agent.RepoID(),
		RepoName:    agent.RepoName(),
		DisplayName: agent.DisplayName(),
		Description: agent.Description(),
		Tools:       agent.Tools(),
		Version:     agent.Version(),
		MCPServers:  agent.MCPConfig().Servers,
	}

	if includePrompt {
		dto.Prompt = agent.Prompt()
	}

	return dto
}

// jobDTOFromDomain converts a [jobs.Job] and list of [sweagentd.CustomAgent] domain models to a JobDTO.
func jobDTOFromDomain(job *jobs.Job, availableCustomAgents []sweagentd.CustomAgent, organizationCustomInstructions string) *jobDTO {
	availableCustomAgentDTOs := make([]customAgentDTO, 0, len(availableCustomAgents))
	for _, sa := range availableCustomAgents {
		dto := makeCustomAgentDTO(sa, false)
		availableCustomAgentDTOs = append(availableCustomAgentDTOs, dto)
	}

	customAgent := customagent.FromDB(job.CustomAgent)
	cadto := makeCustomAgentDTO(customAgent, true)

	return &jobDTO{
		ID: job.ID,
		ProblemStatement: problemStatementDTO{
			Content: job.ProblemStatement.Content,
		},
		CustomAgent:                    cadto,
		AvailableCustomAgents:          availableCustomAgentDTOs,
		OrganizationCustomInstructions: organizationCustomInstructions,
	}
}
