// Package client contains useful HTTP client middleware for Twirp-based clients.
package client

import "net/http"

// Client implements the generated twirp HTTPClient interface.
type Client interface {
	Do(*http.Request) (*http.Response, error)
}
