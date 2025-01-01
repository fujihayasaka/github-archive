package tokensrc

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/workflowbuild/azp/config"
)

func Test_getTokenServiceURL(t *testing.T) {
	cfg := config.AzureProviderConfig{
		TokenServiceBaseURL: "https://tokenghub.actions.githubusercontent.com",
		AZPResource:         "resource",
	}

	require.Equal(t, "https://tokenghub.actions.githubusercontent.com/_apis/oauth2/token/resource", getTokenServiceURL(cfg))
}
