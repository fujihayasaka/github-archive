// Package monolith provides a Protobuf client for communicating with github/github
package monolith

import (
	"fmt"
	"net/http"

	twauth "github.com/github/go-twirp/v2/client/auth"
	customersv1 "github.com/github/licensify/lib/monolith-twirp/customers/v1"
	repositoriesv1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
)

// Client is a wrapper around the monolith-twirp APIs.
type Client struct {
	customersv1.UsersAPI
	repositoriesv1.RepositoriesAPI
}

// NewClient creates a new protobuf client for communicating with github/github.
func NewClient(baseURL, hmacKey string) (*Client, error) {
	httpClient := &http.DefaultClient
	twirpClient, err := twauth.NewRequestHMACSigner(hmacKey, *httpClient)
	if err != nil {
		return nil, fmt.Errorf("failed to create monolith twirp client: %w", err)
	}
	return &Client{
		UsersAPI:        customersv1.NewUsersAPIProtobufClient(baseURL, twirpClient),
		RepositoriesAPI: repositoriesv1.NewRepositoriesAPIProtobufClient(baseURL, twirpClient),
	}, nil
}
