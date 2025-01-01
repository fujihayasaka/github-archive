package aqueduct

import (
	"net/http"
	"time"
)

const defaultHTTPTimeout = 20 * time.Second

type defaultHTTPClient struct {
	client *http.Client
}

func newDefaultHTTPClient() *defaultHTTPClient {
	return &defaultHTTPClient{
		client: &http.Client{
			Timeout: defaultHTTPTimeout,
		},
	}
}

func (c *defaultHTTPClient) Do(req *http.Request) (*http.Response, error) {
	return c.client.Do(req)
}

func (c *defaultHTTPClient) GetRoundTripper() http.RoundTripper {
	return c.client.Transport
}

func (c *defaultHTTPClient) SetRoundTripper(transport http.RoundTripper) {
	c.client.Transport = transport
}

type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
	GetRoundTripper() http.RoundTripper
	SetRoundTripper(http.RoundTripper)
}
