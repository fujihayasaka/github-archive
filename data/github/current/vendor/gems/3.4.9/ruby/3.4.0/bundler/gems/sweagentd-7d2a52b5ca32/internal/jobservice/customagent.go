package jobservice

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

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
}

// GetCustomAgent retrieves a custom agent based on the provided parameters.
// If no specific custom agent configuration is provided, it defaults to the copilot agent.
func (s *Service) GetCustomAgent(ctx context.Context, params GetCustomAgentParams) (sweagentd.CustomAgent, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.GetCustomAgent")
	defer span.End()

	logger := s.obsv.Logger.WithContext(ctx).Named("jobservice.GetCustomAgent")

	var agent sweagentd.CustomAgent = customagent.Copilot(params.GHRepo.Owner.GetID(), params.GHRepo.GetID(), params.GHRepo.Owner.GetLogin(), params.GHRepo.GetName())

	// Tests pass in a nil GHClient, so we need to handle that case.nil for the customagent service so we need to check that here as well.
	useCustomAgents := s.customAgentSvc.IsEnabledForRepo(ctx, params.UserID, params.GHRepo.Owner.GetID(), params.GHRepo.GetID())
	if !useCustomAgents {
		logger.Info("custom agents feature flag disabled, using default copilot agent")
		return agent, nil
	}

	switch {
	case params.Name != "":
		logger.WithFields(kvp.String("name", params.Name)).Info("loading custom agent by name")

		a, err := s.customAgentSvc.ResolveByName(
			ctx,
			uint64(params.UserID),
			params.GHRepo.Owner.GetLogin(),
			params.GHRepo.GetName(),
			params.Name,
			params.Version,
			false,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve custom agent by name %s: %w", params.Name, err)
		}

		agent = a

	case params.Attributes != nil:
		// This is not a user facing flow, it's just for testing purposes right now so its gated behind a staffshipped FF
		if !s.ffs.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentCustomAgentAsAPI, params.UserID) {
			break
		}
		logger.Info("using custom agent from attributes")

		m := customagent.Metadata{
			Name:        "custom", // TODO(josebalius): is this the right name?
			RepoOwner:   params.GHRepo.Owner.GetLogin(),
			RepoOwnerID: params.GHRepo.Owner.GetID(),
			RepoName:    params.GHRepo.GetName(),
			RepoID:      params.GHRepo.GetID(),
			Version:     params.Version,
		}
		attrs := customagent.ConfigAttributes{
			DisplayName: params.Attributes.DisplayName,
			Description: params.Attributes.Description,
			Prompt:      params.Attributes.Prompt,
			Tools:       params.Attributes.Tools,
		}
		agent = customagent.NewWithConfig(m, customagent.NewConfigWithAttributes(attrs))

	default:
		// No specific custom agent configuration provided
	}

	logger.WithFields(kvp.String("name", agent.Name())).Info("using custom agent configuration")

	return agent, nil
}
