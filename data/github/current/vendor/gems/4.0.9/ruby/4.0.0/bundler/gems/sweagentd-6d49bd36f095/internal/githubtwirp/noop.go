package githubtwirp

import (
	"context"
	"fmt"

	billingClient "github.com/github/billing-platform/clients/go/v1/go-client/client"
	billingProto "github.com/github/billing-platform/clients/go/v1/go-client/lib/twirp/proto"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

type NoopClient struct {
	ClientInterface
	CopilotIntegrationIDValue   *string
	NoopSweagentdAPI            *NoopSweagentdAPI
	NoopUserDetailAPI           *NoopUserDetailAPI
	NoopLimiterAPI              *NoopLimiterAPI
	NoopAuthorizationAPI        *NoopAuthorizationAPI
	NoopRepositoriesAPI         *NoopRepositoriesAPI
	NoopBillingClient           *billingMocks.MockClientInterface
	NoopCacheStore              cache.Store
	MockIsAgentEnabled          func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error)
	MockIsMemoryDisabledForRepo func(ctx context.Context, repositoryID int64, userID int64) (bool, error)
	IsAgentEnabledCalls         []IsAgentEnabledCall
}

type IsAgentEnabledCall struct {
	AgentID      int64
	UserID       int64
	RepositoryID int64
}

// Ensure NoopClient implements ClientInterface
var _ ClientInterface = &NoopClient{}

func NewNoopClient() *NoopClient {
	return &NoopClient{
		NoopSweagentdAPI:     &NoopSweagentdAPI{},
		NoopUserDetailAPI:    &NoopUserDetailAPI{},
		NoopLimiterAPI:       &NoopLimiterAPI{},
		NoopAuthorizationAPI: &NoopAuthorizationAPI{},
		NoopRepositoriesAPI:  &NoopRepositoriesAPI{ShouldReturnError: false},
		NoopBillingClient:    &billingMocks.MockClientInterface{},
		NoopCacheStore:       cache.NewMemoryCacheStore(),
	}
}

// NewNoopClientWithRepositoryError creates a NoopClient that returns errors for repository access
func NewNoopClientWithRepositoryError() *NoopClient {
	return &NoopClient{
		NoopSweagentdAPI:     &NoopSweagentdAPI{},
		NoopUserDetailAPI:    &NoopUserDetailAPI{},
		NoopLimiterAPI:       &NoopLimiterAPI{},
		NoopAuthorizationAPI: &NoopAuthorizationAPI{},
		NoopRepositoriesAPI:  &NoopRepositoriesAPI{ShouldReturnError: true},
		NoopBillingClient:    &billingMocks.MockClientInterface{},
	}
}

// NewNoopClientWithMultipleRepositories creates a NoopClient that returns multiple repositories for testing
func NewNoopClientWithMultipleRepositories() *NoopClient {
	return &NoopClient{
		NoopSweagentdAPI:     &NoopSweagentdAPI{},
		NoopUserDetailAPI:    &NoopUserDetailAPI{},
		NoopLimiterAPI:       &NoopLimiterAPI{},
		NoopAuthorizationAPI: &NoopAuthorizationAPI{},
		NoopRepositoriesAPI:  &NoopRepositoriesAPI{ShouldReturnMultiple: true},
		NoopBillingClient:    &billingMocks.MockClientInterface{},
	}
}

func (n *NoopClient) SweagentdAPI() sweagentdTwirp.SweagentdAPI {
	return n.NoopSweagentdAPI
}

func (n *NoopClient) UserDetailAPI() copilotUsersTwirp.CopilotUserDetailAPI {
	return n.NoopUserDetailAPI
}

func (n *NoopClient) LimiterAPI() copilotLimitersTwirp.CopilotLimiterAPI {
	if n.NoopLimiterAPI == nil {
		return &NoopLimiterAPI{}
	}
	return n.NoopLimiterAPI
}

func (n *NoopClient) CopilotIntegrationID() *string {
	return n.CopilotIntegrationIDValue
}

func (n *NoopClient) CacheStore() cache.Store {
	if n.NoopCacheStore == nil {
		n.NoopCacheStore = cache.NewMemoryCacheStore()
	}
	return n.NoopCacheStore
}

func (n *NoopClient) BillingClient() billingClient.ClientInterface {
	if n.NoopBillingClient == nil {
		return &noopBillingClient{}
	}
	return n.NoopBillingClient
}

// noopBillingClient is a default billing client that always allows usage.
// Tests that need specific billing behavior should set NoopBillingClient explicitly.
type noopBillingClient struct{}

