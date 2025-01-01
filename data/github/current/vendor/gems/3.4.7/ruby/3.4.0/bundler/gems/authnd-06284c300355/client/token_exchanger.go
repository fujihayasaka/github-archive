package client

import (
	"context"
	"time"

	"github.com/pkg/errors"

	"github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
)

type ExchangeTokenRequest struct {
	Credentials *Credentials
}

// NewExchangeTokenRequest creates an ExchangeTokenRequest using the provided token
func NewExchangeTokenRequest(credentials *Credentials) *ExchangeTokenRequest {
	return &ExchangeTokenRequest{
		Credentials: credentials,
	}
}

type ExchangeTokenResponse struct {
	// Result is the status code describing the outcome of the ExchangeToken request.
	//
	// RESULT_SUCCESS indicates a successful authentication, and that the Attributes field will contain attributes describing the authentication context.
	// Any other value indicates a failed authentication, and that the Token field will be empty.
	Result pb.AuthenticateResponse_Result

	Token string
}

// Succeeded returns a boolean indicating if the result in this Response indicates success.
func (r *ExchangeTokenResponse) Succeeded() bool {
	return r.Result == pb.AuthenticateResponse_RESULT_SUCCESS
}

// A TokenExchanger represents a connection to the Authnd TokenExchanger service.
// For optimal network performance, use a single TokenExchanger for all your application's requests.
// TokenExchanger are safe for concurrent use by multiple goroutines.
type TokenExchanger interface {
	// ExchangeToken sends a token exchange request to Authnd and processes the response.
	// Use NewRequest to create a Request containing the credentials to be authenticated.
	// Returns an error in the event of an unexpected error (such as a network interruption).
	// The response indicates an token exchange success/failure and includes a signed JWT token.
	ExchangeToken(ctx context.Context, request *ExchangeTokenRequest, opts ...RequestOption) (*ExchangeTokenResponse, error)
}

type tokenExchanger struct {
	twirpClient pb.TokenExchanger
	statter     stats.Client
}

// NewTokenExchanger creates and returns a TokenExchanger with the provided options, or an error if applying any of the options failed.
// If no options are provided, recommended options will be applied.
// For optimal network performance, use a single TokenExchanger for all your application's requests.
// TokenExchangers are safe for concurrent use by multiple goroutines.
func NewTokenExchanger(addr string, catalogService string, opts ...Option) (TokenExchanger, error) {
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
		serviceDimensionName:        "TokenExchanger",
	})

	httpClient := clientOpts.CustomHTTPClient
	if httpClient == nil {
		httpClient = createHTTPClient(clientOpts.HTTPClientOptions, statter)
	}

	// always set the catalog service header and user agent
	httpClient = middleware.ApplyCatalogService(httpClient, catalogService)
	httpClient = middleware.ApplyUserAgent(httpClient, Version)

	return &tokenExchanger{
		pb.NewTokenExchangerProtobufClient(addr, httpClient),
		statter,
	}, nil
}

func (t *tokenExchanger) ExchangeToken(ctx context.Context, request *ExchangeTokenRequest, opts ...RequestOption) (*ExchangeTokenResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "ExchangeToken"}
	defer func() {
		duration := time.Since(start)
		t.statter.Counter(requestsMetric, tags, 1)
		t.statter.DistributionMs(timingMetric, tags, duration)
	}()

	for _, opt := range opts {
		ctx = opt(ctx)
	}

	protobufRequest := &pb.ExchangeTokenRequest{
		Credentials: request.Credentials.Credentials,
	}
	response, err := t.twirpClient.ExchangeToken(ctx, protobufRequest)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return &ExchangeTokenResponse{
		Result: response.Result,
		Token:  response.Token,
	}, nil
}
