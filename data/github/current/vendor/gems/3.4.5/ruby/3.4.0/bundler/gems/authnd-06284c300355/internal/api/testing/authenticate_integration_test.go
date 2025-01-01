//go:build db

package testing

import (
	"context"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSSHKey(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// test success
	resp, err := AuthenticateWithRequestOptions(authenticator, client.NewSSHKeyCredentials(testfixtures.MonalisaPublicKey.Key))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing an attribute
	actorId, err := resp.GetIntAttribute("actor.id")
	require.NoError(t, err)
	require.Equal(t, testfixtures.MonalisaPublicKey.UserID.Int64, actorId)

	// validate returned attributes bag
	expectedBagOfAttributes := map[string]interface{}{
		"actor.id":        testfixtures.MonalisaPublicKey.UserID.Int64,
		"actor.type":      "User",
		"credential.id":   testfixtures.MonalisaPublicKey.ID,
		"credential.type": "SSHPublicKey",
	}
	require.Equal(t, expectedBagOfAttributes, resp.Attributes)
}

func TestOAuth(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// malformed token
	resp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials("notatoken"))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID, resp.Result)

	// token not found
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials("ghp_123456789630a57ca953ad3817a6310fc6af"))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND, resp.Result)

	// test unknown user
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.UnknownUserToken))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)

	// test expired app token
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredGitAppOauthToken))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test expired PAT
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredPersonalAccessToken))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test success
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.MonalisaToken))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing an attribute
	actorId, err := resp.GetIntAttribute("actor.id")
	require.NoError(t, err)
	require.Equal(t, testfixtures.MonalisaPublicKey.UserID.Int64, actorId)

	// validate returned attributes bag
	expectedBagOfAttributes := map[string]interface{}{
		"actor.id":                        testfixtures.MonalisaOAuthAccess.UserID,
		"actor.type":                      "User",
		"user.login":                      testfixtures.MonalisaUser.Login,
		"credential.id":                   testfixtures.MonalisaOAuthAccess.ID,
		"credential.type":                 "PersonalAccessToken",
		"organization.sso_authorized_ids": []int64{testfixtures.MonalisaOAuthSSOAuthorization.OrganizationID},
	}

	// handle expiration and issued at separately
	createdAt, ok := resp.Attributes["credential.created_at_utc"].(time.Time)
	expiresAt, ok := resp.Attributes["credential.expires_at_utc"].(time.Time)
	issuedAt, ok := resp.Attributes["credential.issued_at_utc"].(time.Time)
	require.True(t, ok, resp.Attributes["credential.created_at_utc"])
	require.True(t, ok, resp.Attributes["credential.expires_at_utc"])
	require.True(t, ok, resp.Attributes["credential.issued_at_utc"])

	delete(resp.Attributes, "credential.created_at_utc")
	delete(resp.Attributes, "credential.expires_at_utc")
	delete(resp.Attributes, "credential.issued_at_utc")
	assert.Equal(t, testfixtures.MonalisaOAuthAccess.CreatedAt.Time.Unix(), createdAt.Unix())
	assert.Equal(t, testfixtures.MonalisaOAuthAccess.ExpiresAt.Int64, expiresAt.Unix())
	assert.Equal(t, testfixtures.MonalisaOAuthAccess.LastIssuedAt.Time.Unix(), issuedAt.Unix())
	require.Equal(t, expectedBagOfAttributes, resp.Attributes)

	// ensure authnd client recognizes this token wasn't issued by authnd
	assert.False(t, client.IsAuthndToken(testfixtures.MonalisaToken))
	assert.False(t, client.IsChecksumValid(testfixtures.MonalisaToken))
}

func TestSAT(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// test bad token format
	resp, err := AuthenticateWithRequestOptions(authenticator, client.NewSignedAuthTokenCredentials("badformat", "orascope"))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID, resp.Result)

	// test not found
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewSignedAuthTokenCredentials(testfixtures.UnknownUserSAT, "MyScope"))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)

	// test expired sat
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewSignedAuthTokenCredentials(testfixtures.MonalisaExpiredSAT, "expired"))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test impersonated session SAT (not supported)
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewSignedAuthTokenCredentials(testfixtures.ImpersonatedSessionValidSAT, "MyScope"))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED, resp.Result)

	// test wrong scope supplied
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewSignedAuthTokenCredentials(testfixtures.MonalisaValidSAT2, "wrongscopesorry"))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID, resp.Result)

	// valid session-independent SAT
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewSignedAuthTokenCredentials(testfixtures.MonalisaValidSAT2, "test"))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// validate returned attributes bag
	expectedBagOfAttributes := map[string]interface{}{
		"actor.id":                  testfixtures.MonalisaOAuthAccess.UserID,
		"user.login":                testfixtures.MonalisaUser.Login,
		"actor.type":                "User",
		"credential.type":           "SignedAuthToken",
		"credential.version":        int64(3),
		"credential.expires_at_utc": testfixtures.MonalisaValidSAT2ExpiresAt,
		"credential.payload:key1":   "val1",
		"credential.payload:key2":   int64(42),
	}
	require.Equal(t, expectedBagOfAttributes, resp.Attributes)

	// ensure authnd client recognizes this token wasn't issued by authnd
	assert.False(t, client.IsAuthndToken(testfixtures.MonalisaValidSAT2))
	assert.False(t, client.IsChecksumValid(testfixtures.MonalisaValidSAT2))

	// valid session-dependent SAT
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewSignedAuthTokenCredentials(testfixtures.MonalisaValidSessionSAT, "test"))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing an attribute
	actorId, err := resp.GetIntAttribute("actor.id")
	require.NoError(t, err)
	require.Equal(t, testfixtures.MonalisaPublicKey.UserID.Int64, actorId)

	// validate returned attributes bag
	expectedBagOfAttributes = map[string]interface{}{
		"actor.id":                  testfixtures.MonalisaOAuthAccess.UserID,
		"user.login":                testfixtures.MonalisaUser.Login,
		"actor.type":                "User",
		"credential.type":           "SignedAuthToken",
		"credential.version":        int64(3),
		"credential.expires_at_utc": testfixtures.MonalisaValidSessionSATExpiresAt,
		"session.id":                testfixtures.MonalisaValidUserSession.ID,
		"credential.payload:key1":   "session-val1",
		"credential.payload:key2":   int64(43),
	}
	require.Equal(t, expectedBagOfAttributes, resp.Attributes)

	// ensure authnd client recognizes this token wasn't issued by authnd
	assert.False(t, client.IsAuthndToken(testfixtures.MonalisaValidSessionSAT))
	assert.False(t, client.IsChecksumValid(testfixtures.MonalisaValidSessionSAT))
}

func TestLegacyPrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// test not found
	resp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.NotFoundLegacyProgramaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND, resp.Result)

	// test expired token
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test revoked token
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, resp.Result)

	// test success
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing attributes
	actorId, err := resp.GetIntAttribute("actor.id")
	require.NoError(t, err)
	require.Equal(t, testfixtures.MonalisaUser.ID, actorId)

	accessId, err := resp.GetIntAttribute("access.id")
	require.NoError(t, err)
	require.Equal(t, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.AccessID), accessId)

	// validate returned attributes bag
	expectedBagOfAttributes := map[string]interface{}{
		"actor.id":        testfixtures.MonalisaUser.ID,
		"actor.type":      "User",
		"access.id":       int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.AccessID),
		"credential.id":   int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID),
		"credential.type": pb.ProgrammaticAccessTokenType,
		"user.login":      testfixtures.UserOne.Login, // not monalisauser because of weird token mismatch text
	}

	// handle issued at separately
	issuedAt, ok := resp.Attributes["credential.issued_at_utc"].(time.Time)
	require.True(t, ok, resp.Attributes["credential.issued_at_utc"])

	delete(resp.Attributes, "credential.issued_at_utc")
	assert.InDelta(t, testfixtures.MonalisaLegacyProgrammaticAccessToken.IssuedAt.Unix(), issuedAt.Unix(), 1)

	require.Equal(t, expectedBagOfAttributes, resp.Attributes)

	// ensure authnd client recognizes this token was issued by authnd
	assert.True(t, client.IsAuthndToken(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value))
	assert.True(t, client.IsChecksumValid(testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value))
}

func TestPrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server := CreateTestAuthenticationServer(t, store, false)
	authenticator, err := client.NewAuthenticator(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// test user not found
	resp, err := AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.NilUserToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)

	// test user suspended
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.SuspendedUserToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED, resp.Result)

	// test token not found
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.NotFoundToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND, resp.Result)

	// test expired token
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.ExpiredToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test revoked token
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.RevokedToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, resp.Result)

	// test success
	resp, err = AuthenticateWithRequestOptions(authenticator, client.NewAccessTokenCredentials(testfixtures.MonalisaToken1.Value))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing attributes
	actorId, err := resp.GetIntAttribute("actor.id")
	require.NoError(t, err)
	require.Equal(t, testfixtures.MonalisaUser.ID, actorId)

	accessId, err := resp.GetIntAttribute("access.id")
	require.NoError(t, err)
	require.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID), accessId)

	// validate returned attributes bag
	expectedBagOfAttributes := map[string]interface{}{
		"actor.id":        testfixtures.MonalisaUser.ID,
		"actor.type":      "User",
		"access.id":       int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID),
		"credential.id":   int64(testfixtures.MonalisaProgrammaticAccessToken.ID),
		"credential.type": pb.ProgrammaticAccessTokenType,
		"user.login":      testfixtures.MonalisaUser.Login,
	}

	// handle expiration and issued at separately
	expiresAt, ok := resp.Attributes["credential.expires_at_utc"].(time.Time)
	issuedAt, ok := resp.Attributes["credential.issued_at_utc"].(time.Time)
	require.True(t, ok, resp.Attributes["credential.expires_at_utc"])
	require.True(t, ok, resp.Attributes["credential.issued_at_utc"])

	delete(resp.Attributes, "credential.expires_at_utc")
	delete(resp.Attributes, "credential.issued_at_utc")
	assert.InDelta(t, testfixtures.SixDaysFromNow.Unix(), expiresAt.Unix(), 1)
	assert.InDelta(t, testfixtures.MonalisaProgrammaticAccessToken.IssuedAt.Unix(), issuedAt.Unix(), 1)
	// check the rest of the attributes
	require.Equal(t, expectedBagOfAttributes, resp.Attributes)

	// ensure authnd client recognizes this token was issued by authnd
	assert.True(t, client.IsAuthndToken(testfixtures.MonalisaToken1.Value))
	assert.True(t, client.IsChecksumValid(testfixtures.MonalisaToken1.Value))
}

func AuthenticateWithRequestOptions(authenticator client.Authenticator, creds *client.Credentials) (*client.AuthenticateResponse, error) {
	if commonTesting.IsProximaMode() {
		return authenticator.Authenticate(context.Background(), client.NewAuthenticateRequest(creds),
			client.WithTenant(int(testfixtures.DefaultBusiness.ID), testfixtures.DefaultBusiness.Shortcode))
	}

	return authenticator.Authenticate(context.Background(), client.NewAuthenticateRequest(creds))
}
