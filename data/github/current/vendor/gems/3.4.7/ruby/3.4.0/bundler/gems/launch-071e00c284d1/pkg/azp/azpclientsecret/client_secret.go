package azpclientsecret

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/workflowbuild/azp/config"
)

type clientSecretTokenSource struct {
	client         *azidentity.ClientSecretCredential
	cache          launchcache.AZPS2SAccessTokenCache
	obs            *observability.Observability
	s2sSPNClientID string
}

func (c clientSecretTokenSource) Get(ctx context.Context) (string, error) {
	t, exp, ok, err := c.cache.Get(ctx)
	if err == nil && ok && exp.After(time.Now()) {
		c.obs.Logger.Log(ctx, "use cached SPN access token")
		return string(t), nil
	}

	tok, err := c.client.GetToken(ctx, policy.TokenRequestOptions{
		Scopes: []string{fmt.Sprintf("%s/.default", c.s2sSPNClientID)},
	})
	if err != nil {
		return "", err
	}

	expiresIn := time.Until(tok.ExpiresOn.Add(-5 * time.Minute))
	cerr := c.cache.Set(ctx, []byte(tok.Token), expiresIn)
	if cerr != nil {
		c.obs.Logger.Error(ctx, fmt.Errorf("failed to set SPN access token cache: %w", cerr).Error())
	}

	c.obs.Logger.Log(ctx, "use fresh SPN access token")
	return tok.Token, nil
}

func TokenSource(
	cfg config.AzureProviderConfig,
	client *http.Client,
	cache launchcache.AZPCache,
	obs *observability.Observability,
) (launchhttp.TokenSource, error) {
	clientOptions := azcore.ClientOptions{
		Retry: policy.RetryOptions{
			MaxRetries:    3,
			TryTimeout:    10 * time.Second,
			RetryDelay:    4 * time.Second,
			MaxRetryDelay: 10 * time.Second,
		},
		Transport: client,
	}

	credOpts := &azidentity.ClientSecretCredentialOptions{
		ClientOptions: clientOptions,
	}

	csc, err := azidentity.NewClientSecretCredential(
		cfg.ActionsServiceS2SSPNTenantID,
		cfg.ActionsServiceS2SSPNClientID,
		cfg.ActionsServiceS2SSPNClientSecret,
		credOpts,
	)
	if err != nil {
		return nil, err
	}

	return &clientSecretTokenSource{
		client:         csc,
		cache:          cache.S2SAccessTokenCacheFor(cfg.ActionsServiceS2SSPNClientID),
		obs:            obs,
		s2sSPNClientID: cfg.ActionsServiceS2SSPNClientID,
	}, nil
}
