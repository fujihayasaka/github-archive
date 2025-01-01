package ahttp

import (
	"net/http"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability/statter"
)

// RetryClient is a wrapper around Client that maps `Do` to `DoWithRetries`
type RetryClient struct {
	*Client
}

func NewRetryClient(breaker *circuit.Breaker, statter statter.Statter, httpClient *http.Client, name string) *RetryClient {
	return &RetryClient{NewClient(breaker, statter, DefaultBackoffStrategy, httpClient, name)}
}

func (c *RetryClient) Do(req *http.Request) (*http.Response, error) {
	return c.DoWithRetries(req)
}

func (c *RetryClient) GetRoundTripper() http.RoundTripper {
	return c.client.Transport
}

func (c *RetryClient) SetRoundTripper(transport http.RoundTripper) {
	c.client.Transport = transport
}
