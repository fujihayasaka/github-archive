package auth

import (
	"context"
	"errors"
	"net/http"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/bodyhmac"
)

var ErrNoServiceClient = errors.New("no service client found in context")

const HMACClientHeader = "X-HMAC-Client-Id"

// HMACKeys represents a list of HMAC keys
type HMACKeys []string

func (keys *HMACKeys) Valid() error {
	if len(*keys) == 0 {
		return errors.New("HMAC keys must always be provided. Please provide an HMAC key")
	}
	return nil
}

// ServiceClient represents a client making a request to the API. It is used after authentication
type ServiceClient struct {
	ClientID string
}

// CurrentClientKey is the context key for storing the currently auth'd client
type ctxCurrentClientKey struct{}

type FetchKeysFunc = func(r *http.Request) ([]string, error)

type Middleware = func(next http.Handler) http.Handler

// withCurrentClient creates a new context with the ClientID set to the specified value.
// If ClientID already exists, it will be overwritten.
func WithCurrentClient(ctx context.Context, client ServiceClient) context.Context {
	return context.WithValue(ctx, ctxCurrentClientKey{}, client)
}

// GetCurrentClient retrieves the current ServiceClient object from the context if it exists
func GetCurrentClient(ctx context.Context) (ServiceClient, error) {
	client, ok := ctx.Value(ctxCurrentClientKey{}).(ServiceClient)
	if !ok {
		return ServiceClient{}, ErrNoServiceClient
	}
	return client, nil
}

// makeFetchKeys returns a fetch keys function that uses the clientKeys map
// passed as an argument
func makeFetchKeys(keys HMACKeys) FetchKeysFunc {
	// return a function that will fetch the client ID from the HMAC client header
	// and return the keys associated with that client ID by looking up the client ID
	// in the configByClientID map
	return func(_ *http.Request) ([]string, error) {
		return keys, nil
	}
}

// NewAuthenticationMiddleware configures HMAC authentication if enabled
func NewAuthenticationMiddleware(logger log.Logger, keys HMACKeys) (Middleware, error) {
	// check that authentication configurations are provided
	if len(keys) == 0 {
		return nil, errors.New("HMAC keys must always be provided. Please provide an HMAC key")
	}

	// create a body HMAC verifier using the authConfigByClientID map
	verifier := bodyhmac.Verifier{
		Logger:    logger,
		FetchKeys: makeFetchKeys(keys),
	}

	return verifier.Handler, nil
}
