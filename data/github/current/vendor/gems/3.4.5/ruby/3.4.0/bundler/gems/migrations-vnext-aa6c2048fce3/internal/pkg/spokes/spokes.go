// Package spokes provides a wrapper around the Spokes API, allowing queries for object existence
// and handling authentication, TLS configuration, and request validation.
package spokes

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net/http"

	"github.com/github/go-auth/hmac"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
)

// ServiceName should be your app's name
const ServiceName = "migration-vnext"

// BuildVersion should be set to the current commit SHA
var BuildVersion string

// Client defines an interface for querying object existence
type Client interface {
	OIDExists(ctx context.Context, repoID uint64, oid string) (bool, error)
	OIDsExist(ctx context.Context, repoID uint64, oids []string) (map[string]bool, error)
}

// spokesClient is the implementation of Client
type spokesClient struct {
	spokesURL     string
	objectsClient objects.ObjectsAPI
}

// NewSpokesClient initializes a new Spokes API client using a properly configured HTTP client
func NewSpokesClient(spokesURL, clientCert, clientKey, caChain, hmacKey string) (Client, error) {
	httpClient, err := NewSpokesHTTPClient(clientCert, clientKey, caChain, hmacKey)
	if err != nil {
		return nil, fmt.Errorf("failed to create NewSpokesHTTPClient: %w", err)
	}

	return &spokesClient{
		spokesURL:     spokesURL,
		objectsClient: objects.NewObjectsAPIProtobufClient(spokesURL, httpClient),
	}, nil
}

// OIDExists checks if a single object exists in the repository
func (s *spokesClient) OIDExists(ctx context.Context, repoID uint64, oid string) (bool, error) {
	result, err := s.OIDsExist(ctx, repoID, []string{oid})
	if err != nil {
		return false, err
	}
	return result[oid], nil
}

// OIDsExist checks if multiple objects exist in the repository
func (s *spokesClient) OIDsExist(ctx context.Context, repoID uint64, oids []string) (map[string]bool, error) {
	if len(oids) == 0 {
		return nil, errors.New("oids list cannot be empty")
	}

	// Construct the repository reference using ID
	repository := &types.Repository{
		Type: types.Repository_TYPE_REPOSITORY,
		Id:   repoID,
	}

	// Create selectors for each OID
	selectorsList := make([]*selectors.ObjectSelector, len(oids))
	for i, oid := range oids {
		selectorsList[i] = &selectors.ObjectSelector{
			Object: &selectors.ObjectSelector_ById{
				ById: &types.ObjectID{Id: oid},
			},
		}
	}

	reqCtx := &types.RequestContext{
		QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_NO_DELAY}

	// Create a ReadObjectsRequest using the correct constructor
	req := &objects.ReadObjectsRequest{
		Repository:     repository,
		RequestContext: reqCtx,
		Selectors:      selectorsList,
	}

	// Call ReadObjects API
	resp, err := s.objectsClient.ReadObjects(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to check object existence: %w", err)
	}

	// Prepare results map
	existsMap := make(map[string]bool, len(oids))

	// Mark all objects as false initially
	for _, oid := range oids {
		existsMap[oid] = false
	}

	// Update map if objects exist
	for _, obj := range resp.GetObjects() {
		if obj != nil {
			objErr := obj.GetErrorObject()
			if objErr != nil {
				continue
			}

			existsMap[obj.Object.Oid.Id] = true
		}
	}

	return existsMap, nil
}

// NewSpokesHTTPClient creates an HTTP client with proper TLS and authentication headers.
func NewSpokesHTTPClient(clientCert, clientKey, caChain, hmacKey string) (*http.Client, error) {
	tlsConfig, err := setupSpokesTLSConfig(clientCert, clientKey, caChain)
	if err != nil {
		return nil, fmt.Errorf("failed to Setup Spokes TLSConfig : %w", err)
	}

	// Create an HTTP Transport with TLS settings
	transport := &http.Transport{
		TLSClientConfig:   tlsConfig,
		ForceAttemptHTTP2: true,
	}

	// Create an HTTP client and modify it to set the required headers
	client := &http.Client{Transport: transport}

	// Wrap client with a function that injects headers
	return withHeaders(client, hmacKey), nil
}

// withHeaders is a helper function that injects required headers into requests.
func withHeaders(client *http.Client, hmacKey string) *http.Client {
	baseTransport := client.Transport

	if baseTransport == nil {
		baseTransport = http.DefaultTransport
	}

	client.Transport = roundTripperFunc(func(req *http.Request) (*http.Response, error) {
		// Set User-Agent
		req.Header.Set("User-Agent", fmt.Sprintf("%s/%s", ServiceName, BuildVersion))

		// Set HMAC authentication header
		req.Header.Set("Request-HMAC", hmac.NewRequestHMAC(hmacKey).String())

		// Perform the request
		return baseTransport.RoundTrip(req)
	})

	return client
}

type roundTripperFunc func(*http.Request) (*http.Response, error)

func (f roundTripperFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

// setupSpokesTLSConfig configures TLS settings
func setupSpokesTLSConfig(clientCert, clientKey, caChain string) (*tls.Config, error) {
	config := &tls.Config{
		MinVersion: tls.VersionTLS12,
	}

	if clientCert != "" && clientKey != "" {
		cert, err := tls.X509KeyPair([]byte(clientCert), []byte(clientKey))
		if err != nil {
			return nil, err
		}
		config.Certificates = []tls.Certificate{cert}
	}

	if caChain != "" {
		caPool, err := x509.SystemCertPool()
		if err != nil {
			return nil, err
		}
		if !caPool.AppendCertsFromPEM([]byte(caChain)) {
			return nil, errors.New("failed to configure spokesd CA")
		}
		config.RootCAs = caPool
	}

	return config, nil
}
