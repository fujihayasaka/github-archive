package repositories

import (
	"net/http"
	"strings"

	"github.com/github/actions-usage-metrics/internal/config"
	twirpRepositories "github.com/github/github-proto/gen/go/repositories/v1"
	twirpAuth "github.com/github/go-twirp/client/auth"
)

var repositoryClient twirpRepositories.RepositoriesAPI

func setRepositoriesClient(cfg config.HttpConfig) error {
	// setup an HTTP client that supports request HMAC signing
	hmacKeys := strings.Split(cfg.TwirpInternalApiHMAC, " ")
	primaryKey := hmacKeys[0]
	twirpClient, err := twirpAuth.NewRequestHMACSigner(primaryKey, http.DefaultClient)

	if err != nil {
		return err
	}

	// setup the client using the internal Twirp API url, and Request-HMAC enabled HTTP client
	client := twirpRepositories.NewRepositoriesAPIProtobufClient(cfg.TwirpInternalApiUrl, twirpClient)
	repositoryClient = client
	return nil
}

func GetRepositoriesClient() twirpRepositories.RepositoriesAPI {
	return repositoryClient
}
