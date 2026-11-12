package githubtwirp

import (
	"context"
	"fmt"

	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"google.golang.org/protobuf/types/known/emptypb"
)

type NoopSweagentdAPI struct {
	sweagentdTwirp.SweagentdAPI
	ConfigurationForRepositoryResponse        *sweagentdTwirp.ConfigurationForRepositoryResponse
	ConfigurationForRepositoryError           *error
	MockConfigurationForRepository            func(ctx context.Context, req *sweagentdTwirp.ConfigurationForRepositoryRequest) (*sweagentdTwirp.ConfigurationForRepositoryResponse, error)
	AuthorizeCustomAgentRepoForUserResponse   *sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse
	MockAuthorizeCustomAgentRepoForUser       func(ctx context.Context, req *sweagentdTwirp.AuthorizeCustomAgentRepoForUserRequest) (*sweagentdTwirp.AuthorizeCustomAgentRepoForUserResponse, error)
	MockCreatePullRequest                     func(ctx context.Context, req *sweagentdTwirp.CreatePullRequestRequest) (*sweagentdTwirp.CreatePullRequestResponse, error)
	MockEnterpriseAgents                      func(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error)
	MockGetAgenticApps                        func(ctx context.Context, req *sweagentdTwirp.GetAgenticAppsRequest) (*sweagentdTwirp.GetAgenticAppsResponse, error)
	MockGetIssueById                          func(ctx context.Context, req *sweagentdTwirp.GetIssueByIdRequest) (*sweagentdTwirp.GetIssueByIdResponse, error)
	MockGetOrganizationCCARunnerSettings      func(ctx context.Context, req *sweagentdTwirp.GetOrganizationCCARunnerSettingsRequest) (*sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse, error)
	MockGetOrganizationCustomInstructions     func(ctx context.Context, req *sweagentdTwirp.GetOrganizationCustomInstructionsRequest) (*sweagentdTwirp.GetOrganizationCustomInstructionsResponse, error)
	MockGetEffectiveTriggerActorPolicy        func(ctx context.Context, req *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error)
	MockIsBypassActor                         func(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error)
	MockMCPConfigurationForRepository         func(ctx context.Context, req *sweagentdTwirp.MCPConfigurationForRepositoryRequest) (*sweagentdTwirp.MCPConfigurationForRepositoryResponse, error)
	MockMintUserToServerTokenForRepo          func(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForRepoRequest) (*sweagentdTwirp.MintUserToServerTokenForRepoResponse, error)
	MockMintUserToServerTokenForRepos         func(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error)
	MockResolveUserIDToDisplayLogin           func(ctx context.Context, req *sweagentdTwirp.ResolveUserIDToDisplayLoginRequest) (*sweagentdTwirp.ResolveUserIDToDisplayLoginResponse, error)
	MockRevokeTokens                          func(ctx context.Context, req *sweagentdTwirp.RevokeTokensRequest) (*sweagentdTwirp.RevokeTokensResponse, error)
	MockMintServerToServerTokenForRepo        func(ctx context.Context, req *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error)
	MockMintServerToServerTokenForRepos       func(ctx context.Context, req *sweagentdTwirp.MintServerToServerTokenForReposRequest) (*sweagentdTwirp.MintServerToServerTokenForReposResponse, error)
	MockSignCommit                            func(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error)
	MockGetRepositoryInstallation             func(ctx context.Context, req *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error)
	MockIntegrationNeedsAuthorizationFromUser func(ctx context.Context, req *sweagentdTwirp.IntegrationNeedsAuthorizationFromUserRequest) (*sweagentdTwirp.IntegrationNeedsAuthorizationFromUserResponse, error)
	MockManagedSettingsRepository             func(ctx context.Context, req *sweagentdTwirp.ManagedSettingsRepositoryRequest) (*sweagentdTwirp.ManagedSettingsRepositoryResponse, error)
}

// Ensure NoopClient implements ClientInterface
var _ sweagentdTwirp.SweagentdAPI = &NoopSweagentdAPI{}

