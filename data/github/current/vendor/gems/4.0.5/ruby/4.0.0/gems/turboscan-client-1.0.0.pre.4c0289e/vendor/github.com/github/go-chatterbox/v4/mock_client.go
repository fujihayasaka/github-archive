package chatterbox

import (
	"context"
	"fmt"
	"net/http"
)

// mockClient is a mock implementation of the chatterbox.Client interface.
type mockClient struct {
	cfg MockCfg
}

// MockCfg holds configuration options for the mock client.
type MockCfg struct {
	// Verbose indicates whether to print messages to stdout.
	Verbose bool
}

// NewChatterMock returns a new mock chatterbox.Client which can be used for testing purposes.
// It does not perform any actual HTTP requests and optionally prints messages to stdout.
func NewChatterMock(cfg MockCfg) (Client, error) {
	return &mockClient{cfg: cfg}, nil
}

// Mock the Say method (noop)
func (c *mockClient) Say(ctx context.Context, opts SayPayload) (string, error) {
	if c.cfg.Verbose {
		if opts.Message != nil {
			fmt.Println("Chatter:", opts.Message.text)
		} else {
			fmt.Println("Chatter:", opts.Text)
		}
	}
	return "", nil
}

// WithHTTPClient returns the mock client itself, as it does not use an HTTP client.
func (c *mockClient) WithHTTPClient(httpClient *http.Client) Client {
	return c
}
