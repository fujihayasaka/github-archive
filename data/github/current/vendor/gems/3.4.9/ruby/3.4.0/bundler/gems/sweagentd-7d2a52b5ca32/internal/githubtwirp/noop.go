package githubtwirp

import (
	"context"

	billingClient "github.com/github/billing-platform/clients/go/v1/go-client/client"
	billingMocks "github.com/github/billing-platform/clients/go/v1/go-client/mocks"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
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
