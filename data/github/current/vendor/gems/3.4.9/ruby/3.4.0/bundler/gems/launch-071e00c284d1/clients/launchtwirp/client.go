package launchtwirp

import (
	"net/http"

	twirpclient "github.com/github/go-twirp/client"
	twirpauth "github.com/github/go-twirp/client/auth"
	twirprequestid "github.com/github/go-twirp/client/requestid"
	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/ahttp"
)

// NewClient returns an HTTP client for use with twirp clients
func NewClient(secrets []string, breaker *circuit.Breaker, statter statter.Statter, httpClient *http.Client) (twirpclient.Client, error) {
	// Don't retry. Rely on the originating client to retry instead.
	hc := ahttp.NewClient(breaker, statter, ahttp.DefaultBackoffStrategy, httpClient, "launchtwirp")

	signingHTTPClient, err := twirpauth.NewRequestHMACSigner(
		secrets[len(secrets)-1],
		twirprequestid.NewForwarder(
			hc,
		),
	)
	if err != nil {
		return nil, errors.Wrap(err, "Could not create twirp HMAC signer")
	}

	return signingHTTPClient, nil
}
