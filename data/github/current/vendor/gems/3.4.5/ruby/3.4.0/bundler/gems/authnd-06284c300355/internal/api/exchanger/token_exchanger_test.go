package exchanger

import (
	"context"
	"crypto/ecdsa"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/authenticator"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"

	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var setupOnce sync.Once
var testPrivateKey *ecdsa.PrivateKey

// this test validates that all known authentication attributes have a corresponding
// claim defined in the client.ExchangeTokenClaims struct

func TestClaimsForAllKnownAttributes(t *testing.T) {
	typ := reflect.TypeOf(client.ExchangeTokenClaims{})
	jsonTags := make([]string, 0, typ.NumField())
	for i := 0; i < typ.NumField(); i++ {
		tag := typ.Field(i).Tag.Get("json")
		jt := strings.Split(tag, ",")[0] // remove the omitempty
		jsonTags = append(jsonTags, jt)
	}
	t.Log(jsonTags)

	for _, attr := range client.AllAttributes {
		switch attr {
		case client.CredentialIssuedAtAttribute, client.CredentialExpiresAtAttribute:
			// these attributes are represented by the default JWT claims (i.e. RegisteredClaims),
			// so we don't need to check for them in the custom claims.
		case client.CredentialPayloadAttribute, client.CredentialVersionAttribute, client.SessionIDAttribute:
			// attributes from SATs, which aren't supported by the token exchanger.
		case client.PublicKeyNotVerifiedAttribute:
			// attributes from SSH public keys, which aren't supported by the token exchanger.
		default:
			assert.Contains(t, jsonTags, attr, "missing claim for attribute %q", attr)
		}
	}
}

type testClaims map[string]any

func (tc testClaims) GetExpirationTime() (*jwt.NumericDate, error) { return nil, nil }
func (tc testClaims) GetIssuedAt() (*jwt.NumericDate, error)       { return nil, nil }
func (tc testClaims) GetNotBefore() (*jwt.NumericDate, error)      { return nil, nil }
func (tc testClaims) GetIssuer() (string, error)                   { return "", nil }
func (tc testClaims) GetSubject() (string, error)                  { return "", nil }
func (tc testClaims) GetAudience() (jwt.ClaimStrings, error)       { return nil, nil }

// test helper which takes client.ExchangeTokenClaims and returns a map of claims as serialized
// in the JWT token. this allows us to introspect the serialized JWT token and validate
// that expected claims are present.
func tokenClaimsToAttributeMap(t *testing.T, claims *client.ExchangeTokenClaims) map[string]any {
	hmac := "shhhhhhh"
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	require.NotNil(t, token)

	plaintext, err := token.SignedString([]byte(hmac))
	require.NoError(t, err)
	require.NotEmpty(t, plaintext)

	tc := new(testClaims)
	token2, err := jwt.ParseWithClaims(plaintext, tc, func(token *jwt.Token) (any, error) {
		return []byte(hmac), nil
	})
	require.NoError(t, err)
	require.NotNil(t, token2)
	require.NotNil(t, claims)

	return (map[string]any)(*tc)
}

func TestDynamicAttributes(t *testing.T) {
	t.Run("empty dynamic claims are omitted", func(t *testing.T) {
		tcm := tokenClaimsToAttributeMap(t, &client.ExchangeTokenClaims{})
		require.Empty(t, tcm)
	})

	t.Run("dynamic claims are inlined to the JWT", func(t *testing.T) {
		tcm := tokenClaimsToAttributeMap(t, &client.ExchangeTokenClaims{
			ExchangeTokenDynamicClaims: client.ExchangeTokenDynamicClaims{
				"key1": "value1",
				"key2": 2.0,
			},
		})

		dc, ok := tcm["dynamic_claims"]
		require.True(t, ok)
		assert.Equal(t, map[string]interface{}{
			"key1": "value1",
			"key2": 2.0,
		}, dc)
	})
}

func TestClaimsFromAttributes(t *testing.T) {
	assertDefaultClaims := func(t *testing.T, claims *client.ExchangeTokenClaims) {
		assert.NotEmpty(t, claims.ID)
		assert.Equal(t, "github/authnd", claims.Issuer)
		assert.WithinDuration(t, time.Now().UTC().Add(maxExpirationSeconds*time.Second), claims.ExpiresAt.Time, time.Second)
		assert.WithinDuration(t, time.Now().UTC().Add(-5*time.Second), claims.NotBefore.Time, time.Second)
	}

	t.Run("default claims", func(t *testing.T) {
		claims, err := claimsFromAttributes(nil)
		require.NoError(t, err)
		assertDefaultClaims(t, claims)
	})

	t.Run("expiration", func(t *testing.T) {
		for _, tc := range []struct {
			name                 string
			accessTokenExpiresAt time.Time
			jwtExpiresAt         time.Time
		}{
			{
				name:         "none",
				jwtExpiresAt: time.Now().UTC().Add(maxExpirationSeconds * time.Second),
			},
			{
				name:                 "outside JWT maximum",
				accessTokenExpiresAt: time.Now().UTC().Add(2 * maxExpirationSeconds * time.Second),
				jwtExpiresAt:         time.Now().UTC().Add(maxExpirationSeconds * time.Second),
			},
			{
				name:                 "less than JWT maximum",
				accessTokenExpiresAt: time.Now().UTC().Add((maxExpirationSeconds - 3) * time.Second),
				jwtExpiresAt:         time.Now().UTC().Add((maxExpirationSeconds - 3) * time.Second),
			},
		} {
			t.Run(tc.name, func(t *testing.T) {
				var attrs []*pb.Attribute
				if !tc.accessTokenExpiresAt.IsZero() {
					attrs = append(attrs, pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, tc.accessTokenExpiresAt))
				}
				claims, err := claimsFromAttributes(attrs)
				require.NoError(t, err)
				assert.WithinDuration(t, tc.jwtExpiresAt, claims.ExpiresAt.Time, time.Second)
			})
		}
	})

	t.Run("static claims", func(t *testing.T) {
		now := time.Now().UTC()
		claims, err := claimsFromAttributes([]*pb.Attribute{
			pb.NewInt64Attribute(client.ActorIDAttribute, 1),
			pb.NewInt64Attribute(client.CredentialIDAttribute, 2),
			pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
			pb.NewInt64Attribute(client.ApplicationIDAttribute, 4),
			pb.NewInt64Attribute(client.InstallationIDAttribute, 5),
			pb.NewInt64Attribute(client.InstallationTargetIDAttribute, 6),
			pb.NewStringAttribute(client.InstallationTargetTypeAttribute, "installation-target-type"),
			pb.NewInt64Attribute(client.ScopedInstallationIDAttribute, 7),
			pb.NewInt64Attribute(client.ApplicationOwnerIDAttribute, 8),
			pb.NewStringAttribute(client.ApplicationOwnerTypeAttribute, "owner-type"),
			pb.NewStringAttribute(client.ActorTypeAttribute, "actor-type"),
			pb.NewStringAttribute(client.UserLoginAttribute, "user-login"),
			pb.NewStringAttribute(client.CredentialTypeAttribute, "credential-type"),
			pb.NewStringAttribute(client.TokenSuffixAttribute, "token-suffix"),
			pb.NewStringAttribute(client.ApplicationTypeAttribute, "application-type"),
			pb.NewStringAttribute(client.ApplicationClientIDAttribute, "client-id"),
			pb.NewStringAttribute(client.ScopedInstallationTypeAttribute, "scoped-installation-type"),
			pb.NewStringListAttribute(client.CredentialScopesAttribute, "scope1", "scope2"),
			pb.NewTimeAttribute(client.CredentialCreatedAtAttribute, now),
			pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, 98, 99),
		})
		require.NoError(t, err)

		assertDefaultClaims(t, claims)
		// zero out default claims prior to comparisont to avoid direct comparisons of time.Time
		claims.RegisteredClaims = jwt.RegisteredClaims{}

		assert.Equal(t, &client.ExchangeTokenClaims{
			ActorID:                      testhelpers.IntTokenClaim(1),
			CredentialID:                 testhelpers.IntTokenClaim(2),
			AccessID:                     testhelpers.IntTokenClaim(3),
			ApplicationID:                testhelpers.IntTokenClaim(4),
			InstallationID:               testhelpers.IntTokenClaim(5),
			InstallationTargetID:         testhelpers.IntTokenClaim(6),
			InstallationTargetType:       testhelpers.StringTokenClaim("installation-target-type"),
			ScopedInstallationID:         testhelpers.IntTokenClaim(7),
			ActorType:                    testhelpers.StringTokenClaim("actor-type"),
			UserLogin:                    testhelpers.StringTokenClaim("user-login"),
			CredentialType:               testhelpers.StringTokenClaim("credential-type"),
			TokenSuffix:                  testhelpers.StringTokenClaim("token-suffix"),
			ApplicationType:              testhelpers.StringTokenClaim("application-type"),
			ApplicationClientID:          testhelpers.StringTokenClaim("client-id"),
			ApplicationOwnerID:           testhelpers.IntTokenClaim(8),
			ApplicationOwnerType:         testhelpers.StringTokenClaim("owner-type"),
			ScopedInstallationType:       testhelpers.StringTokenClaim("scoped-installation-type"),
			CredentialScopes:             []string{"scope1", "scope2"},
			CredentialCreatedAtAttribute: jwt.NewNumericDate(now),
			OrganizationSSOAuthorizedIDs: []uint64{98, 99},
		}, claims)
	})
}

