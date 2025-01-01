package ghinternal

import (
	"net/http"
	"net/url"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type Factory interface {
	Create() (Client, error)
	CreateWithAccessToken(token *tokens.AccessToken) (Client, error)
	CreateConnectClient(token *tokens.AccessToken) (Client, error)
}

type factory struct {
	base       *url.URL
	breaker    *circuit.Breaker
	httpClient *http.Client
	signingKey []byte
	hooks      *httpclient.ClientHooks
	obs        *observability.Observability
}

func NewFactory(base *url.URL, obs *observability.Observability, breaker *circuit.Breaker, signingKey []byte, httpClient *http.Client, hooks *httpclient.ClientHooks) *factory {
	return &factory{
		base:       base,
		obs:        obs,
		breaker:    breaker,
		signingKey: signingKey,
		httpClient: httpClient,
		hooks:      hooks,
	}
}

func (f *factory) Create() (Client, error) {
	return New(
		f.base,
		f.httpClient,
		f.obs,
		WithRequestOptions(WithHMAC(f.signingKey)),
		WithBreaker(f.breaker),
		WithClientHooks(f.hooks),
	), nil
}

var connectBaseURL = func() *url.URL {
	h, err := url.Parse("https://api.github.com")
	if err != nil {
		panic(err)
	}
	return h
}()

// CreateConnectClient creates a GitHub Connect client, meaning that this will
// always talk to production regardless of configuration.
func (f *factory) CreateConnectClient(token *tokens.AccessToken) (Client, error) {
	return New(
		connectBaseURL,
		f.httpClient,
		f.obs,
		WithRequestOptions(WithAccessToken(token)),
		WithBreaker(f.breaker),
		WithClientHooks(f.hooks),
	), nil
}

func (f *factory) CreateWithAccessToken(token *tokens.AccessToken) (Client, error) {
	return New(
		f.base,
		f.httpClient,
		f.obs,
		WithRequestOptions(WithAccessToken(token)),
		WithBreaker(f.breaker),
		WithClientHooks(f.hooks),
	), nil
}
