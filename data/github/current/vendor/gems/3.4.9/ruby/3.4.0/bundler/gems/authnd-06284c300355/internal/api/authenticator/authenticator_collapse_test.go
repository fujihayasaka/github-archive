package authenticator

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/github/authnd/internal/common/tokens"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	"github.com/twitchtv/twirp"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

const concurrentRequests = 20

func TestAuthenticator_CollapsibleRequest(t *testing.T) {
	authenticators := map[string]*Authenticator{
		"dotcom":     createTestAuthenticator(t),
		"enterprise": createTestEnterpriseAuthenticator(t),
	}
	for _, tc := range []struct {
		name        string
		credentials *pb.Credentials
		expectedKey string
		collapsible bool
	}{
		{
			name: "legacy PAT",
			credentials: pb.NewAccessTokenCredential(
				testfixtures.MonalisaToken,
			),
			collapsible: true,
			expectedKey: fmt.Sprintf("oauth_access:%s", tokens.Hash(testfixtures.MonalisaToken)),
		},
		{
			name:        "PAT v2",
			credentials: pb.NewAccessTokenCredential(testfixtures.MonalisaToken1.Value),
			collapsible: true,
			expectedKey: fmt.Sprintf("prat:%s", tokens.Hash(testfixtures.MonalisaToken1.Value)),
		},
		{
			name:        "basic auth",
			credentials: pb.NewLoginPasswordCredential(testfixtures.MonalisaUser.Login, "passworD1"),
			collapsible: false,
		},
		{
			name:        "public key",
			credentials: pb.NewSSHPublicKeyCredential(testfixtures.MonalisaPublicKey.Key),
			collapsible: false,
		},
		{
			name:        "signed auth token",
			credentials: pb.NewSignedAuthTokenCredential(testfixtures.MonalisaValidSAT, "test"),
			collapsible: false,
		},
	} {
		for env, authn := range authenticators {
			t.Run(fmt.Sprintf("%s in %s", tc.name, env), func(t *testing.T) {
				key, ok := authn.collapsibleRequest(tc.credentials)
				if tc.collapsible {
					assert.True(t, ok)
					assert.Equal(t, tc.expectedKey, key)
				} else {
					assert.False(t, ok)
					assert.Empty(t, key)
				}
			})
		}
	}
}

func TestAuthenticatorCollapse_AccessToken(t *testing.T) {
	tests := map[string]struct {
		token string
		err   error
		want  []*pb.Attribute
	}{
		"token not defined": {
			err: twirp.RequiredArgumentError("credentials.access_token.token"),
		},
		"valid oauth access token": {
			token: testfixtures.MonalisaToken,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaOAuthAccess.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "PersonalAccessToken"),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{testfixtures.MonalisaOAuthSSOAuthorization.OrganizationID}...),
				pb.NewTimeAttribute(client.CredentialCreatedAtAttribute, testfixtures.MonalisaOAuthAccess.CreatedAt.Time),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaOAuthAccess.LastIssuedAt.Time),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Unix(testfixtures.MonalisaOAuthAccess.ExpiresAt.Int64, 0)),
			},
		},
		"oauth token with gist scope": {
			token: testfixtures.MonalisaGistToken,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaGistOAuthAccess.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "PersonalAccessToken"),
				pb.NewStringListAttribute(client.CredentialScopesAttribute, []string{"gist"}...),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
				pb.NewTimeAttribute(client.CredentialCreatedAtAttribute, testfixtures.MonalisaGistOAuthAccess.CreatedAt.Time),
			},
		},
		"token not found": {
			token: "ghp_859d21d07aed3b5ee810656a93e8b5a3812a",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"unknown user": {
			token: testfixtures.UnknownUserToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			mockStatter := mocks.Client{}
			defer mockStatter.AssertExpectations(t)

			// tolerate other stats
			mockStatter.Mock.On("DistributionMs", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Maybe().Return()
			mockStatter.Mock.On("Counter", "authentication.oauth.result", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
			mockStatter.Mock.On("Histogram", "broadcaster.listeners", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
			mockStatter.Mock.On("Counter", "broadcaster.transmit_complete", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_closed_on_listen", stats.Tags{"collapsed": "false"}, int64(1)).Maybe().Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_cancelled", stats.Tags{"collapsed": "false"}, int64(1)).Maybe().Return()
			// check at least one request is broadcast and one request is collapsed
			mockStatter.Mock.On("Counter", "authenticate.collapse.complete", stats.Tags{"collapsed": "false"}, int64(1)).Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.complete", stats.Tags{"collapsed": "true"}, int64(1)).Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_error", mock.AnythingOfType("stats.Tags"), int64(1)).Maybe().Return()
			ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

			authenticator := createTestAuthenticator(t)

			var wg sync.WaitGroup
			ready := make(chan bool)
			for i := 0; i < concurrentRequests; i++ {
				wg.Add(1)
				go func(id int) {
					defer wg.Done()

					// wait for all goroutines to be spun up
					<-ready

					ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("request-%d", id))
					ctx = diagnostics.WithLogger(ctx, testhelpers.GetTestLogger())

					// authenticate
					credentials := pb.NewAccessTokenCredential(tc.token)
					got, err := authenticator.collapsibleAuthenticate(ctx, credentials)
					require.Equal(t, tc.err, err)
					testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
				}(i)
			}

			// release the hounds
			close(ready)

			wg.Wait()

			for ix, call := range mockStatter.Calls {
				t.Logf("call[%d]: %s(%v)", ix+1, call.Method, call.Arguments)
			}
		})
	}
}

