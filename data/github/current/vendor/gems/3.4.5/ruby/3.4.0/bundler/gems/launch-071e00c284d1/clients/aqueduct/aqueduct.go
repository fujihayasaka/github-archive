package aqueduct

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/ahttp"
)

type (
	Job           = aqueduct.Job
	AckStatus     = aqueduct.AckStatus
	ReceiveResult = aqueduct.ReceiveResult
	SendOption    = aqueduct.SendOption
)

var (
	WithJobRedeliveryTimeoutSeconds = aqueduct.WithJobRedeliveryTimeoutSeconds
	WithJobMaxRedeliveryAttempts    = aqueduct.WithJobMaxRedeliveryAttempts
	WithTTL                         = aqueduct.WithTTL
)

const (
	// AckSuccess states that a job was handled successfully.
	AckSuccess = aqueduct.AckSuccess
	// JobTTL is the default time to live for an aqueduct job before it expires.
	JobTTL = 30 * time.Minute
)

type ClientOptions struct {
	App           string
	URL           string
	WorkerID      int
	APIKey        string
	APIKeyVersion int
}

type Client interface {
	aqueduct.Client
}

func newClient(stats statter.Statter, breaker *circuit.Breaker, innerHTTPClient *http.Client, opts *ClientOptions) (aqueduct.Client, error) {
	if opts.URL == "" {
		return nil, errors.New("AqueductURL is required")
	}

	host, _ := os.Hostname()
	clientID := fmt.Sprintf("%s-%s-%d", opts.App, host, opts.WorkerID)

	httpClient := ahttp.NewRetryClient(breaker, stats, innerHTTPClient, "aqueduct")

	clientOpts := []aqueduct.ClientOption{
		aqueduct.WithClientID(clientID),
		aqueduct.WithHTTPClientInterface(httpClient),
	}
	if opts.APIKey != "" {
		clientOpts = append(clientOpts, aqueduct.WithAPIKey(opts.APIKey), aqueduct.WithAPIKeyVersion(opts.APIKeyVersion))
	}

	client, err := aqueduct.NewClient(opts.URL, clientOpts...)

	if err != nil {
		return nil, err
	}

	return client, nil
}
