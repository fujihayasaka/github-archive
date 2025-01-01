//go:build db && proxima

package testing

import (
	"context"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestServerErrorIfMissingTenantIdContextHeader(t *testing.T) {
	client := TestAuthenticator(t, testfixtures.AuthStore, false)
	TestMissingTenantIdContextHeader(t, client)
}

func TestErrorIfMissingTenantHeadersInProxima(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	resp, err := authenticator.Authenticate(context.Background(), client.NewAuthenticateRequest(client.NewSSHKeyCredentials(testfixtures.MonalisaPublicKey.Key)))
	require.Error(t, err)
	if e, ok := err.(twirp.Error); ok {
		require.Equal(t, e.Code(), twirp.Internal)
	} else {
		require.Fail(t, "expected twirp error", err)
	}
	require.Nil(t, resp)
}

func TestTenantHeadersAcceptedInProxima(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	resp, err := AuthenticateWithRequestOptions(authenticator, client.NewSSHKeyCredentials(testfixtures.MonalisaPublicKey.Key))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())
}

// test relies on SeedTables setting default `business_id` of 12345 on all seeded users
func TestUserLookupTenantScoping(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	t.Run("wrong tenant", func(t *testing.T) {
		resp, err := authenticator.Authenticate(context.Background(),
			client.NewAuthenticateRequest(client.NewAccessTokenCredentials(testfixtures.MonalisaToken1.Value)),
			client.WithTenant(9999, "zyxwvu"))
		require.NoError(t, err)
		require.False(t, resp.Succeeded())
		require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)
	})

	t.Run("valid tenant with ID and Shortcode", func(t *testing.T) {
		resp, err := authenticator.Authenticate(context.Background(),
			client.NewAuthenticateRequest(client.NewAccessTokenCredentials(testfixtures.MonalisaToken1.Value)),
			client.WithTenant(int(testfixtures.DefaultBusiness.ID), testfixtures.DefaultBusiness.Shortcode))
		require.NoError(t, err)
		require.True(t, resp.Succeeded())
		require.Equal(t, pb.AuthenticateResponse_RESULT_SUCCESS, resp.Result)
	})

	t.Run("valid tenant with slug", func(t *testing.T) {
		resp, err := authenticator.Authenticate(context.Background(),
			client.NewAuthenticateRequest(client.NewAccessTokenCredentials(testfixtures.MonalisaToken1.Value)),
			client.WithTenantSlug(testfixtures.DefaultBusiness.Slug))
		require.NoError(t, err)
		require.True(t, resp.Succeeded())
		require.Equal(t, pb.AuthenticateResponse_RESULT_SUCCESS, resp.Result)
	})
}

// test relies on SeedTables setting default fingerprint suffix of `_test-tenant` on all seeded keys
func TestPublicKeyLookupTenantScoping(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	t.Run("wrong tenant", func(t *testing.T) {
		resp, err := authenticator.Authenticate(context.Background(), client.NewAuthenticateRequest(client.NewSSHKeyCredentials(testfixtures.MonalisaPublicKey.Key)), client.WithTenant(9999, "zyxwvu"))
		require.NoError(t, err)
		require.False(t, resp.Succeeded())
		require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_NOT_FOUND, resp.Result)
	})

	t.Run("valid tenant with ID and Shortcode", func(t *testing.T) {
		resp, err := authenticator.Authenticate(context.Background(),
			client.NewAuthenticateRequest(client.NewSSHKeyCredentials(testfixtures.MonalisaPublicKey.Key)),
			client.WithTenant(int(testfixtures.DefaultBusiness.ID), testfixtures.DefaultBusiness.Shortcode))
		require.NoError(t, err)
		require.True(t, resp.Succeeded())
		require.Equal(t, pb.AuthenticateResponse_RESULT_SUCCESS, resp.Result)
	})

	t.Run("valid tenant with Slug", func(t *testing.T) {
		resp, err := authenticator.Authenticate(context.Background(),
			client.NewAuthenticateRequest(client.NewSSHKeyCredentials(testfixtures.MonalisaPublicKey.Key)),
			client.WithTenantSlug(testfixtures.DefaultBusiness.Slug))
		require.NoError(t, err)
		require.True(t, resp.Succeeded())
		require.Equal(t, pb.AuthenticateResponse_RESULT_SUCCESS, resp.Result)
	})
}