func TestAuthenticatorCollapse_ProgrammaticAccessToken(t *testing.T) {
	tests := map[string]struct {
		token string
		err   error
		want  []*pb.Attribute
	}{
		"token not defined": {
			err: twirp.RequiredArgumentError("credentials.access_token.token"),
		},
		"valid prat token": {
			token: testfixtures.MonalisaToken1.Value,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID)),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessToken.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.SixDaysFromNow),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaProgrammaticAccessToken.IssuedAt),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
			},
		},
		"token not found": {
			token: testfixtures.NotFoundToken.Value,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"valid prat token with extra attributes": {
			token: testfixtures.MonalisaTokenExtraAttributes.Value,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.AccessID)),
				pb.NewBoolAttribute(testfixtures.BoolTrueAttributeId, true),
				pb.NewBoolAttribute(testfixtures.BoolFalseAttributeId, false),
				pb.NewDoubleAttribute(testfixtures.DoubleAttributeId, 1.1),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaProgrammaticAccessTokenExtraAttributes.IssuedAt),
			},
		},
		"valid prat token future expire": {
			token: testfixtures.FutureExpiredToken.Value,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FutureExpiredProgrammaticAccessToken.ID)),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.FutureExpiredProgrammaticAccessToken.AccessID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FutureExpirationTime),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.FutureExpiredProgrammaticAccessToken.IssuedAt),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
			},
		},
		"token expired": {
			token: testfixtures.ExpiredToken.Value,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"token revoked": {
			token: testfixtures.RevokedToken.Value,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			mockStatter := mocks.Client{}
			defer mockStatter.AssertExpectations(t)

			// tolerate other stats
			mockStatter.Mock.On("DistributionMs", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Maybe().Return()
			mockStatter.Mock.On("Counter", "authentication.mint.result", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
			mockStatter.Mock.On("Counter", "authentication.mint.patv2_user_lookup_result", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
			mockStatter.Mock.On("Histogram", "broadcaster.listeners", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
			mockStatter.Mock.On("Counter", "broadcaster.transmit_complete", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_closed_on_listen", stats.Tags{"collapsed": "false"}, int64(1)).Maybe().Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_cancelled", stats.Tags{"collapsed": "false"}, int64(1)).Maybe().Return()
			// check at least one request is broadcast and one request is collapsed
			mockStatter.Mock.On("Counter", "authenticate.collapse.complete", stats.Tags{"collapsed": "false"}, int64(1)).Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.complete", stats.Tags{"collapsed": "true"}, int64(1)).Return()
			mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_error", mock.AnythingOfType("stats.Tags"), int64(1)).Maybe().Return()
			ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

			authenticator := createTestAuthenticator(t)

			var wg sync.WaitGroup
			ready := make(chan bool)
			for i := 0; i < concurrentRequests; i++ {
				wg.Add(1)
				go func(id int) {
					defer wg.Done()

					// wait for all goroutines to be spun up
					<-ready

					ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("request-%d", id))
					ctx = diagnostics.WithLogger(ctx, testhelpers.GetTestLogger())

					// authenticate
					credentials := pb.NewAccessTokenCredential(tc.token)
					got, err := authenticator.collapsibleAuthenticate(ctx, credentials)
					require.Equal(t, tc.err, err)
					testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
				}(i)
			}

			// release the hounds
			close(ready)

			wg.Wait()

			for ix, call := range mockStatter.Calls {
				t.Logf("call[%d]: %s(%v)", ix+1, call.Method, call.Arguments)
			}
		})
	}
}

func TestAuthenticatorCollapse_ResultsAreIsolated(t *testing.T) {
	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)

	// tolerate other stats
	mockStatter.Mock.On("DistributionMs", mock.AnythingOfType("string"), mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("time.Duration")).Maybe().Return()
	mockStatter.Mock.On("Counter", "authentication.oauth.result", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
	mockStatter.Mock.On("Counter", "authentication.mint.result", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
	mockStatter.Mock.On("Counter", "authentication.mint.patv2_user_lookup_result", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
	mockStatter.Mock.On("Histogram", "broadcaster.listeners", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
	mockStatter.Mock.On("Counter", "broadcaster.transmit_complete", mock.AnythingOfType("stats.Tags"), mock.AnythingOfType("int64")).Maybe().Return()
	mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_closed_on_listen", stats.Tags{"collapsed": "false"}, int64(1)).Maybe().Return()
	mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_cancelled", stats.Tags{"collapsed": "false"}, int64(1)).Maybe().Return()
	// check at least one request is broadcast and one request is collapsed
	mockStatter.Mock.On("Counter", "authenticate.collapse.complete", stats.Tags{"collapsed": "false"}, int64(1)).Return()
	mockStatter.Mock.On("Counter", "authenticate.collapse.complete", stats.Tags{"collapsed": "true"}, int64(1)).Return()
	mockStatter.Mock.On("Counter", "authenticate.collapse.broadcast_error", mock.AnythingOfType("stats.Tags"), int64(1)).Maybe().Return()
	ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

	authenticator := createTestAuthenticator(t)

	var wg sync.WaitGroup
	ready := make(chan bool)

	for _, cred := range []struct {
		token string
		want  []*pb.Attribute
	}{
		{
			token: testfixtures.MonalisaToken1.Value,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID)),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessToken.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.SixDaysFromNow),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaProgrammaticAccessToken.IssuedAt),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
			},
		},
		{
			token: testfixtures.MonalisaToken,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaOAuthAccess.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "PersonalAccessToken"),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{testfixtures.MonalisaOAuthSSOAuthorization.OrganizationID}...),
				pb.NewTimeAttribute(client.CredentialCreatedAtAttribute, testfixtures.MonalisaOAuthAccess.CreatedAt.Time),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaOAuthAccess.LastIssuedAt.Time),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Unix(testfixtures.MonalisaOAuthAccess.ExpiresAt.Int64, 0)),
			},
		},
	} {
		for i := 0; i < concurrentRequests; i++ {
			wg.Add(1)
			go func(id int, token string, expected []*pb.Attribute) {
				defer wg.Done()

				// wait for all goroutines to be spun up
				<-ready

				ctx := requestid.WithGitHubRequestID(ctx, fmt.Sprintf("request-%d", id))
				ctx = diagnostics.WithLogger(ctx, testhelpers.GetTestLogger())

				// authenticate
				credentials := pb.NewAccessTokenCredential(token)
				got, err := authenticator.collapsibleAuthenticate(ctx, credentials)
				require.NoError(t, err)
				testhelpers.RequireEqualAttributeSlices(t, expected, got, true)
			}(i, cred.token, cred.want)
		}
	}

	// release the hounds
	close(ready)

	wg.Wait()

	for ix, call := range mockStatter.Calls {
		t.Logf("call[%d]: %s(%v)", ix+1, call.Method, call.Arguments)
	}
}
