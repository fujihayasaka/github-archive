//go:build db

package testing

import (
	"context"
	"crypto/ecdsa"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func extractClaims(t *testing.T, publicKey *ecdsa.PublicKey, plaintext string) *client.ExchangeTokenClaims {
	t.Helper()

	require.NotEmpty(t, plaintext)
	claims := new(client.ExchangeTokenClaims)
	token, err := jwt.ParseWithClaims(plaintext, claims, func(token *jwt.Token) (any, error) {
		return publicKey, nil
	})
	require.NoError(t, err)
	require.NotNil(t, token)
	require.NotNil(t, claims)

	return claims
}

func TestTokenExchange_OAuth(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server, publicKey := CreateTestTokenExchangerServer(t, store, false)
	tokenExchanger, err := client.NewTokenExchanger(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// malformed token
	resp, err := ExchangeTokenWithRequestOptions(tokenExchanger, "notatoken")
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID, resp.Result)

	// token not found
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, "ghp_123456789630a57ca953ad3817a6310fc6af")
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND, resp.Result)

	// test unknown user
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, testfixtures.UnknownUserToken)
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)

	// test expired app token
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, testfixtures.ExpiredGitAppOauthToken)
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test expired PAT
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, testfixtures.ExpiredPersonalAccessToken)
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test success
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, testfixtures.MonalisaToken)
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing an attribute
	claims := extractClaims(t, publicKey, resp.Token)
	require.NotNil(t, claims.ActorID)
	require.Equal(t, testfixtures.MonalisaPublicKey.UserID.Int64, int64(*claims.ActorID))

	// handle expiration and issued at separately
	require.NotNil(t, claims.ExpiresAt)
	assert.WithinDuration(t, time.Now().UTC().Add(60*time.Second), claims.ExpiresAt.Time, 1*time.Second)
	require.NotNil(t, claims.IssuedAt)
	assert.InDelta(t, testfixtures.MonalisaOAuthAccess.LastIssuedAt.Time.Unix(), claims.IssuedAt.Unix(), 1)
	require.NotNil(t, claims.CredentialCreatedAtAttribute)
	assert.Equal(t, testfixtures.MonalisaOAuthAccess.CreatedAt.Time.Unix(), claims.CredentialCreatedAtAttribute.Unix())
	assert.WithinDuration(t, time.Now().UTC().Add(-5*time.Second), claims.NotBefore.Time, 1*time.Second)
	claims.ExpiresAt, claims.IssuedAt, claims.NotBefore, claims.CredentialCreatedAtAttribute = nil, nil, nil, nil

	assert.NotEmpty(t, claims.ID)
	claims.ID = ""

	// validate returned attributes bag
	expectedClaims := &client.ExchangeTokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer: "github/authnd",
		},
		ActorID:                      testhelpers.IntTokenClaim(testfixtures.MonalisaOAuthAccess.UserID),
		ActorType:                    testhelpers.StringTokenClaim("User"),
		UserLogin:                    testhelpers.StringTokenClaim(testfixtures.MonalisaUser.Login),
		CredentialID:                 testhelpers.IntTokenClaim(testfixtures.MonalisaOAuthAccess.ID),
		CredentialType:               testhelpers.StringTokenClaim("PersonalAccessToken"),
		OrganizationSSOAuthorizedIDs: []uint64{uint64(testfixtures.MonalisaOAuthSSOAuthorization.OrganizationID)},
	}
	require.Equal(t, expectedClaims, claims)
}