type testAuthenticator struct {
	result pb.AuthenticateResponse_Result
}

func (a *testAuthenticator) Authenticate(ctx context.Context, request *pb.AuthenticateRequest) (*pb.AuthenticateResponse, error) {
	return &pb.AuthenticateResponse{
		Result: a.result,
	}, nil
}

func TestTokenExchanger_AllFailureResults(t *testing.T) {
	for ix, result := range pb.AuthenticateResponse_Result_name {
		if result == "RESULT_SUCCESS" {
			continue
		}

		t.Run(result, func(t *testing.T) {
			exchanger := &TokenExchanger{
				authnr: &testAuthenticator{
					result: pb.AuthenticateResponse_Result(ix),
				},
			}

			resp, err := exchanger.ExchangeToken(context.Background(), &pb.ExchangeTokenRequest{
				Credentials: pb.NewAccessTokenCredential("invalid"),
			})
			require.NoError(t, err)

			require.Equal(t, pb.AuthenticateResponse_Result(ix), resp.Result)
		})
	}
}

func TestTokenExchanger_AccessToken(t *testing.T) {
	tests := map[string]struct {
		token  string
		result pb.AuthenticateResponse_Result
		claims *client.ExchangeTokenClaims
	}{
		"valid oauth access token": {
			token:  testfixtures.MonalisaToken,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
					IssuedAt:  jwt.NewNumericDate(testfixtures.MonalisaOAuthAccess.LastIssuedAt.Time),
				},
				ActorID:                      testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:                    testhelpers.StringTokenClaim("User"),
				UserLogin:                    testhelpers.StringTokenClaim(testfixtures.MonalisaUser.Login),
				CredentialID:                 testhelpers.IntTokenClaim(testfixtures.MonalisaOAuthAccess.ID),
				CredentialType:               testhelpers.StringTokenClaim("PersonalAccessToken"),
				CredentialCreatedAtAttribute: jwt.NewNumericDate(testfixtures.MonalisaOAuthAccess.CreatedAt.Time),
				OrganizationSSOAuthorizedIDs: []uint64{uint64(testfixtures.MonalisaOAuthSSOAuthorization.OrganizationID)},
			},
		},
		"oauth token with gist scope": {
			token:  testfixtures.MonalisaGistToken,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
				},
				ActorID:                      testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:                    testhelpers.StringTokenClaim("User"),
				UserLogin:                    testhelpers.StringTokenClaim(testfixtures.MonalisaUser.Login),
				CredentialID:                 testhelpers.IntTokenClaim(testfixtures.MonalisaGistOAuthAccess.ID),
				CredentialType:               testhelpers.StringTokenClaim("PersonalAccessToken"),
				CredentialCreatedAtAttribute: jwt.NewNumericDate(testfixtures.MonalisaGistOAuthAccess.CreatedAt.Time),
				CredentialScopes:             []string{"gist"},
			},
		},
		"token not found": {
			token:  "ghp_859d21d07aed3b5ee810656a93e8b5a3812a",
			result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND,
		},
		"unknown user": {
			token:  testfixtures.UnknownUserToken,
			result: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			exchanger, key := createTestTokenExchanger(t)
			ctx := commonTesting.NewLoggerContext(t)
			resp, err := exchanger.ExchangeToken(ctx, &pb.ExchangeTokenRequest{
				Credentials: pb.NewAccessTokenCredential(tc.token),
			})
			require.NoError(t, err)

			require.Equal(t, tc.result, resp.Result)
			if tc.claims != nil {
				assertClaims(t, key, tc.claims, resp.Token)
			}
		})
	}
}

