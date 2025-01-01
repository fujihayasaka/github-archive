package tokensrc

import (
	"fmt"

	"github.com/github/launch/pkg/azp/azpbearer"
	"github.com/github/launch/pkg/azp/azpbearer/jwt"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/workflowbuild/azp/config"
)

const aadTokenURLTemplate = "%s/%s/oauth2/token"
const keyvaultResource = "https://vault.azure.net"

func ForKeyVault(cfg config.AzureProviderConfig, btc *azpbearer.Client, certHook jwt.CertHook) launchhttp.TokenSource {
	kvSigner := jwt.ForGHAppTokenFrom(cfg, certHook)
	reqURL := urlForKeyVault(cfg)
	return btc.TokenSourceFor(
		kvSigner,
		reqURL,
		cfg.GHAppID,
		keyvaultResource)
}

func urlForKeyVault(cfg config.AzureProviderConfig) string {
	return fmt.Sprintf(aadTokenURLTemplate, cfg.AadOAuthBaseURL, cfg.VaultTenantID)
}
