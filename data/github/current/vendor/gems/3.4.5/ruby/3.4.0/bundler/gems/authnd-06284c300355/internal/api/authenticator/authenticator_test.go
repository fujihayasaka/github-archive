package authenticator

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/broadcaster"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/api/validators"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/twitchtv/twirp"

	"github.com/stretchr/testify/require"
)

func TestAuthenticator_AuthenticateLoginPassword(t *testing.T) {
	tests := map[string]struct {
		creds *pb.LoginPassword
		err   error
		want  []*pb.Attribute
	}{
		"login not defined": {
			err: twirp.RequiredArgumentError("credentials.login_password.login"),
		},
		"password not defined": {
			creds: &pb.LoginPassword{Login: "foo"},
			err:   twirp.RequiredArgumentError("credentials.login_password.password"),
		},
		"valid login password": {
			creds: &pb.LoginPassword{
				Login:    testfixtures.MonalisaUser.Login,
				Password: "passworD1",
			},
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "LoginPassword"),
			},
		},
		"unknown user": {
			creds: &pb.LoginPassword{Login: "foo", Password: "bar"},
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			authenticator := createTestAuthenticator(t)
			got, err := authenticator.authenticateLoginPassword(context.Background(), tc.creds)
			require.Equal(t, tc.err, err)
			require.Equal(t, tc.want, got)
		})
	}
}

func TestAuthenticator_AuthenticateSSHPublicKey(t *testing.T) {
	tests := map[string]struct {
		key  *pb.SSHPublicKey
		err  error
		want []*pb.Attribute
	}{
		"public key not defined": {
			key: &pb.SSHPublicKey{},
			err: twirp.RequiredArgumentError("credentials.ssh_public_key.key"),
		},
		"public key missing": {
			key: &pb.SSHPublicKey{
				Key: `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCjN2JeCEOp0ZHk5fkOQ4XOyYg6KJ0HQUai/RIRNOY9ifvlpwGO/sH26oUD3IzEuPmEsDyFcDMY4a8FO1CAyNElHZOKygwvF90OYCqZa2y1v9ZEA5W9xzlIhtALAiTtzuy4YRn4sra1VCGagbP+WJTmookeWXxFp5thqnlIgvZkzYkjDPf6uE/iFtRHdYUsl4pkIVjfkrV1QqRSE64M9oneaj90Sd9PSlel7OlUwaaeno4gKei+fTw6XRff/duxE1Ze5lJPaRsbtxThBlpqaCDx3nEw0jCsQNH85BOcXlaZbP+gmMi4rsYYmgujfbdWDspVVnbteRzoRPANMIkTlmok8bZTuin6VYI4F0LdMFf6YKMwDOGug0NzFp7WtX/PZM3eRx5tXUqRWIL3e4f9T/E4HhGFos7qRsoPUdLv7pZfB1FaTXDKGebYSPByb/32o6Hit7NR9HJ6fJYmcLSQhNMew9bmAvJAK7zFf7N8LK2IL56ftG+Wy7GAunX/qn/Vm0U= sid@gitlab.com`,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_NOT_FOUND},
		},
		"public key exists": {
			key: &pb.SSHPublicKey{
				Key: testfixtures.MonalisaPublicKey.Key,
			},
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaPublicKey.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			authenticator := createTestAuthenticator(t)

			got, err := authenticator.authenticateSSHPublicKey(context.Background(), tc.key)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
		})
	}
}