func (c *noopBillingClient) CanProceedWithUsage(_ context.Context, _ *billingProto.CanProceedWithUsageRequest) (*billingProto.CanProceedWithUsageResponse, error) {
	return &billingProto.CanProceedWithUsageResponse{CanProceed: true}, nil
}

func (n *NoopClient) AuthorizationAPI() coreTwirp.AuthorizationAPI {
	return n.NoopAuthorizationAPI
}

func (n *NoopClient) RepositoriesAPI() repositoriesTwirp.RepositoriesAPI {
	return n.NoopRepositoriesAPI
}

func (n *NoopClient) GetRepoById(ctx context.Context, id int64) (*repositoriesTwirp.RepositoryListItem, error) {
	req := &repositoriesTwirp.FindRepositoriesRequest{
		Ids: []int64{id},
	}
	resp, err := n.NoopRepositoriesAPI.FindRepositories(ctx, req)
	if err != nil {
		return nil, err
	}
	repos := resp.GetRepositories()
	if len(repos) == 0 {
		return nil, ErrRepoNotFound
	}
	return repos[0], nil
}

func (n *NoopClient) GetRepoByName(ctx context.Context, owner, name string) (*repositoriesTwirp.RepositoryListItem, error) {
	nwo := fmt.Sprintf("%s/%s", owner, name)
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{nwo},
	}
	resp, err := n.NoopRepositoriesAPI.FindRepositoriesByName(ctx, req)
	if err != nil {
		return nil, err
	}
	repos := resp.GetRepositories()
	if len(repos) == 0 {
		return nil, ErrRepoNotFound
	}
	return repos[0], nil
}

func (n *NoopClient) GetCopilotUserDetails(ctx context.Context, userID int64) (*copilotUsersTwirp.CopilotUserDetails, error) {
	if n.NoopUserDetailAPI != nil && n.NoopUserDetailAPI.MockGetCopilotUser != nil {
		resp, err := n.NoopUserDetailAPI.MockGetCopilotUser(ctx, &copilotUsersTwirp.GetCopilotUserRequest{
			Id: uint64(userID),
		})
		if err != nil {
			return nil, err
		}
		// Best-effort memoize in ctx to match real client behavior
		_ = requestctx.AddCopilotUserDetails(ctx, userID, resp.UserDetails)
		return resp.UserDetails, nil
	}
	details := &copilotUsersTwirp.CopilotUserDetails{
		Id:                    uint64(userID),
		BillingEntityResolved: true,
	}
	// Best-effort memoize in ctx to match real client behavior
	_ = requestctx.AddCopilotUserDetails(ctx, userID, details)
	return details, nil
}

func (n *NoopClient) GetCustomerID(ctx context.Context, userID int64) (int64, error) {
	// Use mocked implementation if available
	if n.NoopUserDetailAPI != nil && n.NoopLimiterAPI != nil && n.NoopLimiterAPI.MockGetConsumptiveUser != nil {
		// First get user details for tracking ID
		userDetails, err := n.GetCopilotUserDetails(ctx, userID)
		if err != nil {
			return 0, fmt.Errorf("failed to get user details: %w", err)
		}

		// Then get consumptive user to determine customer ID
		response, err := n.NoopLimiterAPI.MockGetConsumptiveUser(ctx, &copilotLimitersTwirp.GetConsumptiveUserRequest{
			CopilotTrackingId: userDetails.GetAnalyticsTrackingId(),
		})
		if err != nil {
			return 0, fmt.Errorf("failed to get consumptive user: %w", err)
		}

		customerID := int64(0)
		if len(response.CustomerIds) == 0 && IsMultiSKU(response.AccessType.String()) {
			customerID = -1
		} else if len(response.CustomerIds) > 0 {
			customerID = response.CustomerIds[0]
		}
		return customerID, nil
	}
	// Simple noop implementation
	return 123, nil
}

func (n *NoopClient) IsAgentEnabled(ctx context.Context, agentID, userID int64, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error) {
	// Track the call
	n.IsAgentEnabledCalls = append(n.IsAgentEnabledCalls, IsAgentEnabledCall{
		AgentID:      agentID,
		UserID:       userID,
		RepositoryID: repositoryID,
	})

	// Use mock if provided
	if n.MockIsAgentEnabled != nil {
		return n.MockIsAgentEnabled(ctx, agentID, userID, repositoryID)
	}

	if n.NoopSweagentdAPI != nil && n.NoopSweagentdAPI.ConfigurationForRepositoryResponse != nil {
		return n.NoopSweagentdAPI.ConfigurationForRepositoryResponse.IsAgentEnabled, n.NoopSweagentdAPI.ConfigurationForRepositoryResponse, nil
	}

	// Simple noop implementation - return true for enabled
	return true, &sweagentdTwirp.ConfigurationForRepositoryResponse{IsAgentEnabled: true}, nil
}

