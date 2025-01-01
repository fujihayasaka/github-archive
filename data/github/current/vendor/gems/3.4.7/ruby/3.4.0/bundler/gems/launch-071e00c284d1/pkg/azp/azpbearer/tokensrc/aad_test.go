package tokensrc

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/workflowbuild/azp/config"
)

var exampleCfg = config.AzureProviderConfig{
	AadOAuthBaseURL: "https://login.microsoftonline.com",
	AZPTenantID:     "VSOGHAAD.onmicrosoft.com",
	VaultTenantID:   "33e01921-4d64-4f8c-a055-5bdaffd5e33d",
}

func Test_urlForKeyVault(t *testing.T) {
	require.Equal(t, "https://login.microsoftonline.com/33e01921-4d64-4f8c-a055-5bdaffd5e33d/oauth2/token", urlForKeyVault(exampleCfg))
}
