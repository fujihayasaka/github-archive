package client

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	"github.com/pkg/errors"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type mockTwirpTokenExchanger struct {
	err error
}

func (ma mockTwirpTokenExchanger) ExchangeToken(context.Context, *pb.ExchangeTokenRequest) (*pb.ExchangeTokenResponse, error) {
	if ma.err != nil {
		return nil, ma.err
	}
	return &pb.ExchangeTokenResponse{Result: pb.AuthenticateResponse_RESULT_SUCCESS}, nil
}

func TestNewTokenExchangerEmptyAddr(t *testing.T) {
	_, err := NewTokenExchanger("", "something")
	require.Error(t, err)
	require.Equal(t, "must provide a non empty addr", err.Error())
}

func TestNewTokenExchangerEmptyCatalogService(t *testing.T) {
	_, err := NewTokenExchanger("localhost.test", "")
	require.Error(t, err)
	require.Equal(t, "must provide a non empty catalogService", err.Error())
}

func TestNewTokenExchangerNoOptions(t *testing.T) {
	_, err := NewTokenExchanger("localhost.test", "catalog_service")
	require.NoError(t, err)
}

func TestNewTokenExchangerWithCustomOption(t *testing.T) {
	someErr := errors.New("some_error")
	option := func(*options) error {
		return someErr
	}
	_, err := NewTokenExchanger("localhost.test", "catalog_service", option)
	require.ErrorIs(t, err, someErr)
}

func TestExchangeTokenRequestIDForwarding(t *testing.T) {
	var receivedRequestID string
	server := httptest.NewServer(requestid.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedRequestID = requestid.GetGitHubRequestID(r.Context())
	})))
	defer server.Close()
	ctx := requestid.WithGitHubRequestID(context.Background(), "the-request-id")

	TokenExchanger, err := NewTokenExchanger(server.URL, "catalog_service")
	require.NoError(t, err)
	_, e := TokenExchanger.ExchangeToken(ctx, NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.NoError(t, e)

	require.Equal(t, "the-request-id", receivedRequestID)
}

func TestExchangeTokenWithoutRequestIDForwarding(t *testing.T) {
	var receivedRequestID string
	server := httptest.NewServer(requestid.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedRequestID = requestid.GetGitHubRequestID(r.Context())
	})))
	defer server.Close()
	ctx := requestid.WithGitHubRequestID(context.Background(), "the-request-id")

	TokenExchanger, err := NewTokenExchanger(server.URL, "catalog_service", WithoutRequestIDForwarder())
	require.NoError(t, err)

	_, e := TokenExchanger.ExchangeToken(ctx, NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.NoError(t, e)

	// shouldn't equal the GitHub request ID set above (will be a uuid)
	require.NotEqual(t, "the-request-id", receivedRequestID)
}

func TestExchangeTokenUserAgentApplied(t *testing.T) {
	var receivedUserAgent string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedUserAgent = r.Header.Get("User-Agent")
	}))
	defer server.Close()

	TokenExchanger, err := NewTokenExchanger(server.URL, "catalog_service")
	require.NoError(t, err)

	_, e := TokenExchanger.ExchangeToken(context.Background(), NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.NoError(t, e)
	require.Equal(t, fmt.Sprintf("authnd-go/%s", Version), receivedUserAgent)
}

func TestExchangeTokenCatalogServiceApplied(t *testing.T) {
	var receivedCatalogService string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedCatalogService = r.Header.Get("Catalog-Service")
	}))
	defer server.Close()

	TokenExchanger, err := NewTokenExchanger(server.URL, "catalog_service")
	require.NoError(t, err)

	_, e := TokenExchanger.ExchangeToken(context.Background(), NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.NoError(t, e)
	require.Equal(t, "catalog_service", receivedCatalogService)
}

func TestExchangeTokenWithStatterOnError(t *testing.T) {
	mockAuth := &mockTwirpTokenExchanger{
		err: errors.New(""),
	}
	expectedTags := stats.Tags{
		"method": "ExchangeToken",
		"result": "twirp_client_error",
	}
	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)
	mockStatter.Mock.On("Counter", requestsMetric, expectedTags, int64(1)).Return()
	mockStatter.Mock.On("DistributionMs", timingMetric, expectedTags, mock.AnythingOfType("time.Duration")).Return()

	TokenExchanger := &tokenExchanger{
		mockAuth,
		&mockStatter,
	}
	_, e := TokenExchanger.ExchangeToken(context.Background(), NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.Error(t, e)
}

func TestExchangeTokenWithStatterOnSuccess(t *testing.T) {
	mockAuth := &mockTwirpTokenExchanger{}
	expectedTags := stats.Tags{
		"method": "ExchangeToken",
		"result": "RESULT_SUCCESS",
	}
	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)
	mockStatter.Mock.On("Counter", requestsMetric, expectedTags, int64(1)).Return()
	mockStatter.Mock.On("DistributionMs", timingMetric, expectedTags, mock.AnythingOfType("time.Duration")).Return()

	TokenExchanger := &tokenExchanger{
		mockAuth,
		&mockStatter,
	}
	_, e := TokenExchanger.ExchangeToken(context.Background(), NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.NoError(t, e)
}

func TestExchangeTokenWithCustomHTTPClient(t *testing.T) {
	customHttpClient := http.DefaultClient

	var receivedCatalogService string
	var receivedUserAgent string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedCatalogService = r.Header.Get("Catalog-Service")
		receivedUserAgent = r.Header.Get("User-Agent")
	}))
	defer server.Close()

	TokenExchanger, err := NewTokenExchanger(server.URL, "catalog_service", WithCustomHTTPClient(customHttpClient))
	require.NoError(t, err)

	_, e := TokenExchanger.ExchangeToken(context.Background(), NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.NoError(t, e)

	// test that we still set Catalog-Service and User-Agent when using a custom HTTP client
	require.Equal(t, "catalog_service", receivedCatalogService)
	require.Equal(t, fmt.Sprintf("authnd-go/%s", Version), receivedUserAgent)
}

func TestExchangeTokenWithCustomHTTPClientApplyMiddleware(t *testing.T) {
	theUserAgentValue := "some_user"
	customHttpClient := pb.HTTPClient(http.DefaultClient)
	customHttpClient = middleware.ApplyCatalogService(customHttpClient, theUserAgentValue)

	var receivedUserAgent string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedUserAgent = r.Header.Get("Catalog-Service")
	}))
	defer server.Close()

	TokenExchanger, err := NewTokenExchanger(server.URL, "catalog_service", WithCustomHTTPClient(customHttpClient))
	require.NoError(t, err)

	_, e := TokenExchanger.ExchangeToken(context.Background(), NewExchangeTokenRequest(NewAccessTokenCredentials("fake-token")))
	require.NoError(t, e)
	require.Equal(t, theUserAgentValue, receivedUserAgent)
}
