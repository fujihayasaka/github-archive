package aqueduct

import (
	"net/http"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability/statter"
)

type Factory struct {
	httpClient *http.Client
}

func NewFactory(httpClient *http.Client) Factory {
	return Factory{httpClient}
}

func (f Factory) NewClient(stats statter.Statter, breaker *circuit.Breaker, opts *ClientOptions) (Client, error) {
	return newClient(stats, breaker, f.httpClient, opts)
}
