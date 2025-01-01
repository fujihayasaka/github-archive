package tokensrc

import (
	"fmt"

	"github.com/github/launch/pkg/azp/azpbearer"
	"github.com/github/launch/pkg/azp/azpbearer/jwt"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/workflowbuild/azp/config"
)

func S2SForTokenService(cfg config.AzureProviderConfig, btc *azpbearer.Client) launchhttp.TokenSource {
	es2sSigner := jwt.ForTokenSvcS2SFrom(cfg)
	return btc.TokenSourceFor(
		es2sSigner,
		getTokenServiceURL(cfg),
		cfg.ServicePrincipalID,
		cfg.AZPResource,
	)
}
func getTokenServiceURL(cfg config.AzureProviderConfig) string {
	return fmt.Sprintf("%s/_apis/oauth2/token/%s", cfg.TokenServiceBaseURL, cfg.AZPResource)
}