func (n *NoopClient) IntegrationNeedsAuthorizationFromUser(ctx context.Context, userID, agentID int64) (bool, string, error) {
	if n.NoopSweagentdAPI != nil {
		resp, err := n.NoopSweagentdAPI.IntegrationNeedsAuthorizationFromUser(ctx, &sweagentdTwirp.IntegrationNeedsAuthorizationFromUserRequest{
			UserId:  uint64(userID),
			AgentId: agentID,
		})
		if err != nil {
			return false, "", err
		}

		return resp.NeedsAuthorization, resp.AuthorizationUrl, nil
	}

	return false, "", nil
}

func (n *NoopClient) IsMemoryDisabledForRepo(ctx context.Context, repositoryID int64, userID int64) (bool, error) {
	if n.MockIsMemoryDisabledForRepo != nil {
		return n.MockIsMemoryDisabledForRepo(ctx, repositoryID, userID)
	}
	// Default: memory is not disabled
	return false, nil
}

func (n *NoopClient) TokenHasAccess(ctx context.Context, user *requestctx.UserInfo, rules []*HasAccessCheck) (bool, error) {
	// Guard against checking empty permissions
	if len(rules) == 0 {
		return false, fmt.Errorf("no access checks provided to verify")
	}

	// Build the batch request
	reqObjs := make([]*coreTwirp.AuthorizationRequestObject, len(rules))
	for i, rule := range rules {
		reqObjs[i] = &coreTwirp.AuthorizationRequestObject{
			Id:             fmt.Sprintf("%s-%s-%d", rule.Action, rule.ResourceType, i),
			Action:         rule.Action,
			ResourceId:     rule.ResourceId,
			ResourceType:   rule.ResourceType,
			OrganizationId: rule.OrganizationID,
			RepositoryId:   rule.RepositoryID,
			RepositoryNwo:  rule.RepositoryNWO,
		}
	}

	batch := &coreTwirp.BatchControlAccessRequest{
		AccessToken:           user.TokenInfo.Token,
		AuthorizationRequests: reqObjs,
		RequestIp:             user.RequestIP,
	}

	// Call the authorization API
	result, err := n.NoopAuthorizationAPI.BatchControlAccess(ctx, batch)
	if err != nil {
		return false, fmt.Errorf("failed to check access: %w", err)
	}

	// Check if all decisions passed
	for _, decision := range result.Decisions {
		if !decision.GetDecision() {
			return false, nil
		}
	}

	return true, nil
}

func (n *NoopClient) GetInstallationInfo(ctx context.Context, appID, repoID int64) (*InstallationInfo, error) {
	resp, err := n.NoopSweagentdAPI.GetRepositoryInstallation(ctx, &sweagentdTwirp.GetRepositoryInstallationRequest{
		AgentId:      appID,
		RepositoryId: uint64(repoID),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get repository installation: %w", err)
	}

	ownerType := sweagentd.OwnerTypeOrganization
	if resp.OwnerType != sweagentdTwirp.RepositoryOwnerType_REPOSITORY_OWNER_TYPE_ORGANIZATION {
		ownerType = sweagentd.OwnerTypeUser
	}

	return &InstallationInfo{
		ID:                repoID,
		Name:              resp.RepoName,
		OwnerID:           int64(resp.OwnerId),
		OwnerLogin:        resp.OwnerLogin,
		OwnerType:         ownerType,
		AppClientID:       resp.ClientId,
		AppIsGlobal:       resp.IsGlobal,
		AppInstallationID: int64(resp.InstallationId),
		Permissions:       resp.GetPermissions(),
	}, nil
}

func (n *NoopClient) GetInstallationPermissions(ctx context.Context, appID, repoID int64) (map[string]string, error) {
	resp, err := n.NoopSweagentdAPI.GetRepositoryInstallation(ctx, &sweagentdTwirp.GetRepositoryInstallationRequest{
		AgentId:      appID,
		RepositoryId: uint64(repoID),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get repository installation permissions: %w", err)
	}
	return resp.GetPermissions(), nil
}
