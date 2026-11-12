package agenthttp

import (
	"encoding/json"
	"strings"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/mcp"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/skills"
	"github.com/github/sweagentd/internal/sweagentd"
)

// defaultMCPProxyURL is the default URL of the MCP proxy server that runs
// alongside engines on the Actions runner. The proxy is started by the
// workflow before the engine and bridges user-provided MCP servers.
const defaultMCPProxyURL = "http://127.0.0.1:2301"

// jobDTO represents the agent configuration and the work unit that the agent will execute.
type jobDTO struct {
	ID                             string
	ProblemStatement               problemStatementDTO `json:"problem_statement"`
	IsTrigger                      bool                `json:"is_trigger,omitempty"`
	CustomAgent                    customAgentDTO      `json:"custom_agent"`
	AvailableCustomAgents          []customAgentDTO    `json:"available_custom_agents,omitempty"`
	AvailableSkills                []skills.SkillDTO   `json:"available_skills,omitempty"`
	PluginRepos                    []plugins.PluginDTO `json:"plugins,omitempty"`
	OrganizationCustomInstructions string              `json:"organization_custom_instructions,omitempty"`
	Action                         string              `json:"action"`
	Repository                     string              `json:"repository"`
	ServerURL                      string              `json:"server_url"`
	BranchName                     string              `json:"branch_name,omitempty"`
	CommitLogin                    string              `json:"commit_login"`
	CommitEmail                    string              `json:"commit_email"`
	MCPProxyURL                    string              `json:"mcp_proxy_url"`
	EventType                      string              `json:"event_type,omitempty"`
	EventURL                       string              `json:"event_url,omitempty"`
	EventIdentifiers               []string            `json:"event_identifiers,omitempty"`
	CAPISessionToken               string              `json:"capi_session_token,omitempty"`
	AutoModeModel                  string              `json:"auto_mode_model,omitempty"`
	AgenticApp                     *agenticAppDTO      `json:"agentic_app,omitempty"`

	// Model selection fields for engines that support dynamic model selection.
	Features        *jobFeaturesDTO `json:"features,omitempty"`
	SelectedModel   string          `json:"selected_model,omitempty"`
	DefaultModel    string          `json:"default_model,omitempty"`
	AvailableModels []string        `json:"available_models,omitempty"`
	ModelVendors    []string        `json:"model_vendors,omitempty"`
}

// jobFeaturesDTO represents feature flags for the job.
type jobFeaturesDTO struct {
	ModelSelection bool `json:"model_selection,omitempty"`
}

type agenticAppDTO struct {
	Metadata map[string]string `json:"metadata,omitempty"`
}

type problemStatementDTO struct {
	Content string `json:"content"`
}

// customAgentDTO is currently the same as customagent.customAgentDTO, but keeping separate in case we want to diverge later
type customAgentDTO struct {
	Name                   string                         `json:"name"`
	RepoOwnerID            int64                          `json:"repo_owner_id"`
	RepoOwner              string                         `json:"repo_owner"`
	RepoID                 int64                          `json:"repo_id"`
	RepoName               string                         `json:"repo_name"`
	DisplayName            string                         `json:"display_name"`
	Description            string                         `json:"description"`
	Prompt                 string                         `json:"prompt,omitempty"`
	Tools                  []string                       `json:"tools"`
	Version                string                         `json:"version"`
	MCPServers             map[string]mcpconfig.Server    `json:"mcp_servers,omitempty"`
	InferenceEnabled       bool                           `json:"infer"`                    // TODO: deprecate this field in favor of DisableModelInvocation in a follow up PR, runtime looks for this today so can't do it in one PR
	DisableModelInvocation bool                           `json:"disable_model_invocation"` // New field to replace InferenceEnabled
	UserInvocable          bool                           `json:"user_invocable"`
	Model                  string                         `json:"model,omitempty"`
	Handoffs               []sweagentd.CustomAgentHandoff `json:"handoffs,omitempty"`
	GitHub                 *customAgentGitHubDTO          `json:"github,omitempty"`
	Skills                 []string                       `json:"skills,omitempty"`
	// We are intentionally excluding Target and ConfigError since we
	// will not send something to the runtime that it cannot process.
	// ArgumentHint and Metadata are also currently omitted since they are
	// not intended to affect how the runtime processes a job request.
}

// customAgentGitHubDTO groups GitHub-specific agent properties.
type customAgentGitHubDTO struct {
	Permissions map[string]string `json:"permissions,omitempty"`
	Toolsets    []string          `json:"toolsets,omitempty"`
}