func TestTokenExchanger_LegacyPrATToken(t *testing.T) {
	tests := map[string]struct {
		token  string
		result pb.AuthenticateResponse_Result
		claims *client.ExchangeTokenClaims
	}{
		"valid prat token": {
			token:  testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
					IssuedAt:  jwt.NewNumericDate(testfixtures.MonalisaLegacyProgrammaticAccessToken.IssuedAt),
				},
				ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:      testhelpers.StringTokenClaim("User"),
				UserLogin:      testhelpers.StringTokenClaim(testfixtures.UserOne.Login), // mismatched user ids in token
				AccessID:       testhelpers.IntTokenClaim(testfixtures.MonalisaLegacyProgrammaticAccessToken.AccessID),
				CredentialID:   testhelpers.IntTokenClaim(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID),
				CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
			},
		},
		"token not found": {
			token:  testfixtures.NotFoundToken.Value,
			result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND,
		},
		"valid prat token with extra attributes": {
			token:  testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributesPlainText.Value,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
					IssuedAt:  jwt.NewNumericDate(testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.IssuedAt),
				},
				ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:      testhelpers.StringTokenClaim("User"),
				UserLogin:      testhelpers.StringTokenClaim(testfixtures.UserOne.Login), // mismatched user ids in token
				AccessID:       testhelpers.IntTokenClaim(testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.AccessID),
				CredentialID:   testhelpers.IntTokenClaim(testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.ID),
				CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
				ExchangeTokenDynamicClaims: map[string]interface{}{
					testfixtures.BoolTrueAttributeId:  true,
					testfixtures.BoolFalseAttributeId: false,
					testfixtures.DoubleAttributeId:    1.1,
				},
			},
		},
		"valid prat token future expire": {
			token:  testfixtures.FutureExpiredLegacyProgrammaticAccessTokenPlainText.Value,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
					IssuedAt:  jwt.NewNumericDate(testfixtures.FutureExpiredLegacyProgrammaticAccessToken.IssuedAt),
				},
				ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:      testhelpers.StringTokenClaim("User"),
				UserLogin:      testhelpers.StringTokenClaim(testfixtures.UserOne.Login), // mismatched user ids in token
				AccessID:       testhelpers.IntTokenClaim(testfixtures.FutureExpiredLegacyProgrammaticAccessToken.AccessID),
				CredentialID:   testhelpers.IntTokenClaim(testfixtures.FutureExpiredLegacyProgrammaticAccessToken.ID),
				CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
			},
		},
		"token expired": {
			token:  testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value,
			result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED,
		},
		"token revoked": {
			token:  testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value,
			result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			exchanger, key := createTestTokenExchanger(t)
			ctx := commonTesting.NewLoggerContext(t)
			resp, err := exchanger.ExchangeToken(ctx, &pb.ExchangeTokenRequest{
				Credentials: pb.NewAccessTokenCredential(tc.token),
			})
			require.NoError(t, err)

			require.Equal(t, tc.result, resp.Result)
			if tc.claims != nil {
				assertClaims(t, key, tc.claims, resp.Token)
			}
		})
	}

}

