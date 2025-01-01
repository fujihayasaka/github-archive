package client

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	"github.com/pkg/errors"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type mockTwirpIdentityManager struct {
	err error
}

func (ma mockTwirpIdentityManager) IssueIdentityToken(context.Context, *pb.IssueIdentityTokenRequest) (*pb.IssueIdentityTokenResponse, error) {
	if ma.err != nil {
		return nil, ma.err
	}
	return &pb.IssueIdentityTokenResponse{Token: "identity-token"}, nil
}

func (ma mockTwirpIdentityManager) DiscoveryDocument(ctx context.Context, req *pb.DiscoveryDocumentRequest) (*pb.DiscoveryDocumentResponse, error) {
	if ma.err != nil {
		return nil, ma.err
	}
	return &pb.DiscoveryDocumentResponse{}, nil
}

func (m mockTwirpIdentityManager) Jwks(ctx context.Context, req *pb.JwksRequest) (*pb.JwksResponse, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &pb.JwksResponse{}, nil
}

func TestNewIssueIdentityTokenEmptyAddr(t *testing.T) {
	_, err := NewIdentityManager("", "something")
	require.Error(t, err)
	require.Equal(t, "must provide a non empty addr", err.Error())
}

func TestNewIssueIdentityTokenEmptyCatalogService(t *testing.T) {
	_, err := NewIdentityManager("localhost.test", "")
	require.Error(t, err)
	require.Equal(t, "must provide a non empty catalogService", err.Error())
}

func TestNewIssueIdentityTokenNoOptions(t *testing.T) {
	_, err := NewIdentityManager("localhost.test", "catalog_service")
	require.NoError(t, err)
}

func TestIdentityManagerRequestIDForwarding(t *testing.T) {
	var receivedRequestID string
	server := httptest.NewServer(requestid.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedRequestID = requestid.GetGitHubRequestID(r.Context())
	})))
	defer server.Close()
	ctx := requestid.WithGitHubRequestID(context.Background(), "the-request-id")

	identityManager, err := NewIdentityManager(server.URL, "catalog_service")
	require.NoError(t, err)
	_, e := identityManager.IssueIdentityToken(ctx, NewIssueIdentityTokenRequest(&pb.Claims{
		Sub: "sub",
		Aud: "aud",
		Act: &pb.ActorClaims{
			Sub: "act.sub",
		},
	}))
	require.NoError(t, e)

	require.Equal(t, "the-request-id", receivedRequestID)
}

func TestIssueIdentityTokenUserAgentApplied(t *testing.T) {
	var receivedUserAgent string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedUserAgent = r.Header.Get("User-Agent")
	}))
	defer server.Close()

	identityManager, err := NewIdentityManager(server.URL, "catalog_service")
	require.NoError(t, err)

	_, e := identityManager.IssueIdentityToken(context.Background(), NewIssueIdentityTokenRequest(&pb.Claims{
		Sub: "sub",
		Aud: "aud",
		Act: &pb.ActorClaims{
			Sub: "act.sub",
		},
	}))
	require.NoError(t, e)
	require.Equal(t, fmt.Sprintf("authnd-go/%s", Version), receivedUserAgent)
}

func TestIssueIdentityTokenCatalogServiceApplied(t *testing.T) {
	var receivedCatalogService string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedCatalogService = r.Header.Get("Catalog-Service")
	}))
	defer server.Close()

	identityManager, err := NewIdentityManager(server.URL, "catalog_service")
	require.NoError(t, err)

	_, e := identityManager.IssueIdentityToken(context.Background(), NewIssueIdentityTokenRequest(&pb.Claims{
		Sub: "sub",
		Aud: "aud",
		Act: &pb.ActorClaims{
			Sub: "act.sub",
		},
	}))
	require.NoError(t, e)
	require.Equal(t, "catalog_service", receivedCatalogService)
}

func TestIssueIdentityTokenWithStatterOnError(t *testing.T) {
	mockAuth := &mockTwirpIdentityManager{
		err: errors.New(""),
	}
	expectedTags := stats.Tags{
		"method": "IssueIdentityToken",
		"result": "twirp_client_error",
	}
	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)
	mockStatter.Mock.On("Counter", requestsMetric, expectedTags, int64(1)).Return()
	mockStatter.Mock.On("DistributionMs", timingMetric, expectedTags, mock.AnythingOfType("time.Duration")).Return()

	identityManager := &identityManager{
		mockAuth,
		&mockStatter,
	}
	_, e := identityManager.IssueIdentityToken(context.Background(), NewIssueIdentityTokenRequest(&pb.Claims{
		Sub: "sub",
		Aud: "aud",
		Act: &pb.ActorClaims{
			Sub: "act.sub",
		},
	}))
	require.Error(t, e)
}

func TestIssueIdentityTokenWithStatterOnSuccess(t *testing.T) {
	mockAuth := &mockTwirpIdentityManager{}
	expectedTags := stats.Tags{
		"method": "IssueIdentityToken",
	}
	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)
	mockStatter.Mock.On("Counter", requestsMetric, expectedTags, int64(1)).Return()
	mockStatter.Mock.On("DistributionMs", timingMetric, expectedTags, mock.AnythingOfType("time.Duration")).Return()

	identityManager := &identityManager{
		mockAuth,
		&mockStatter,
	}
	_, e := identityManager.IssueIdentityToken(context.Background(), NewIssueIdentityTokenRequest(&pb.Claims{
		Sub: "sub",
		Aud: "aud",
		Act: &pb.ActorClaims{
			Sub: "act.sub",
		},
	}))
	require.NoError(t, e)
}
