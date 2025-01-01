// Package turboghas provides a client for the TurboGHAS service.
package turboghas

import (
	"net/http"

	twauth "github.com/github/go-twirp/v2/client/auth"
	turboghas "github.com/github/turboghas/proto"
)

// Client is a wrapper around the TurboGHAS API.
type Client struct {
	AdvancedSecurityAPI turboghas.AdvancedSecurityAPI
}

// NewTurboGHASClient creates a new TurboGHAS client.
func NewTurboGHASClient(baseURL, hmacKey string) (*Client, error) {
	httpClient := &http.DefaultClient
	twirpClient, err := twauth.NewRequestHMACSigner(hmacKey, *httpClient)
	if err != nil {
		return nil, err
	}
	return &Client{
		AdvancedSecurityAPI: turboghas.NewAdvancedSecurityAPIProtobufClient(baseURL, twirpClient),
	}, nil
}
