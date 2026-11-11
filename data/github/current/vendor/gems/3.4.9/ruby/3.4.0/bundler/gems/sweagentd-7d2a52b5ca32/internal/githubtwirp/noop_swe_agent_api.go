package githubtwirp

import (
	"context"
	"fmt"

	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

type NoopSweagentdAPI struct {
	sweagentdTwirp.SweagentdAPI
	ConfigurationForRepositoryResponse      *sweagentdTwirp.ConfigurationForRepositoryResponse
	ConfigurationForRepositoryError         *error
	AuthorizeCustomAgentRepoForUserResponse *sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse
	MockMCPConfigurationForRepository       func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error)
	MockCreatePullRequest                   func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error)
	MockEnterpriseAgents                    func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error)
	MockResolveUserIDToDisplayLogin         func(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error)
	MockGetIssueById                        func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error)
	MockGetOrganizationCustomInstructions   func(ctx context.Context, req *sweagentdTwirp.GetOrganizationCustomInstructionsRequest) (*sweagentdTwirp.GetOrganizationCustomInstructionsResponse, error)
	MockAuthorizeCustomAgentRepoForUser     func(ctx context.Context, req *sweagentdTwirp.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse, error)
	MockIsBypassActor                       func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error)
}

// Ensure NoopClient implements ClientInterface
var _ sweagentdTwirp.SweagentdAPI = &NoopSweagentdAPI{}

func (n *NoopSweagentdAPI) ConfigurationForRepository(context.Context, *sweagentdTwirp.ConfigurationForRepositoryRequest) (*sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
	if n.ConfigurationForRepositoryError != nil {
		return nil, *n.ConfigurationForRepositoryError
	} else if n.ConfigurationForRepositoryResponse != nil {
		return n.ConfigurationForRepositoryResponse, nil
	} else {
		return &sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		}, nil
	}
}

func (n *NoopSweagentdAPI) MCPConfigurationForRepository(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error) {
	if n.MockMCPConfigurationForRepository != nil {
		return n.MockMCPConfigurationForRepository(ctx, req)
	}

	panic("MCPConfigurationForRepository not implemented, provide a Mock method")
}

func (n *NoopSweagentdAPI) CreatePullRequest(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error) {
	if n.MockCreatePullRequest != nil {
		return n.MockCreatePullRequest(ctx, req)
	}
	return &sweagentdTwirp.CreatePullRequestResponse{
		PullRequest: &sweagentdTwirp.PullRequest{
			Id:           123,
			GithubNumber: 789,
			RepositoryId: 456,
		},
	}, nil
}

func (n *NoopSweagentdAPI) MintUserToServerTokenForRepo(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error) {
	return &sweagentdTwirp.MintUserToServerTokenForRepoResponse{
		Token: "mock-token",
	}, nil
}

func (n *NoopSweagentdAPI) EnterpriseAgents(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
	if n.MockEnterpriseAgents != nil {
		return n.MockEnterpriseAgents(ctx, req)
	}

	// Default mock response with the repository ID
	return &sweagentdTwirp.EnterpriseAgentsResponse{
		RepositoryId: req.RepositoryId,
	}, nil
}

func (n *NoopSweagentdAPI) ResolveUserIDToDisplayLogin(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error) {
	if n.MockResolveUserIDToDisplayLogin != nil {
		return n.MockResolveUserIDToDisplayLogin(ctx, req)
	}
	// Default behavior: return a display login different from the original login
	return &sweagentdTwirp.ResolveUserIDToDisplayLoginResponse{
		DisplayLogin: "display-login-" + fmt.Sprintf("%d", req.UserId),
	}, nil
}

func (n *NoopSweagentdAPI) GetOrganizationCustomInstructions(ctx context.Context, req *sweagentdTwirp.GetOrganizationCustomInstructionsRequest) (*sweagentdTwirp.GetOrganizationCustomInstructionsResponse, error) {
	if n.MockGetOrganizationCustomInstructions != nil {
		return n.MockGetOrganizationCustomInstructions(ctx, req)
	}
	// Return empty instructions for noop client by default
	return &sweagentdTwirp.GetOrganizationCustomInstructionsResponse{
		OrganizationCustomInstructions: "",
	}, nil
}

func (n *NoopSweagentdAPI) SetupMockResponseForResolveUserIDToDisplayLogin(id uint64, matchedResponse string, defaultResponse string) {
	n.MockResolveUserIDToDisplayLogin = func(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error) {
		// The test actor writer has a specific ID that we can match against
		if req.UserId == id {
			return &sweagentdTwirp.ResolveUserIDToDisplayLoginResponse{
				DisplayLogin: matchedResponse,
			}, nil
		}
		// For other users, return their original login
		return &sweagentdTwirp.ResolveUserIDToDisplayLoginResponse{
			DisplayLogin: defaultResponse,
		}, nil
	}
}

func (n *NoopSweagentdAPI) AuthorizeCustomAgentRepoForUser(ctx context.Context, req *sweagentdTwirp.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse, error) {
	if n.MockAuthorizeCustomAgentRepoForUser != nil {
		return n.MockAuthorizeCustomAgentRepoForUser(ctx, req)
	}

	if n.AuthorizeCustomAgentRepoForUserResponse != nil {
		return n.AuthorizeCustomAgentRepoForUserResponse, nil
	}
	// Default: allow access for testing
	return &sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse{
		CanAccess: true,
	}, nil
}

func (n *NoopSweagentdAPI) GetIssueById(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error) {
	if n.MockGetIssueById != nil {
		return n.MockGetIssueById(ctx, req)
	}
	// Default: return a basic issue for testing
	return &sweagentdTwirp.GetIssueByIdResponse{
		Issue: &sweagentdTwirp.Issue{
			Id:      req.IssueId,
			Number:  123,
			Body:    "Default test issue body",
			HtmlUrl: "https://github.com/test/repo/issues/123",
			Labels:  []string{},
		},
	}, nil
}

func (n *NoopSweagentdAPI) IsBypassActor(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
	if n.MockIsBypassActor != nil {
		return n.MockIsBypassActor(ctx, req)
	}
	// Default: return false (actor is not a bypass actor)
	return &sweagentdTwirp.IsBypassActorResponse{IsBypassActor: false}, nil
}