func makeCustomAgentDTO(agent sweagentd.CustomAgent, includePrompt bool) customAgentDTO {
	var mcpServers map[string]mcpconfig.Server
	if p, ok := agent.(mcp.ConfigProvider); ok {
		mcpServers = p.MCPConfig().Servers
	}

	var perms map[string]string
	if p, ok := agent.(permissions.Provider); ok {
		perms = p.Permissions().ToMap()
	}

	dto := customAgentDTO{
		Name:                   agent.Name(),
		RepoOwnerID:            agent.RepoOwnerID(),
		RepoOwner:              agent.RepoOwner(),
		RepoID:                 agent.RepoID(),
		RepoName:               agent.RepoName(),
		DisplayName:            agent.DisplayName(),
		Description:            agent.Description(),
		Tools:                  agent.Tools(),
		Version:                agent.Version(),
		MCPServers:             mcpServers,
		InferenceEnabled:       agent.InferenceEnabled(),
		DisableModelInvocation: agent.DisableModelInvocation(),
		UserInvocable:          agent.UserInvocable(),
		Model:                  agent.Model(),
		Handoffs:               agent.Handoffs(),
		Skills:                 agent.Skills(),
	}

	toolsets := agent.GitHubMCPToolsets()
	if len(perms) > 0 || len(toolsets) > 0 {
		dto.GitHub = &customAgentGitHubDTO{
			Permissions: perms,
			Toolsets:    toolsets,
		}
	}

	if includePrompt {
		dto.Prompt = agent.Prompt()
	}

	return dto
}

// jobExtraFields carries values resolved outside the job domain model
// (e.g., from service config or the agentic app).
type jobExtraFields struct {
	ServerURL   string
	CommitLogin string
	CommitEmail string
	AgenticApp  map[string]string
}

// stripCAPIModelPrefix removes the "sweagent-capi:" prefix from model IDs.
// Engine consumers should see plain model IDs without the internal prefix.
func stripCAPIModelPrefix(model string) string {
	return strings.TrimPrefix(model, jobs.CapiModelPrefix)
}

// stripCAPIModelPrefixes removes the "sweagent-capi:" prefix from each model ID in the slice.
func stripCAPIModelPrefixes(models []string) []string {
	if len(models) == 0 {
		return models
	}
	out := make([]string, len(models))
	for i, m := range models {
		out[i] = stripCAPIModelPrefix(m)
	}
	return out
}

// jobDTOFromDomain converts a [jobs.Job] and list of [sweagentd.CustomAgent] domain models to a JobDTO.
func jobDTOFromDomain(job *jobs.Job, agent sweagentd.CustomAgent, availableCustomAgents []sweagentd.CustomAgent, availableSkills []*skills.Skill, pluginRepos []plugins.PluginDTO, organizationCustomInstructions string, extra jobExtraFields) *jobDTO {
	availableCustomAgentDTOs := make([]customAgentDTO, 0, len(availableCustomAgents))
	for _, sa := range availableCustomAgents {
		dto := makeCustomAgentDTO(sa, false)
		availableCustomAgentDTOs = append(availableCustomAgentDTOs, dto)
	}

	availableSkillDTOs := make([]skills.SkillDTO, 0, len(availableSkills))
	for _, sk := range availableSkills {
		dto := skills.MakeSkillDTO(sk, false)
		availableSkillDTOs = append(availableSkillDTOs, dto)
	}

	customAgentDTO := makeCustomAgentDTO(agent, true)

	// Prefer Args.GitHubRepo; fall back to owner/name for older job records.
	repo := job.Args.GitHubRepo
	if repo == "" && job.Args.GitHubRepoOwner != "" && job.Args.GitHubRepoName != "" {
		repo = job.Args.GitHubRepoOwner + "/" + job.Args.GitHubRepoName
	}

	dto := &jobDTO{
		ID: job.ID,
		ProblemStatement: problemStatementDTO{
			Content: job.ProblemStatement.Content,
		},
		IsTrigger:                      job.IsTriggered,
		CustomAgent:                    customAgentDTO,
		AvailableCustomAgents:          availableCustomAgentDTOs,
		AvailableSkills:                availableSkillDTOs,
		PluginRepos:                    pluginRepos,
		OrganizationCustomInstructions: organizationCustomInstructions,
		Action:                         string(job.Action),
		Repository:                     repo,
		ServerURL:                      extra.ServerURL,
		BranchName:                     job.BranchName,
		CommitLogin:                    extra.CommitLogin,
		CommitEmail:                    extra.CommitEmail,
		MCPProxyURL:                    defaultMCPProxyURL,
		EventType:                      string(job.EventType),
		EventURL:                       job.EventURL,
		EventIdentifiers:               job.EventIdentifiers,
		AgenticApp:                     newAgenticAppDTO(extra.AgenticApp),
	}

	// Populate model selection fields when the job has model selection info.
	if ms := job.ModelSelection; ms != nil && ms.Enabled {
		dto.Features = &jobFeaturesDTO{ModelSelection: true}
		dto.SelectedModel = stripCAPIModelPrefix(job.Model)
		dto.DefaultModel = stripCAPIModelPrefix(ms.DefaultModel)
		dto.AvailableModels = stripCAPIModelPrefixes(ms.AvailableModels)
		dto.ModelVendors = ms.Vendors
	}

	return dto
}

