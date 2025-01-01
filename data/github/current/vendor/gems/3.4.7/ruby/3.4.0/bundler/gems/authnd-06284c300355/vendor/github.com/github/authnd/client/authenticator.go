package client

import (
	"context"
	"time"

	"github.com/pkg/errors"

	"github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
)

const (
	catalogServiceDimensionName = "catalog_service"
	clientVersionDimensionName  = "client_version"
	requestsMetric              = "authnd.client.request"
	timingMetric                = "authnd.client.timing"
	serviceDimensionName        = "service"
	methodDimensionName         = "method"
)

type AuthenticateRequest struct {
	*Credentials
}

// NewAuthenticateRequest creates an AuthenticateRequest using the provided Credentials.
func NewAuthenticateRequest(credentials *Credentials) *AuthenticateRequest {
	return &AuthenticateRequest{credentials}
}

// An Authenticator represents a connection to the Authnd Authenticator service.
// For optimal network performance, use a single Authenticator for all your application's requests.
// Authenticators are safe for concurrent use by multiple goroutines.
type Authenticator interface {
	// Authenticate sends an authentication request to Authnd and processes the response.
	// Use NewRequest to create a Request containing the credentials to be authenticated.
	// Returns an error in the event of an unexpected error (such as a network interruption).
	// The response indicates an authentication success/failure and includes any applicable attributes.
	Authenticate(ctx context.Context, request *AuthenticateRequest, opts ...RequestOption) (*AuthenticateResponse, error)
}

type authenticator struct {
	twirpClient pb.Authenticator
	statter     stats.Client
}

// NewAuthenticator creates and returns a Authenticator with the provided options, or an error if applying any of the options failed.
// If no options are provided, recommended options will be applied.
// For optimal network performance, use a single Authenticator for all your application's requests.
// Authenticators are safe for concurrent use by multiple goroutines.
func NewAuthenticator(addr string, catalogService string, opts ...Option) (Authenticator, error) {
	if addr == "" {
		return nil, errors.New("must provide a non empty addr")
	}
	if catalogService == "" {
		return nil, errors.New("must provide a non empty catalogService")
	}

	clientOpts := defaultClientOptions()
	err := applyOptions(clientOpts, opts...)
	if err != nil {
		return nil, errors.Wrap(err, "error applying options")
	}

	statter := clientOpts.Statter.WithTags(stats.Tags{
		catalogServiceDimensionName: catalogService,
		clientVersionDimensionName:  Version,
		serviceDimensionName:        "Authenticator",
	})

	httpClient := clientOpts.CustomHTTPClient
	if httpClient == nil {
		httpClient = createHTTPClient(clientOpts.HTTPClientOptions, statter)
	}

	// always set the catalog service header and user agent
	httpClient = middleware.ApplyCatalogService(httpClient, catalogService)
	httpClient = middleware.ApplyUserAgent(httpClient, Version)

	return &authenticator{
		pb.NewAuthenticatorProtobufClient(addr, httpClient),
		statter,
	}, nil
}

func (a *authenticator) Authenticate(ctx context.Context, request *AuthenticateRequest, opts ...RequestOption) (*AuthenticateResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "Authenticate"}
	defer func() {
		duration := time.Since(start)
		a.statter.Counter(requestsMetric, tags, 1)
		a.statter.DistributionMs(timingMetric, tags, duration)
	}()

	for _, opt := range opts {
		ctx = opt(ctx)
	}

	protobufRequest := &pb.AuthenticateRequest{
		Credentials: request.Credentials.Credentials,
	}
	response, err := a.twirpClient.Authenticate(ctx, protobufRequest)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return responseFromTwirp(response)
}