func (n *NoopSweagentdAPI) ConfigurationForRepository(ctx context.Context, req *sweagentdTwirp.ConfigurationForRepositoryRequest) (*sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
	if n.MockConfigurationForRepository != nil {
		return n.MockConfigurationForRepository(ctx, req)
	} else if n.ConfigurationForRepositoryError != nil {
		return nil, *n.ConfigurationForRepositoryError
	} else if n.ConfigurationForRepositoryResponse != nil {
		return n.ConfigurationForRepositoryResponse, nil
	} else {
		return &sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
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
	if n.MockMintUserToServerTokenForRepo != nil {
		return n.MockMintUserToServerTokenForRepo(ctx, req)
	}
	return &sweagentdTwirp.MintUserToServerTokenForRepoResponse{
		Token: "mock-token",
	}, nil
}

func (n *NoopSweagentdAPI) MintUserToServerTokenForRepos(ctx context.Context, req *sweagentdTwirp.MintUserToServerTokenForReposRequest) (*sweagentdTwirp.MintUserToServerTokenForReposResponse, error) {
	if n.MockMintUserToServerTokenForRepos != nil {
		return n.MockMintUserToServerTokenForRepos(ctx, req)
	}
	return &sweagentdTwirp.MintUserToServerTokenForReposResponse{
		Token: "mock-token",
	}, nil
}

func (n *NoopSweagentdAPI) MintServerToServerTokenForRepo(ctx context.Context, req *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
	if n.MockMintServerToServerTokenForRepo != nil {
		return n.MockMintServerToServerTokenForRepo(ctx, req)
	}
	return &sweagentdTwirp.MintServerToServerTokenForRepoResponse{
		Token: "mock-token",
	}, nil
}

func (n *NoopSweagentdAPI) MintServerToServerTokenForRepos(ctx context.Context, req *sweagentdTwirp.MintServerToServerTokenForReposRequest) (*sweagentdTwirp.MintServerToServerTokenForReposResponse, error) {
	if n.MockMintServerToServerTokenForRepos != nil {
		return n.MockMintServerToServerTokenForRepos(ctx, req)
	}
	return &sweagentdTwirp.MintServerToServerTokenForReposResponse{
		Token: "mock-token",
	}, nil
}

func (n *NoopSweagentdAPI) EnterpriseAgents(ctx context.Context, req *sweagentdTwirp.EnterpriseAgentsRequest) (*sweagentdTwirp.EnterpriseAgentsResponse, error) {
	if n.MockEnterpriseAgents != nil {
		return n.MockEnterpriseAgents(ctx, req)
	}

	// Default mock response with the repository ID
	return &sweagentdTwirp.EnterpriseAgentsResponse{
		RepositoryId: req.GetRepositoryId(),
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

func (n *NoopSweagentdAPI) GetOrganizationCCARunnerSettings(ctx context.Context, req *sweagentdTwirp.GetOrganizationCCARunnerSettingsRequest) (*sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse, error) {
	if n.MockGetOrganizationCCARunnerSettings != nil {
		return n.MockGetOrganizationCCARunnerSettings(ctx, req)
	}
	// Return default runner settings for noop client (standard runner, no customization)
	return &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse{
		Runner:                       &sweagentdTwirp.GetOrganizationCCARunnerSettingsResponse_StandardRunner{StandardRunner: &emptypb.Empty{}},
		AllowRepositoryCustomization: false,
	}, nil
}

func (n *NoopSweagentdAPI) GetEffectiveTriggerActorPolicy(ctx context.Context, req *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
	if n.MockGetEffectiveTriggerActorPolicy != nil {
		return n.MockGetEffectiveTriggerActorPolicy(ctx, req)
	}
	// Default: read-access triggers are not allowed (matches the dotcom default-deny posture).
	return &sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse{
		AllowReadAccessTriggers: false,
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

func (n *NoopSweagentdAPI) GetAgenticApps(ctx context.Context, req *sweagentdTwirp.GetAgenticAppsRequest) (*sweagentdTwirp.GetAgenticAppsResponse, error) {
	if n.MockGetAgenticApps != nil {
		return n.MockGetAgenticApps(ctx, req)
	}
	// Default: return empty list
	return &sweagentdTwirp.GetAgenticAppsResponse{
		AgenticApps: []*sweagentdTwirp.AgenticApp{},
	}, nil
}

func (n *NoopSweagentdAPI) IsBypassActor(ctx context.Context, req *sweagentdTwirp.IsBypassActorRequest) (*sweagentdTwirp.IsBypassActorResponse, error) {
	if n.MockIsBypassActor != nil {
		return n.MockIsBypassActor(ctx, req)
	}
	// Default: return false (actor is not a bypass actor)
	return &sweagentdTwirp.IsBypassActorResponse{IsBypassActor: false}, nil
}

func (n *NoopSweagentdAPI) RevokeTokens(ctx context.Context, req *sweagentdTwirp.RevokeTokensRequest) (*sweagentdTwirp.RevokeTokensResponse, error) {
	if n.MockRevokeTokens != nil {
		return n.MockRevokeTokens(ctx, req)
	}
	// Default: report all tokens as successfully revoked
	return &sweagentdTwirp.RevokeTokensResponse{
		TotalRevoked: int32(len(req.Tokens)),
	}, nil
}

func (n *NoopSweagentdAPI) SignCommit(ctx context.Context, req *sweagentdTwirp.SignCommitRequest) (*sweagentdTwirp.SignCommitResponse, error) {
	if n.MockSignCommit != nil {
		return n.MockSignCommit(ctx, req)
	}
	// Default: return a mock signature
	return &sweagentdTwirp.SignCommitResponse{
		Signature: "mock-signature",
	}, nil
}

func (n *NoopSweagentdAPI) GetRepositoryInstallation(ctx context.Context, req *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
	if n.MockGetRepositoryInstallation != nil {
		return n.MockGetRepositoryInstallation(ctx, req)
	}
	// Default: return a basic installation response
	return &sweagentdTwirp.GetRepositoryInstallationResponse{
		InstallationId: 1,
		OwnerId:        200,
		OwnerLogin:     "test-owner",
		OwnerType:      sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION,
		ClientId:       "test-client-id",
		RepoName:       "test-repo",
	}, nil
}

func (n *NoopSweagentdAPI) IntegrationNeedsAuthorizationFromUser(ctx context.Context, req *sweagentdTwirp.IntegrationNeedsAuthorizationFromUserRequest) (*sweagentdTwirp.IntegrationNeedsAuthorizationFromUserResponse, error) {
	if n.MockIntegrationNeedsAuthorizationFromUser != nil {
		return n.MockIntegrationNeedsAuthorizationFromUser(ctx, req)
	}

	return &sweagentdTwirp.IntegrationNeedsAuthorizationFromUserResponse{
		NeedsAuthorization: false,
	}, nil
}

func (n *NoopSweagentdAPI) ManagedSettingsRepository(ctx context.Context, req *sweagentdTwirp.ManagedSettingsRepositoryRequest) (*sweagentdTwirp.ManagedSettingsRepositoryResponse, error) {
	if n.MockManagedSettingsRepository != nil {
		return n.MockManagedSettingsRepository(ctx, req)
	}
	// Default: no managed settings repository configured.
	return &sweagentdTwirp.ManagedSettingsRepositoryResponse{}, nil
}
