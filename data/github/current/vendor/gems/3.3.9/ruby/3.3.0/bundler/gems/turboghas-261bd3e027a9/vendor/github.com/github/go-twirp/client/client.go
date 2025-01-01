package client

import "net/http"

// Implements the generated twirp HTTPClient interface.
type Client interface {
	Do(*http.Request) (*http.Response, error)
}
