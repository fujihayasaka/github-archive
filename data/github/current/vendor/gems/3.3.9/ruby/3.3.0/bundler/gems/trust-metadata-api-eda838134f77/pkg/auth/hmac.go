package auth

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/bodyhmac"
)

// this enum represents the accepted domains and associated IDs
const (
	npmDomainID = iota + 1
	githubDomainID
)

// domainNameToID maps domain names to the corresponding domain IDs
var domainNameToID = map[string]uint32{"npm": npmDomainID, "github": githubDomainID}

var ErrNoServiceClient = errors.New("no service client found in context")

const HMACClientHeader = "X-HMAC-Client-Id"

// ClientConfig represents the authentication configuration for a client
// that can make requests to the API
type ClientConfig struct {
	ClientID string   `json:"clientId"`
	Domain   string   `json:"domain"`
	Keys     []string `json:"keys"`
}

func (config *ClientConfig) Valid() error {
	if config.ClientID == "" {
		return errors.New("client ID cannot be empty")
	}
	if config.Domain == "" {
		return errors.New("domain name cannot be empty")
	}
	if config.Keys == nil || len(config.Keys) == 0 {
		return errors.New("keys slice cannot be empty")
	}
	for _, key := range config.Keys {
		if key == "" {
			return errors.New("key cannot be empty")
		}
	}
	return nil
}

// ServiceClient represents a client making a request to the API. It is used after authentication
type ServiceClient struct {
	ClientID string
	Domain   string
	DomainID uint32
}

// FromGitHub returns true if the ServiceClient represents a client request from GitHub
func (client *ServiceClient) FromGitHub() bool {
	return client.DomainID == githubDomainID
}

// FromNpm returns true if the ServiceClient represents a client request from npm
func (client *ServiceClient) FromNpm() bool {
	return client.DomainID == npmDomainID
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

// mapConfigsToClients maps the clientID to a ServiceClient struct, which has
// details we want (client, domain) and filters out sensitive details (auth keys), so it
// can be stored in the request context for later use
func mapConfigsToClients(cfg []ClientConfig) map[string]ServiceClient {
	clientByID := make(map[string]ServiceClient, len(cfg))
	for _, c := range cfg {
		if domainID, ok := domainNameToID[c.Domain]; ok {
			clientByID[c.ClientID] = ServiceClient{
				ClientID: c.ClientID,
				Domain:   c.Domain,
				DomainID: domainID,
			}
		}
	}
	// TODO: add a DomainNameToID mapping check to ClientConfig.Valid()
	// so misconfigurations are caught on boot and not on request
	return clientByID
}

// makeSetClientMiddleware creates middleware that gets the client ID from the HMAC client header
// and sets the current client in the request context
func makeSetClientMiddleware(cfg []ClientConfig) Middleware {
	clientsByID := mapConfigsToClients(cfg)

	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			id := r.Header.Get(HMACClientHeader)

			currentClient, ok := clientsByID[id]
			// if the client ID provided in the HMAC client header does not have a map entry,
			// it is not supported and the request should be rejected
			if !ok {
				log.Error("unauthorized client ID")
				w.WriteHeader(http.StatusUnauthorized)
				return
			}

			r = r.WithContext(WithCurrentClient(r.Context(), currentClient))
			next.ServeHTTP(w, r)
		}
		return http.HandlerFunc(fn)
	}
}

// makeFetchKeys returns a fetch keys function that uses the clientKeys map
// passed as an argument
func makeFetchKeys(cfg []ClientConfig) FetchKeysFunc {
	// create a map of client ID to client configs
	// this will be used to look up the keys for a given client ID
	// in the function returned below
	configByClientID := make(map[string]ClientConfig, len(cfg))
	for _, c := range cfg {
		configByClientID[c.ClientID] = c
	}

	// return a function that will fetch the client ID from the HMAC client header
	// and return the keys associated with that client ID by looking up the client ID
	// in the configByClientID map
	return func(r *http.Request) ([]string, error) {
		clientID := r.Header.Get(HMACClientHeader)
		log.Debug("header: %s", kvp.String(HMACClientHeader, clientID))
		if clientID == "" {
			return nil, fmt.Errorf("missing client header")
		}

		authCfg, ok := configByClientID[clientID]
		if !ok {
			return nil, fmt.Errorf("unauthorized access")
		}

		return authCfg.Keys, nil
	}
}

// NewAuthenticationMiddleware configures HMAC authentication if enabled
func NewAuthenticationMiddleware(logger log.Logger, cfg []ClientConfig) (Middleware, error) {
	// check that authentication configurations are provided
	if cfg == nil || len(cfg) == 0 {
		return nil, errors.New("HMAC keys must always be provided. Please provide an HMAC key")
	}

	// create a body HMAC verifier using the authConfigByClientID map
	verifier := bodyhmac.Verifier{
		Logger:    logger,
		FetchKeys: makeFetchKeys(cfg),
	}

	// create the HMAC middleware handler that verifies the incoming body HMAC header
	// and then sets the current client in the request context
	setClientMiddleware := makeSetClientMiddleware(cfg)
	hamcHandler := func(next http.Handler) http.Handler {
		return verifier.Handler(setClientMiddleware(next))
	}

	return hamcHandler, nil
}
