package monolith

import (
	"context"
	"net/http"

	twirpclientauth "github.com/github/go-twirp/v2/client/auth"
	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
	"github.com/pkg/errors"
)

type ClientConfig struct {
	Context    context.Context
	URL        string
	HMACKey    string
	HTTPClient *http.Client
}

type Client struct {
	RepositoryAPI repositories.RepositoryAPI
}

func NewClient(cfg *ClientConfig) (*Client, error) {
	if cfg.URL == "" {
		return nil, errors.New("URL is required")
	}

	if cfg.HMACKey == "" {
		return nil, errors.New("HMACKey is required")
	}

	if cfg.HTTPClient == nil {
		cfg.HTTPClient = http.DefaultClient
	}

	if cfg.Context == nil {
		cfg.Context = context.Background()
	}

	twirpClient, err := twirpclientauth.NewRequestHMACSigner(cfg.HMACKey, cfg.HTTPClient)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create twirp client")
	}

	reposClient := repositories.NewRepositoryAPIJSONClient(cfg.URL, twirpClient)

	return &Client{
		RepositoryAPI: reposClient,
	}, nil
}
