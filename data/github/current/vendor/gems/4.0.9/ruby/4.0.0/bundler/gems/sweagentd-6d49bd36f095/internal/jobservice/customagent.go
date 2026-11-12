package jobservice

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/permissions"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// ErrAgentNotUserInvocable is returned when a user attempts to select a custom
// agent that has user-invocable set to false in its configuration.
var ErrAgentNotUserInvocable = goerrors.New("custom agent is not user-invocable")

// GetCustomAgentParams holds parameters for the GetCustomAgent function.
type GetCustomAgentParams struct {
	// UserID is the ID of the user requesting the custom agent.
	UserID int64

	// GHClient is a GitHub client authenticated as the user.
	// Must have access to the repository.
	GHClient github.ClientInterface

	// GHRepo is the GitHub repository associated with the custom agent.
	GHRepo *gg.Repository

	// Name is the name of the custom agent to fetch. If empty, default copilot agent is used.
	// If both Name and Attributes are provided, Name takes precedence.
	Name string

	// Version is the version of the custom agent to fetch. Leave empty for latest.
	// This is currently a git SHA. In the future we can mimic Actions and support tag/branch references as well.
	Version string

	// Attributes are custom attributes for creating a custom agent. If both Name and Attributes
	// are provided, Name takes precedence.
	Attributes *GetCustomAgentParamsAttributes
}

// GetCustomAgentParamsAttributes holds custom attributes for creating a custom agent.
type GetCustomAgentParamsAttributes struct {
	// DisplayName is the display name of the custom agent.
	DisplayName string

	// Description is a brief description of the custom agent.
	// This is used in the prompt to provide context about the agent's purpose.
	Description string

	// Prompt is the base prompt for the custom agent.
	Prompt string

	// Tools is a list of tool names that the custom agent can use.
	Tools []string

	// Permissions is a map of permission names to their access levels.
	Permissions map[string]string

	// GitHubMCPToolsets configures which toolsets are enabled on the built-in GitHub MCP server.
	GitHubMCPToolsets []string

	// MCPServers contains the MCP server configuration.
	// This field is only available through the internal Twirp API, not the public Jobs API.
	MCPServers mcpconfig.JSON

	// Skills is the list of skill names to preload into this agent's context.
	Skills []string
}

// GetCustomAgent retrieves a custom agent based on the provided parameters.
// If no specific custom agent configuration is provided, it defaults to the copilot agent.
func (s *Service) GetCustomAgent(ctx context.Context, params GetCustomAgentParams) (sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetCustomAgent")
	defer span.End()

	logger := s.obsv.Logger.WithContext(ctx).Named("jobservice.GetCustomAgent")

	var agent sweagentd.CustomAgent = customagent.Copilot(params.GHRepo.Owner.GetID(), params.GHRepo.GetID(), params.GHRepo.Owner.GetLogin(), params.GHRepo.GetName())

	// Tests pass in a nil GHClient for the customagent service, so we need to handle that case.
	useCustomAgents := s.customAgentSvc.IsEnabledForRepo(ctx, params.UserID, params.GHRepo.Owner.GetID(), params.GHRepo.GetID())
	if !useCustomAgents {
		logger.Info("custom agents feature flag disabled, using default copilot agent")
		return agent, nil
	}

	switch {
	// Check if custom attributes were provided and assume this is a job-scoped agent if so
	case params.Attributes != nil:
		if !s.ffs.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentCustomAgentAsAPI, params.UserID) {
			break
		}
		// This flow is only supported through the Twirp API for internal integrators. The public Job API does not allow for Custom Agent Attributes to be specified.
		logger.Info("using job-scoped custom agent from attributes")

		if params.Name == "" {
			logger.Warn("name is required for job-scoped agents, using default")
			params.Name = "job-agent"
		}

		m := customagent.Metadata{
			Name:        params.Name,
			RepoOwner:   params.GHRepo.Owner.GetLogin(),
			RepoOwnerID: params.GHRepo.Owner.GetID(),
			RepoName:    params.GHRepo.GetName(),
			RepoID:      params.GHRepo.GetID(),
			Version:     params.Version,
		}
		attrs := customagent.ConfigAttributes{
			DisplayName:       params.Attributes.DisplayName,
			Description:       params.Attributes.Description,
			Prompt:            params.Attributes.Prompt,
			Tools:             params.Attributes.Tools,
			Permissions:       permissions.New(params.Attributes.Permissions),
			GitHubMCPToolsets: params.Attributes.GitHubMCPToolsets,
			MCPConfig:         params.Attributes.MCPServers,
			Skills:            params.Attributes.Skills,
		}
		agent = customagent.NewJobScopedAgent(m, customagent.NewConfigWithAttributes(attrs))

	// Check if a specific custom agent name was provided, and load that if so
	case params.Name != "":
		logger.WithFields(kvp.String("name", params.Name)).Info("loading custom agent by name")

		a, err := s.customAgentSvc.ResolveByNameAndRepoID(
			ctx,
			uint64(params.GHRepo.GetID()),
			params.Name,
			params.Version,
			customagent.ResolveByNameOpts{
				UserID:               uint64(params.UserID),
				ErrorOnInvalidConfig: false,
			},
		)
		if err != nil {
			return nil, goerrors.Errorf("failed to resolve custom agent by name %s: %w", params.Name, err)
		}

		// params.Name is only provided in use cases under the control of the user. Ideally the UI should have filtered out
		// all custom agents with `user-invocable: false` but this is an additional safeguard in case outdated UI allows them to submit such a request.
		if !a.UserInvocable() {
			logger.WithFields(kvp.String("name", params.Name)).Warn("custom agent is not user-invocable")
			return nil, ErrAgentNotUserInvocable
		}

		agent = a

	default:
		logger.Info("no custom agent configuration provided, using default copilot agent")
	}

	logger.WithFields(kvp.String("name", agent.Name())).Info("resolved agent")

	return agent, nil
}
