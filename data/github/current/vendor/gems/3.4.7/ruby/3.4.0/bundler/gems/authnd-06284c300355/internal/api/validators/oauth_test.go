package validators

import (
	"context"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/testfixtures"

	"github.com/stretchr/testify/require"
)

func TestOAuthValidatorValidateOAuthAccessToken(t *testing.T) {
	validator := &OAuthValidator{
		Store: testfixtures.AuthStore,
	}

	tests := map[string]struct {
		token string
		err   error
		want  []*pb.Attribute
	}{
		"not found": {
			token: "ghp_859d21d07aed3b5ee810656a93e8b5a3812a",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"matching token, nil scopes": {
			token: testfixtures.MonalisaToken,
			want: []*pb.Attribute{
				pb.NewStringAttribute(client.CredentialTypeAttribute, "PersonalAccessToken"),
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaOAuthAccess.ID),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{testfixtures.MonalisaOAuthSSOAuthorization.OrganizationID}...),
				pb.NewTimeAttribute(client.CredentialCreatedAtAttribute, testfixtures.MonalisaOAuthAccess.CreatedAt.Time),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaOAuthAccess.LastIssuedAt.Time),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Unix(testfixtures.MonalisaOAuthAccess.ExpiresAt.Int64, 0)),
			},
		},
		"matching token, empty scopes": {
			token: testfixtures.EmptyScopesGHPToken,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.EmptyScopesOAuthAccess.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "PersonalAccessToken"),
				pb.NewStringListAttribute(client.CredentialScopesAttribute, []string{}...),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
				pb.NewTimeAttribute(client.CredentialCreatedAtAttribute, testfixtures.EmptyScopesOAuthAccess.CreatedAt.Time),
			},
		},
		"matching token, one scope": {
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
		"mismatched token_last_eight": {
			token: testfixtures.MismatchedEightToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_LAST_EIGHT_MISMATCH},
		},
		"suspended user PAT": {
			// ol' trolly mc trollface got hisself suspended.
			token: testfixtures.TrollToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"unknown": {
			token: testfixtures.UnknownUserToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
		"valid Oauth Application token": {
			token: testfixtures.OAuthApplicationToken,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.RandomUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.RandomUser.Login),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.ApplicationOauthAccess.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "OAuthApplicationToken"),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
				pb.NewInt64Attribute(client.ApplicationIDAttribute, testfixtures.DefaultOAuthApplication.ID),
				pb.NewStringAttribute(client.ApplicationTypeAttribute, "OauthApplication"),
				pb.NewStringAttribute(client.ApplicationClientIDAttribute, testfixtures.OAuthApplicationKey),
				pb.NewInt64Attribute(client.ApplicationOwnerIDAttribute, testfixtures.ApplicationOauthAccess.ApplicationOwnerID.Int64),
				pb.NewStringAttribute(client.ApplicationOwnerTypeAttribute, testfixtures.ApplicationOauthAccess.ApplicationOwnerType.String),
			},
		},
		"suspended Oauth Application token": {
			token: testfixtures.SusOAuthApplicationToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"spammy oauth app owner": {
			token: testfixtures.SpammyGHOToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_APPLICATION_OWNER_SPAMMY},
		},
		"Oauth Application token with suspended user": {
			token: testfixtures.UserSuspendedOAuthApplicationToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"valid Github Application token": {
			token: testfixtures.GitAppOauthToken,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.RandomUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.RandomUser.Login),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.GithubAppOauthAccess.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "UserToServerToken"),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
				pb.NewInt64Attribute(client.ApplicationIDAttribute, int64(testfixtures.DefaultIntegration.ID)),
				pb.NewStringAttribute(client.ApplicationTypeAttribute, "Integration"),
				pb.NewStringAttribute(client.ApplicationClientIDAttribute, testfixtures.IntegrationKey),
				pb.NewInt64Attribute(client.ApplicationOwnerIDAttribute, testfixtures.GithubAppOauthAccess.ApplicationOwnerID.Int64),
				pb.NewStringAttribute(client.ApplicationOwnerTypeAttribute, testfixtures.GithubAppOauthAccess.ApplicationOwnerType.String),
			},
		},
		"github Application token linked to suspended user": {
			token: testfixtures.SusUserGitAppOauthToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"expired github Application token": {
			token: testfixtures.ExpiredGitAppOauthToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"expired PAT": {
			token: testfixtures.ExpiredPersonalAccessToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"valid with set-expiration github Application token": {
			token: testfixtures.NotExpiredGitAppOauthToken,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.RandomUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.RandomUser.Login),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.NotExpiredGithubAppOauthAccess.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "UserToServerToken"),
				pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
				pb.NewInt64Attribute(client.ApplicationIDAttribute, int64(testfixtures.DefaultIntegration.ID)),
				pb.NewStringAttribute(client.ApplicationTypeAttribute, "Integration"),
				pb.NewStringAttribute(client.ApplicationClientIDAttribute, testfixtures.IntegrationKey),
				pb.NewInt64Attribute(client.ApplicationOwnerIDAttribute, testfixtures.NotExpiredGithubAppOauthAccess.ApplicationOwnerID.Int64),
				pb.NewStringAttribute(client.ApplicationOwnerTypeAttribute, testfixtures.NotExpiredGithubAppOauthAccess.ApplicationOwnerType.String),
			},
		},
		"suspended GitHub App u2s token": {
			token: testfixtures.SusGitAppOauthToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"github app u2s token with spammy integration owner user": {
			token: testfixtures.SpammyUserGHUToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_APPLICATION_OWNER_SPAMMY},
		},
		"github app u2s token with spammy integration owner business": {
			token: testfixtures.SpammyBusinessGHUToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_APPLICATION_OWNER_SPAMMY},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			got, err := validator.ValidateOAuthAccessToken(context.Background(), tc.token)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
		})
	}
}
