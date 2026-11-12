package githubtwirp

import (
	"context"
	"fmt"

	billingClient "github.com/github/billing-platform/clients/go/v1/go-client/client"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

type NoopClient struct {
	ClientInterface
	NoopSweagentdAPI     *NoopSweagentdAPI
	NoopUserDetailAPI    *NoopUserDetailAPI
	NoopLimiterAPI       *NoopLimiterAPI
	NoopAuthorizationAPI *NoopAuthorizationAPI
	NoopRepositoriesAPI  *NoopRepositoriesAPI
	NoopBillingClient    *billingMocks.MockClientInterface
	MockIsAgentEnabled   func(ctx context.Context, agentID, userID, repositoryID int64) (bool, *sweagentdTwirp.ConfigurationForRepositoryResponse, error)
	IsAgentEnabledCalls  []IsAgentEnabledCall
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
	return n.NoopLimiterAPI
}

func (n *NoopClient) BillingClient() billingClient.ClientInterface {
	return n.NoopBillingClient
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
		return resp.UserDetails, nil
	}
	return &copilotUsersTwirp.CopilotUserDetails{
		Id: uint64(userID),
	}, nil
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
