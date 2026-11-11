package agenthttp

import (
	"encoding/json"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/sweagentd"
)

// jobDTO represents the agent configuration and the work unit that the agent will execute.
type jobDTO struct {
	ID                             string
	ProblemStatement               problemStatementDTO `json:"problem_statement"`
	CustomAgent                    customAgentDTO      `json:"custom_agent"`
	AvailableCustomAgents          []customAgentDTO    `json:"available_custom_agents,omitempty"`
	OrganizationCustomInstructions string              `json:"organization_custom_instructions,omitempty"`
}

type problemStatementDTO struct {
	Content string `json:"content"`
}

// customAgentDTO is currently the same as customagent.customAgentDTO, but keeping separate in case we want to diverge later
type customAgentDTO struct {
	Name             string                         `json:"name"`
	RepoOwnerID      int64                          `json:"repo_owner_id"`
	RepoOwner        string                         `json:"repo_owner"`
	RepoID           int64                          `json:"repo_id"`
	RepoName         string                         `json:"repo_name"`
	DisplayName      string                         `json:"display_name"`
	Description      string                         `json:"description"`
	Prompt           string                         `json:"prompt,omitempty"`
	Tools            []string                       `json:"tools"`
	Version          string                         `json:"version"`
	MCPServers       map[string]mcpconfig.Server    `json:"mcp_servers,omitempty"`
	InferenceEnabled bool                           `json:"infer"`
	Model            string                         `json:"model,omitempty"`
	Handoffs         []sweagentd.CustomAgentHandoff `json:"handoffs,omitempty"`
	// We are intentionally excluding Target and ConfigError since we
	// will not send something to the runtime that it cannot process.
	// ArgumentHint, Metadata, Permissions, and Events (on) are also
	// currently omitted since they are not intended to affect how the
	// runtime processes a job request.
}

func makeCustomAgentDTO(agent sweagentd.CustomAgent, includePrompt bool) customAgentDTO {
	dto := customAgentDTO{
		Name:             agent.Name(),
		RepoOwnerID:      agent.RepoOwnerID(),
		RepoOwner:        agent.RepoOwner(),
		RepoID:           agent.RepoID(),
		RepoName:         agent.RepoName(),
		DisplayName:      agent.DisplayName(),
		Description:      agent.Description(),
		Tools:            agent.Tools(),
		Version:          agent.Version(),
		MCPServers:       agent.MCPConfig().Servers,
		InferenceEnabled: agent.InferenceEnabled(),
		Model:            agent.Model(),
		Handoffs:         agent.Handoffs(),
	}

	if includePrompt {
		dto.Prompt = agent.Prompt()
	}

	return dto
}

// jobDTOFromDomain converts a [jobs.Job] and list of [sweagentd.CustomAgent] domain models to a JobDTO.
func jobDTOFromDomain(job *jobs.Job, agent sweagentd.CustomAgent, availableCustomAgents []sweagentd.CustomAgent, organizationCustomInstructions string) *jobDTO {
	availableCustomAgentDTOs := make([]customAgentDTO, 0, len(availableCustomAgents))
	for _, sa := range availableCustomAgents {
		dto := makeCustomAgentDTO(sa, false)
		availableCustomAgentDTOs = append(availableCustomAgentDTOs, dto)
	}

	customAgentDTO := makeCustomAgentDTO(agent, true)

	return &jobDTO{
		ID: job.ID,
		ProblemStatement: problemStatementDTO{
			Content: job.ProblemStatement.Content,
		},
		CustomAgent:                    customAgentDTO,
		AvailableCustomAgents:          availableCustomAgentDTOs,
		OrganizationCustomInstructions: organizationCustomInstructions,
	}
}

type newProgressDTO struct {
	Namespace string `json:"namespace"`
	Kind      string `json:"kind"`
	Version   int64  `json:"version"`
	Content   string `json:"content"`
}

type progressDTO struct {
	ID        string `json:"id"`
	Namespace string `json:"namespace"`
	Kind      string `json:"kind"`
	Version   int64  `json:"version"`
	Content   string `json:"content"`
	CreatedAt int64  `json:"created_at"`
}

func progressDTOFromDomain(p *progress.Progress) progressDTO {
	content := ""

	contentJSON, err := json.Marshal(p.Content)
	if err == nil {
		content = string(contentJSON)
	}

	return progressDTO{
		ID:        p.ID,
		Namespace: p.Namespace,
		Kind:      p.Kind,
		Version:   p.Version,
		Content:   content,
		CreatedAt: p.CreatedAt,
	}
}

type progressRequest struct {
	Items []newProgressDTO
}

func (pr *progressRequest) UnmarshalJSON(data []byte) error {
	// Try to unmarshal as array first
	var items []newProgressDTO
	err := json.Unmarshal(data, &items)
	if err == nil {
		pr.Items = items
		return nil
	}

	// If that fails, try single item
	var single newProgressDTO
	err = json.Unmarshal(data, &single)
	if err != nil {
		return err
	}

	pr.Items = []newProgressDTO{single}
	return nil
}