func TestTokenExchanger_PrATToken(t *testing.T) {
	tests := map[string]struct {
		token  string
		result pb.AuthenticateResponse_Result
		claims *client.ExchangeTokenClaims
	}{
		"valid prat token": {
			token:  testfixtures.MonalisaToken1.Value,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
					IssuedAt:  jwt.NewNumericDate(testfixtures.MonalisaProgrammaticAccessToken.IssuedAt),
				},
				ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:      testhelpers.StringTokenClaim("User"),
				UserLogin:      testhelpers.StringTokenClaim(testfixtures.MonalisaUser.Login),
				AccessID:       testhelpers.IntTokenClaim(testfixtures.MonalisaProgrammaticAccessToken.AccessID),
				CredentialID:   testhelpers.IntTokenClaim(testfixtures.MonalisaProgrammaticAccessToken.ID),
				CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
			},
		},
		"token not found": {
			token:  testfixtures.NotFoundToken.Value,
			result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND,
		},
		"valid prat token with extra attributes": {
			token:  testfixtures.MonalisaTokenExtraAttributes.Value,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
					IssuedAt:  jwt.NewNumericDate(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.IssuedAt),
				},
				ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:      testhelpers.StringTokenClaim("User"),
				UserLogin:      testhelpers.StringTokenClaim(testfixtures.MonalisaUser.Login), // mismatched user ids in token
				AccessID:       testhelpers.IntTokenClaim(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.AccessID),
				CredentialID:   testhelpers.IntTokenClaim(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.ID),
				CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
				ExchangeTokenDynamicClaims: map[string]interface{}{
					testfixtures.BoolTrueAttributeId:  true,
					testfixtures.BoolFalseAttributeId: false,
					testfixtures.DoubleAttributeId:    1.1,
				},
			},
		},
		"valid prat token future expire": {
			token:  testfixtures.FutureExpiredToken.Value,
			result: pb.AuthenticateResponse_RESULT_SUCCESS,
			claims: &client.ExchangeTokenClaims{
				RegisteredClaims: jwt.RegisteredClaims{
					ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(1 * time.Minute)),
					IssuedAt:  jwt.NewNumericDate(testfixtures.FutureExpiredProgrammaticAccessToken.IssuedAt),
				},
				ActorID:        testhelpers.IntTokenClaim(testfixtures.MonalisaUser.ID),
				ActorType:      testhelpers.StringTokenClaim("User"),
				UserLogin:      testhelpers.StringTokenClaim(testfixtures.MonalisaUser.Login),
				AccessID:       testhelpers.IntTokenClaim(testfixtures.FutureExpiredProgrammaticAccessToken.AccessID),
				CredentialID:   testhelpers.IntTokenClaim(testfixtures.FutureExpiredProgrammaticAccessToken.ID),
				CredentialType: testhelpers.StringTokenClaim(pb.ProgrammaticAccessTokenType),
			},
		},
		"token expired": {
			token:  testfixtures.ExpiredToken.Value,
			result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED,
		},
		"token revoked": {
			token:  testfixtures.RevokedToken.Value,
			result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED,
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			exchanger, key := createTestTokenExchanger(t)
			ctx := commonTesting.NewLoggerContext(t)
			resp, err := exchanger.ExchangeToken(ctx, &pb.ExchangeTokenRequest{
				Credentials: pb.NewAccessTokenCredential(tc.token),
			})
			require.NoError(t, err)

			require.Equal(t, tc.result, resp.Result)
			if tc.claims != nil {
				assertClaims(t, key, tc.claims, resp.Token)
			}
		})
	}
}

