// Package ghapi provides a client for REST API access to gh/gh.
// It supports both public REST endpoints and /internal endpoints.
package ghapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/v2/middleware/requestid"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"

	"github.com/bradleyfalzon/ghinstallation/v2"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	gogh "github.com/google/go-github/v52/github"
	"github.com/pkg/errors"
	"golang.org/x/oauth2"
)

// Client is a REST client for the GitHub API.
// It supports both public endpoints and internal endpoints.
// See GetWorkflowRunAnnotations for an example using the public API.
type Client struct {
	appClient *gogh.Client

	internalUrl string

	// HMACKey is used for internal endpoints.
	hmacKey string

	logger log.Logger
	stats  stats.Client
}

func New(cfg *config.Config, logger log.Logger, stats stats.Client) (*Client, error) {
	out := &Client{
		logger: logger,
		stats:  stats,
	}

	// Set fields for the App Client - if the private key is not set, we do not initialize the client.
	if cfg.GitHubAppPrivateKey != nil {
		err := cfg.GitHubAppPrivateKey.Validate()
		if err != nil {
			return nil, errors.Wrap(err, "GitHub App Private Key is invalid")
		}

		atr := ghinstallation.NewAppsTransportFromPrivateKey(http.DefaultTransport, cfg.GitHubAppID, cfg.GitHubAppPrivateKey)
		atr.BaseURL = cfg.GitHubApiBaseAddr

		baseUrl, err := url.Parse(cfg.GitHubApiBaseAddr + "/")
		if err != nil {
			return nil, errors.Wrap(err, "parsing base URL for GitHub API client")
		}
		c := gogh.NewClient(&http.Client{Transport: atr})
		c.BaseURL = baseUrl
		out.appClient = c
	}

	// Set fields for the Internal Client
	out.hmacKey = cfg.GitHubTwirpHMACKey
	out.internalUrl = cfg.GitHubInternalApiAddr
	return out, nil
}

// newClientForRepo returns an new client with permission to operate on RepoID on behalf of OwnerID
// appClient is only used to obtain the token to create the new client.
func newClientForRepo(ctx context.Context, appClient *gogh.Client, ownerID ts.OwnerEID, repoID ts.RepositoryEID) (*gogh.Client, error) {
	// The client might not exist if the PrivateKey was not set. This makes local testing easier.
	if appClient == nil {
		return nil, errors.New("appClient not initialized - GitHub App Private Key might not be set")
	}

	token, err := createRepositoryInstallationToken(ctx, appClient, ownerID, repoID)
	if err != nil {
		return nil, errors.Wrap(err, "creating GitHub global installation token")
	}

	sts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: *token})
	oAuthClient := oauth2.NewClient(ctx, sts)
	client := gogh.NewClient(oAuthClient)
	client.BaseURL = appClient.BaseURL

	return client, nil
}

// sendPostRequestInternal sends a POST request to the /internal API.
func (c *Client) sendPostRequestInternal(ctx context.Context, path string, requestData, responseValue interface{}) error {
	reqBody, err := json.Marshal(requestData)
	if err != nil {
		return err
	}

	// BaseURL here is http://api.github.localhost/internal with the trailing /internal
	req, err := http.NewRequestWithContext(ctx, "POST", c.internalUrl+path, bytes.NewReader(reqBody))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	// These endpoints use the HMAC for for authentication
	hmac := hmac.NewRequestHMAC(c.hmacKey)
	req.Header.Set("Request-HMAC", hmac.String())

	requestid.Forward(req)

	// TODO: Create a client in the constructor to make it possible to inject the VCR Recorder
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	// If we didnt get 200 OK, we log the response body to help debug the issue.
	if resp.StatusCode != http.StatusOK {
		c.logger.Error("sendPostRequestInternal failed response",
			kvp.String("gh.turboscan.internal_request.resp_body", string(body)),
		)
		return errors.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	err = json.Unmarshal(body, responseValue)
	return err
}
