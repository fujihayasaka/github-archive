// Package featureflags provides a Protobuf client for communicating with the monolith-twirp-features API.
package featureflags

import (
	"fmt"
	"net/http"

	twauth "github.com/github/go-twirp/v2/client/auth"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
)

// NewClient creates a new protobuf client for communicating with the monolith-twirp-features API.
func NewClient(baseURL, hmacKey string) (twirpFeatures.FeaturesAPI, error) {
	httpClient := http.DefaultClient
	twirpClient, err := twauth.NewRequestHMACSigner(hmacKey, httpClient)

	if err != nil {
		return nil, fmt.Errorf("failed to create features twirp client: %w", err)
	}

	client := twirpFeatures.NewFeaturesAPIProtobufClient(baseURL, twirpClient)
	return client, nil
}