func createTestTokenExchanger(t *testing.T) (*TokenExchanger, *ecdsa.PublicKey) {
	t.Helper()

	setupOnce.Do(func() {
		// avoid doing this multiple times because it makes our tests much slower
		testPrivateKey = crypto.MustCreateECDSAPrivateKey()
	})

	dataStore := testfixtures.AuthStore
	return &TokenExchanger{
		authnr:     authenticator.NewAuthenticator(dataStore, false),
		signingKey: testPrivateKey,
	}, &testPrivateKey.PublicKey
}

func assertClaims(t *testing.T, key *ecdsa.PublicKey, expected *client.ExchangeTokenClaims, token string) {
	t.Helper()

	require.NotEmpty(t, token)

	tk, err := jwt.ParseWithClaims(token, &client.ExchangeTokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		return key, nil
	})
	require.NoError(t, err)

	claims, ok := tk.Claims.(*client.ExchangeTokenClaims)
	require.True(t, ok)

	// manually verify 'exp'
	if expected.RegisteredClaims.ExpiresAt != nil {
		assert.WithinDuration(t, expected.RegisteredClaims.ExpiresAt.Time, claims.ExpiresAt.Time, time.Second, "exp")
		claims.ExpiresAt, expected.RegisteredClaims.ExpiresAt = nil, nil
	} else {
		assert.Nil(t, claims.ExpiresAt, "exp")
	}

	// manually verify 'iat'
	if expected.RegisteredClaims.IssuedAt != nil {
		assert.WithinDuration(t, expected.RegisteredClaims.IssuedAt.Time, claims.IssuedAt.Time, time.Second, "iat")
		claims.IssuedAt, expected.RegisteredClaims.IssuedAt = nil, nil
	} else {
		assert.Nil(t, claims.IssuedAt, "iat")
	}

	// manually verify 'nbf'
	assert.WithinDuration(t, time.Now().UTC().Add(-5*time.Second), claims.NotBefore.Time, time.Second, "nbf")
	claims.NotBefore = nil

	assert.NotEmpty(t, claims.ID)
	assert.Equal(t, "github/authnd", claims.Issuer)
	claims.ID, claims.Issuer = "", ""

	assert.Equal(t, expected, claims)
}