func TestAuthenticator_AuthenticateAccessToken(t *testing.T) {
	tests := map[string]struct {
		token *pb.AccessToken
		err   error
		want  []*pb.Attribute
	}{
		"token not defined": {
			err: twirp.RequiredArgumentError("credentials.access_token.token"),
		},
		"valid oauth access token": {
			token: &pb.AccessToken{
				Token: testfixtures.MonalisaToken,
			},
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
			token: &pb.AccessToken{
				Token: testfixtures.MonalisaGistToken,
			},
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
			token: &pb.AccessToken{
				Token: "ghp_859d21d07aed3b5ee810656a93e8b5a3812a",
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"unknown user": {
			token: &pb.AccessToken{
				Token: testfixtures.UnknownUserToken,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			authenticator := createTestAuthenticator(t)
			got, err := authenticator.authenticateAccessToken(context.Background(), tc.token)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
		})
	}
}

func TestAuthenticator_AuthenticateSignedAuthToken(t *testing.T) {
	tests := map[string]struct {
		token *pb.SignedAuthToken
		now   time.Time
		err   error
		want  []*pb.Attribute
	}{
		"token not defined": {
			token: &pb.SignedAuthToken{
				Scope: "test",
			},
			err: twirp.RequiredArgumentError("credentials.signedAuthToken.token"),
		},
		"scope not defined": {
			token: &pb.SignedAuthToken{
				Token: testfixtures.MonalisaValidSAT,
			},
			err: twirp.RequiredArgumentError("credentials.signedAuthToken.scope"),
		},
		"valid signed auth token": {
			token: &pb.SignedAuthToken{
				Token: testfixtures.MonalisaValidSAT,
				Scope: "test",
			},
			now: time.Date(2021, 1, 1, 7, 0, 0, 0, time.UTC),
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SignedAuthToken"),
				pb.NewInt64Attribute(client.CredentialVersionAttribute, 3),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.MonalisaValidSATExpiresAt),
				pb.NewStringAttribute(fmt.Sprintf("%s:key1", client.CredentialPayloadAttribute), "val1"),
				pb.NewInt64Attribute(fmt.Sprintf("%s:key2", client.CredentialPayloadAttribute), 42),
			},
		},
		"unknown user": {
			token: &pb.SignedAuthToken{
				Token: testfixtures.UnknownUserSAT,
				Scope: "MyScope",
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			authenticator := createTestAuthenticator(t)
			nowFn := func() time.Time {
				return time.Date(2021, 01, 01, 7, 0, 0, 0, time.UTC)
			}
			authenticator.sat = validators.NewTestSignedAuthTokenValidator(testfixtures.AuthStore, nowFn, t)

			got, err := authenticator.authenticateSignedAuthToken(context.Background(), tc.token)
			require.Equal(t, tc.err, err)
			require.Equal(t, tc.want, got)
		})
	}
}

func TestAuthenticator_AuthenticateLegacyPrATToken(t *testing.T) {
	tests := map[string]struct {
		token *pb.AccessToken
		err   error
		want  []*pb.Attribute
	}{
		"token not defined": {
			err: twirp.RequiredArgumentError("credentials.access_token.token"),
		},
		"valid prat token": {
			token: &pb.AccessToken{
				Token: testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText.Value,
			},
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.UserOne.Login), // mismatched user ids in token
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.AccessID)),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaLegacyProgrammaticAccessToken.IssuedAt),
			},
		},
		"token not found": {
			token: &pb.AccessToken{
				Token: testfixtures.NotFoundToken.Value,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"valid prat token with extra attributes": {
			token: &pb.AccessToken{
				Token: testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributesPlainText.Value,
			},
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.UserOne.Login), // mismatched user ids in token
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.AccessID)),
				pb.NewBoolAttribute(testfixtures.BoolTrueAttributeId, true),
				pb.NewBoolAttribute(testfixtures.BoolFalseAttributeId, false),
				pb.NewDoubleAttribute(testfixtures.DoubleAttributeId, 1.1),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.IssuedAt),
			},
		},
		"valid prat token future expire": {
			token: &pb.AccessToken{
				Token: testfixtures.FutureExpiredLegacyProgrammaticAccessTokenPlainText.Value,
			},
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.UserOne.Login), // mismatched user ids in token
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FutureExpiredLegacyProgrammaticAccessToken.ID)),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.FutureExpiredLegacyProgrammaticAccessToken.AccessID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FutureExpirationTime),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.FutureExpiredLegacyProgrammaticAccessToken.IssuedAt),
			},
		},
		"token expired": {
			token: &pb.AccessToken{
				Token: testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText.Value,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"token revoked": {
			token: &pb.AccessToken{
				Token: testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText.Value,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			authenticator := createTestAuthenticator(t)
			got, err := authenticator.authenticateAccessToken(context.Background(), tc.token)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
		})
	}
}