func TestTokenExchange_LegacyPrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server, publicKey := CreateTestTokenExchangerServer(t, store, false)
	tokenExchanger, err := client.NewTokenExchanger(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// test not found
	resp, err := ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.NotFoundLegacyProgramaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND, resp.Result)

	// test expired token
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test revoked token
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, resp.Result)

	// test success
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing attributes
	claims := extractClaims(t, publicKey, resp.Token)
	require.NotNil(t, claims.ActorID)
	require.Equal(t, testfixtures.MonalisaUser.ID, int64(*claims.ActorID))

	require.NotNil(t, claims.AccessID)
	require.Equal(t, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.AccessID), int64(*claims.AccessID))

	// handle expiration and issued at separately
	require.NotNil(t, claims.ExpiresAt)
	assert.WithinDuration(t, time.Now().UTC().Add(60*time.Second), claims.ExpiresAt.Time, 1*time.Second)
	require.NotNil(t, claims.IssuedAt)
	assert.InDelta(t, testfixtures.MonalisaLegacyProgrammaticAccessToken.IssuedAt.Unix(), claims.IssuedAt.Time.Unix(), 1)
	assert.WithinDuration(t, time.Now().UTC().Add(-5*time.Second), claims.NotBefore.Time, 1*time.Second)
	claims.ExpiresAt, claims.IssuedAt, claims.NotBefore = nil, nil, nil

	assert.NotEmpty(t, claims.ID)
	claims.ID = ""

	// validate returned attributes bag
	expectedClaims := &client.ExchangeTokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer: "github/authnd",
		},
		ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
		ActorType:      testhelpers.StringTokenClaim("User"),
		UserLogin:      testhelpers.StringTokenClaim(testfixtures.UserOne.Login),
		AccessID:       testhelpers.IntTokenClaim(testfixtures.MonalisaLegacyProgrammaticAccessToken.AccessID),
		CredentialID:   testhelpers.IntTokenClaim(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID),
		CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
	}
	require.Equal(t, expectedClaims, claims)
}

func TestTokenExchange_PrATToken(t *testing.T) {
	store := testfixtures.CreateTestDatabaseStore(t, true)
	server, publicKey := CreateTestTokenExchangerServer(t, store, false)
	tokenExchanger, err := client.NewTokenExchanger(server.URL, TestCatalogServiceName, client.WithHMACKey(TestHMACKey))
	require.NoError(t, err)

	// test user not found
	resp, err := ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.NilUserToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN, resp.Result)

	// test user suspended
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.SuspendedUserToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED, resp.Result)

	// test token not found
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.NotFoundToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND, resp.Result)

	// test expired token
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.ExpiredToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED, resp.Result)

	// test revoked token
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.RevokedToken.Value))
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
	require.Equal(t, pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED, resp.Result)

	// test success
	resp, err = ExchangeTokenWithRequestOptions(tokenExchanger, (testfixtures.MonalisaToken1.Value))
	require.NoError(t, err)
	require.True(t, resp.Succeeded())

	// test parsing attributes
	claims := extractClaims(t, publicKey, resp.Token)
	require.NotNil(t, claims.ActorID)
	assert.Equal(t, testfixtures.MonalisaUser.ID, int64(*claims.ActorID))

	require.NotNil(t, claims.AccessID)
	require.Equal(t, int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID), int64(*claims.AccessID))

	// handle expiration and issued at separately
	require.NotNil(t, claims.ExpiresAt)
	assert.WithinDuration(t, time.Now().UTC().Add(60*time.Second), claims.ExpiresAt.Time, 1*time.Second)
	require.NotNil(t, claims.IssuedAt)
	assert.InDelta(t, testfixtures.MonalisaProgrammaticAccessToken.IssuedAt.Unix(), claims.IssuedAt.Time.Unix(), 1)
	assert.WithinDuration(t, time.Now().UTC().Add(-5*time.Second), claims.NotBefore.Time, 1*time.Second)
	claims.ExpiresAt, claims.IssuedAt, claims.NotBefore = nil, nil, nil

	assert.NotEmpty(t, claims.ID)
	claims.ID = ""

	// validate returned attributes bag
	expectedClaims := &client.ExchangeTokenClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer: "github/authnd",
		},
		ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
		ActorType:      testhelpers.StringTokenClaim("User"),
		UserLogin:      testhelpers.StringTokenClaim(testfixtures.MonalisaUser.Login),
		AccessID:       testhelpers.IntTokenClaim(testfixtures.MonalisaProgrammaticAccessToken.AccessID),
		CredentialID:   testhelpers.IntTokenClaim(testfixtures.MonalisaProgrammaticAccessToken.ID),
		CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
	}
	require.Equal(t, expectedClaims, claims)
}

func ExchangeTokenWithRequestOptions(tokenExchanger client.TokenExchanger, token string) (*client.ExchangeTokenResponse, error) {
	if commonTesting.IsProximaMode() {
		return tokenExchanger.ExchangeToken(context.Background(), client.NewExchangeTokenRequest(client.NewAccessTokenCredentials(token)),
			client.WithTenant(int(testfixtures.DefaultBusiness.ID), testfixtures.DefaultBusiness.Shortcode))
	}

	return tokenExchanger.ExchangeToken(context.Background(), client.NewExchangeTokenRequest(client.NewAccessTokenCredentials(token)))
}
