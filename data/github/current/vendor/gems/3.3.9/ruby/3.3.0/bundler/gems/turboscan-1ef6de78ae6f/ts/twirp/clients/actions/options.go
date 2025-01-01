package actions

import (
	"net/http"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/launch/services/pb/deploy"
	"github.com/twitchtv/twirp"
)

type Option func(target *LaunchClient)

// WithDebugClient replaces the protobuf twirp client with the JSON one.
// A custom http.RoundTripper can be injected to intercept requests/responses.
func WithDebugClient(rt http.RoundTripper) Option {
	return func(target *LaunchClient) {
		client := http.DefaultClient
		if rt != nil {
			client = &http.Client{Transport: rt}
		}
		target.client = deploy.NewLaunchDeploymentServiceJSONClient(
			target.twirpAddr,
			client,
			twirp.WithClientHooks(target.hooks),
		)
	}
}

// WithLogger injects a logger into the client.
func WithLogger(logger log.Logger) Option {
	return func(target *LaunchClient) {
		target.logger = logger
	}
}