func TestAuthenticator_AuthenticatePrATToken(t *testing.T) {
	tests := map[string]struct {
		token *pb.AccessToken
		err   error
		want  []*pb.Attribute
	}{
		"token not defined": {
			err: twirp.RequiredArgumentError("credentials.access_token.token"),
		},
		"valid prat token": {
			token: &pb.AccessToken{
				Token: testfixtures.MonalisaToken1.Value,
			},
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
			token: &pb.AccessToken{
				Token: testfixtures.NotFoundToken.Value,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"valid prat token with extra attributes": {
			token: &pb.AccessToken{
				Token: testfixtures.MonalisaTokenExtraAttributes.Value,
			},
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
			token: &pb.AccessToken{
				Token: testfixtures.FutureExpiredToken.Value,
			},
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
			token: &pb.AccessToken{
				Token: testfixtures.ExpiredToken.Value,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"token revoked": {
			token: &pb.AccessToken{
				Token: testfixtures.RevokedToken.Value,
			},
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := commonTesting.NewLoggerContext(t)
			authenticator := createTestAuthenticator(t)
			got, err := authenticator.authenticateAccessToken(ctx, tc.token)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
		})
	}
}

func TestEnterpriseAuthenticator(t *testing.T) {
	authenticator := createTestEnterpriseAuthenticator(t)

	// expected error for all unsupported types
	unsupportedErr := &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}

	// login-pw
	lp := &pb.LoginPassword{
		Login:    testfixtures.MonalisaUser.Login,
		Password: "passworD1",
	}
	lpRes, lpErr := authenticator.authenticateLoginPassword(commonTesting.NewLoggerContext(t), lp)
	require.Equal(t, unsupportedErr, lpErr)
	require.Equal(t, []*pb.Attribute(nil), lpRes)

	// SSH public key
	sshKey := &pb.SSHPublicKey{
		Key: testfixtures.MonalisaPublicKey.Key,
	}
	sshKeyRes, sshKeyErr := authenticator.authenticateSSHPublicKey(commonTesting.NewLoggerContext(t), sshKey)
	require.Equal(t, unsupportedErr, sshKeyErr)
	require.Equal(t, []*pb.Attribute(nil), sshKeyRes)

	// oauth token
	token := &pb.AccessToken{
		Token: testfixtures.MonalisaToken,
	}
	tokenRes, tokenErr := authenticator.authenticateAccessToken(commonTesting.NewLoggerContext(t), token)
	require.Equal(t, unsupportedErr, tokenErr)
	require.Equal(t, []*pb.Attribute(nil), tokenRes)

	// signed auth token
	sat := &pb.SignedAuthToken{
		Token: testfixtures.MonalisaValidSAT,
		Scope: "test",
	}
	satRes, satErr := authenticator.authenticateSignedAuthToken(commonTesting.NewLoggerContext(t), sat)
	require.Equal(t, unsupportedErr, satErr)
	require.Equal(t, []*pb.Attribute(nil), satRes)

	// PrAT
	prat := &pb.AccessToken{
		Token: testfixtures.MonalisaToken1.Value,
	}
	pratWant := []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID)),
		pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessToken.ID)),
		pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
		pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.SixDaysFromNow),
		pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaProgrammaticAccessToken.IssuedAt),
		pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
	}
	pratRes, pratErr := authenticator.authenticateAccessToken(commonTesting.NewLoggerContext(t), prat)
	require.Equal(t, nil, pratErr)
	testhelpers.RequireEqualAttributeSlices(t, pratWant, pratRes, true)
}

func createTestAuthenticator(t *testing.T) *Authenticator {
	t.Helper()

	dataStore := testfixtures.AuthStore
	return &Authenticator{
		requestBroadcaster: broadcaster.NewBroadcaster(),
		login: &validators.LoginValidator{
			Store: dataStore,
		},
		ssh: &validators.SSHPublicKeyValidator{
			Store: dataStore,
		},
		oauth: &validators.OAuthValidator{
			Store: dataStore,
		},
		sat: validators.NewSignedAuthTokenValidator(dataStore),
		mint: &validators.MintTokenValidator{
			Store: dataStore,
		},
	}
}

func createTestEnterpriseAuthenticator(t *testing.T) *Authenticator {
	t.Helper()

	dataStore := testfixtures.AuthStore
	return &Authenticator{
		requestBroadcaster: broadcaster.NewBroadcaster(),
		login:              &validators.UnsupportedValidator{},
		ssh:                &validators.UnsupportedValidator{},
		oauth:              &validators.UnsupportedValidator{},
		sat:                &validators.UnsupportedValidator{},
		mint: &validators.MintTokenValidator{
			Store: dataStore,
		},
	}
}
