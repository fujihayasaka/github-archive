package ghinternal

import (
	"net/url"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability"
	"github.com/github/launch/utils/apphttp"
)

type testFactory struct {
	apiBase    *url.URL
	obs        *observability.Observability
	breaker    *circuit.Breaker
	signingKey []byte
}

func NewTestFactory(apiBase *url.URL, obs *observability.Observability, breaker *circuit.Breaker, signingKey []byte) *testFactory {
	return &testFactory{apiBase: apiBase, obs: obs, breaker: breaker, signingKey: signingKey}
}

func (f *testFactory) Create() (Client, error) {
	return New(
		f.apiBase,
		apphttp.NewClient(),
		f.obs,
		WithRequestOptions(WithHMAC(f.signingKey)),
	), nil
}

// CreateConnectClient creates a GitHub Connect client, meaning that this will
// always talk to production regardless of configuration.
func (f *testFactory) CreateConnectClient(token *tokens.AccessToken) (Client, error) {
	return New(
		f.apiBase,
		apphttp.NewClient(),
		f.obs,
		WithRequestOptions(WithAccessToken(token)),
	), nil
}

func (f *testFactory) CreateWithAccessToken(token *tokens.AccessToken) (Client, error) {
	return New(
		f.apiBase,
		apphttp.NewClient(),
		f.obs,
		WithRequestOptions(WithAccessToken(token)),
	), nil
}
