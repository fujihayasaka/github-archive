package api

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/authenticator"
	"github.com/github/authnd/internal/api/middleware"
	"github.com/github/authnd/internal/api/mux"
	apiTesting "github.com/github/authnd/internal/api/testing"
	"github.com/github/authnd/internal/common/feature"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-stats"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewHandler_Twirp_NoMethod(t *testing.T) {
	ts := newTestServer(t)

	client := ts.Client()
	path := ts.URL + pb.AuthenticatorPathPrefix
	req, err := http.NewRequest("POST", path, nil)
	require.NoError(t, err)
	signRequest(req, apiTesting.TestHMACKey)
	setRequiredHeaders(req)
	res, err := client.Do(req)
	require.NoError(t, err)
	require.Equal(t, http.StatusNotFound, res.StatusCode)
}

func TestNewHandler_TwirpSigner(t *testing.T) {
	ts := newTestServer(t)

	client := ts.Client()
	path := ts.URL + pb.AuthenticatorPathPrefix
	req, err := http.NewRequest("POST", path, nil)
	require.NoError(t, err)
	signRequest(req, apiTesting.TestHMACKey)
	setRequiredHeaders(req)
	res, err := client.Do(req)
	require.NoError(t, err)
	require.Equal(t, http.StatusNotFound, res.StatusCode)
}

func TestNewHandler_TwirpSignerNotSignedRespondsNotAuthorized(t *testing.T) {
	if commonTesting.IsProximaMode() {
		t.Skip("skipping test in proxima mode")
	}

	ts := newTestServer(t)

	client := ts.Client()
	path := ts.URL + pb.AuthenticatorPathPrefix
	req, err := http.NewRequest("POST", path, nil)
	require.NoError(t, err)
	setRequiredHeaders(req)
	res, err := client.Do(req)
	require.NoError(t, err)
	require.Equal(t, http.StatusUnauthorized, res.StatusCode)
}

func TestNoCatalogService(t *testing.T) {
	ts := newTestServer(t)

	client := ts.Client()
	path := ts.URL + pb.AuthenticatorPathPrefix

	req, err := http.NewRequest("POST", path, nil)
	require.NoError(t, err)
	req.Header.Add("User-Agent", "test-user-agent")
	signRequest(req, apiTesting.TestHMACKey)

	res, err := client.Do(req)
	require.NoError(t, err)
	require.Equal(t, http.StatusBadRequest, res.StatusCode)

	body, err := io.ReadAll(res.Body)
	require.NoError(t, err)
	require.Equal(t, "both the 'Catalog-Service' and 'User-Agent' headers must be provided", string(body))
}

func TestNoUserAgent(t *testing.T) {
	ts := newTestServer(t)

	client := ts.Client()
	path := ts.URL + pb.AuthenticatorPathPrefix

	req, err := http.NewRequest("POST", path, nil)
	require.NoError(t, err)
	req.Header.Add("Catalog-Service", "test-catalog-service")
	req.Header.Set("User-Agent", "") // Go will set a User-Agent if we don't, but setting to "" is equivalent to not providing one.
	signRequest(req, apiTesting.TestHMACKey)

	res, err := client.Do(req)
	require.NoError(t, err)
	require.Equal(t, http.StatusBadRequest, res.StatusCode)

	body, err := io.ReadAll(res.Body)
	require.NoError(t, err)
	require.Equal(t, "both the 'Catalog-Service' and 'User-Agent' headers must be provided", string(body))
}

type middlewareHandler struct {
	a *assert.Assertions
}

func (h middlewareHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	h.a.True(feature.Enabled(ctx, "invisibility"))
	h.a.True(feature.Enabled(ctx, "flight"))
	h.a.False(feature.Enabled(ctx, "super-strength"))
	w.WriteHeader(http.StatusOK)
}

func (h middlewareHandler) PathPrefix() string {
	return "/mwtest"
}

