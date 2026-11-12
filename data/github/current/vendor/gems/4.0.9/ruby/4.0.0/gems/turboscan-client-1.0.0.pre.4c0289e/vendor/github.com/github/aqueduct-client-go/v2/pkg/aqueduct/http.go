package aqueduct

import (
	"net/http"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

const defaultHTTPTimeout = 20 * time.Second

type defaultHTTPClient struct {
	client *http.Client
}

var attributes = otelhttp.WithSpanOptions(trace.WithAttributes(attribute.String("peer.service", "aqueduct-gateway")))

func newDefaultHTTPClient() *defaultHTTPClient {
	return &defaultHTTPClient{
		client: &http.Client{
			Timeout:   defaultHTTPTimeout,
			Transport: otelhttp.NewTransport(http.DefaultTransport, attributes),
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
	c.client.Transport = otelhttp.NewTransport(transport, attributes)
}

type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
	GetRoundTripper() http.RoundTripper
	SetRoundTripper(http.RoundTripper)
}