func newAgenticAppDTO(metadata map[string]string) *agenticAppDTO {
	if len(metadata) == 0 {
		return nil
	}
	return &agenticAppDTO{Metadata: metadata}
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

// createPullRequestRequestDTO represents the request body for creating a pull request.
type createPullRequestRequestDTO struct {
	Title       string `json:"title"`
	Description string `json:"description"`
}

// createPullRequestResponseDTO represents the response body for creating a pull request.
type createPullRequestResponseDTO struct {
	ID           int64 `json:"id"`
	GithubNumber int   `json:"github_number"`
}

// tokensRequestDTO is the request body for the POST /agent/jobs/{jobID}/tokens endpoint.
type tokensRequestDTO struct {
	SecretNames []string `json:"secret_names"`
	// MCPServerNames is an alternative to SecretNames for MCP inline OIDC entries.
	// The runtime passes the raw MCP server name and the backend resolves the
	// corresponding OIDC config entry. Tokens are returned in MCPServerTokens keyed by
	// server name.
	MCPServerNames []string `json:"mcp_server_names,omitempty"`
	// AgentName is the name of a dynamically-selected custom agent whose MCP
	// servers may declare inline OIDC entries. When set, the sweagentd resolves
	// this agent instead of relying on the job's stored CustomAgent record.
	AgentName string `json:"agent_name,omitempty"`
	// AgentVersion is the version of the agent to process. When set, the sweagentd
	// resolves this version instead of what is on the default branch.
	AgentVersion string `json:"agent_version,omitempty"`
}

// tokensResponseDTO is the response body for the POST /agent/jobs/{jobID}/tokens endpoint.
type tokensResponseDTO struct {
	// Tokens contains tokens keyed by their full secret name (e.g.
	// GITHUB_COPILOT_OIDC_MY_API) for entries resolved via secret_names.
	SecretTokens map[string]string `json:"secret_tokens"`
	// MCPTokens contains tokens keyed by MCP server name for entries resolved
	// via mcp_server_names. Omitted when no MCP server names were requested.
	MCPServerTokens map[string]string `json:"mcp_server_tokens,omitempty"`
	// Failures contains per-entry exchange failures. Omitted when all entries
	// exchanged successfully.
	Failures []tokenFailureDTO `json:"failures,omitempty"`
	// Warnings contains per-entry exchange warnings. Omitted when no warnings.
	Warnings []tokenWarningDTO `json:"warnings,omitempty"`
}

// tokenFailureDTO describes a single token exchange failure for a secret or
// MCP server entry.
type tokenFailureDTO struct {
	// ResponseCode is the HTTP status code that best describes this failure
	// (e.g. 500 for internal errors, 401 for authorization_required).
	ResponseCode int `json:"response_code"`
	// Message is a human-readable description of what went wrong.
	Message string `json:"message"`
	// Error is an optional implementation-defined error string for diagnostics.
	// Clients should not treat it as a stable programmatic error code.
	Error string `json:"error,omitempty"`
	// FailureURL is the integrator-configured failure endpoint, if any.
	FailureURL string `json:"failure_url,omitempty"`
	// SecretName is the full secret name for entries resolved via secret_names.
	SecretName string `json:"secret_name,omitempty"`
	// ServerName is the MCP server name for entries resolved via mcp_server_names.
	ServerName string `json:"server_name,omitempty"`
}

// tokenWarningDTO describes a single token exchange warning for a secret or MCP server entry.
type tokenWarningDTO struct {
	// Message is a human-readable description of the warning.
	Message string `json:"message"`
}

// downloadAttachmentResponseDTO is the response body for the GET
// /agent/jobs/{jobID}/attachments/{guid} endpoint.
type downloadAttachmentResponseDTO struct {
	URL string `json:"url"`
}