func TestFeatureMiddleware(t *testing.T) {
	ts := newTestServer(t, middlewareHandler{assert.New(t)})
	path := ts.URL + "/mwtest"

	features := []string{"invisibility", "flight"}
	serialized, err := json.Marshal(features)
	require.NoError(t, err)
	encoded := base64.StdEncoding.EncodeToString(serialized)

	client := ts.Client()
	req, err := http.NewRequest("POST", path, nil)
	require.NoError(t, err)
	req.Header.Add("Catalog-Service", "test-catalog-service")
	req.Header.Set("User-Agent", "test-user-agent") // Go will set a User-Agent if we don't, but setting to "" is equivalent to not providing one.
	req.Header.Set("X-GitHub-Features", encoded)
	signRequest(req, apiTesting.TestHMACKey)

	res, err := client.Do(req)
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, res.StatusCode)
}

// signRequest implement internal signing
func signRequest(req *http.Request, hmacKey string) {
	req.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(hmacKey).String())
}

func setRequiredHeaders(req *http.Request) {
	req.Header.Add("Catalog-Service", "test-catalog-service")

	if commonTesting.IsProximaMode() {
		req.Header.Add("X-GitHub-Tenant-ID", strconv.Itoa(int(testfixtures.DefaultBusiness.ID)))
		req.Header.Add("X-GitHub-Tenant-Shortcode", testfixtures.DefaultBusiness.Shortcode)
	}
}

func newTestServer(t *testing.T, handlers ...mux.PrefixHandler) *httptest.Server {
	store := testfixtures.AuthStore
	hooks := middleware.NewServerHooks(apiTesting.TestApiConfig(), log.NewNullLogger(), stats.NullStatter, apiTesting.TestHMACKey)
	authnServer := authenticator.NewAuthenticatorServer(
		store,
		hooks,
		false,
	)
	handler := mux.NewMux(log.NewNullLogger(), stats.NullStatter, false, nil, append(
		[]mux.PrefixHandler{authnServer},
		handlers...,
	)...)

	ts := httptest.NewServer(handler)
	t.Cleanup(ts.Close)
	return ts
}

func TestLoginPassword(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, false)
	apiTesting.TestLoginPassword(t, client)
}

func TestSSHPublicKey(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, false)
	apiTesting.TestSSHPublicKey(t, client)
}

func TestAccessToken(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, false)
	apiTesting.TestAccessTokens(t, client)
	apiTesting.TestPrATTokens(t, client)
}

func TestAccessTokenInEnterprise(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, true)
	apiTesting.TestPrATTokens(t, client)
}

func TestUnsupportedCredentialTypesInEnterprise(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, true)
	apiTesting.TestEnterpriseNotSupported(t, client)
}

func TestSignedAuthToken(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, false)
	apiTesting.TestSignedAuthToken(t, client)
}

func TestServerToServerTokens(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, false)
	apiTesting.TestServerToServerTokens(t, client)
}

func TestUnknownCredentialType(t *testing.T) {
	client := newAuthenticatorWithInMemoryStore(t, false)
	apiTesting.TestUnknownCredentialType(t, client)
}

func newAuthenticatorWithInMemoryStore(t *testing.T, isEnterpriseServer bool) pb.Authenticator {
	t.Helper()
	authenticator := apiTesting.TestAuthenticator(t, testfixtures.AuthStore, isEnterpriseServer)
	return authenticator
}

// OAuthStore represents a mock implementation of dotcom.AuthStore that
// overrides the OAuth behavior for testing purposes.
type OAuthStore struct {
	FindOAuthAccessByHashFn func(ctx context.Context, token string) (*models.OAuthAccessWithTokenContext, error)
	store.Store
}

// FindOAuthAccessByHash returns a *dotcom.OAuthAccess
// for the matching hashed token.
func (l *OAuthStore) FindOAuthAccessByHash(ctx context.Context, token string) (*models.OAuthAccessWithTokenContext, error) {
	return l.FindOAuthAccessByHashFn(ctx, token)
}
