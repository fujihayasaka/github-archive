package validators

import (
	"context"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/testfixtures"
	"github.com/github/authnd/internal/common/tokens/fgpat"
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestValidateLegacyPrATToken(t *testing.T) {
	validator := &MintTokenValidator{
		Store: testfixtures.AuthStore,
	}

	tests := map[string]struct {
		token *fgpat.Token
		err   error
		want  []*pb.Attribute
	}{
		"token not found": {
			token: testfixtures.NotFoundLegacyProgramaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"token expired": {
			token: testfixtures.ExpiredLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"token revoked": {
			token: testfixtures.RevokedLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED},
		},
		"missing actor ID in attributes column": {
			token: testfixtures.MissingActorIDLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"missing actor type in attributes column": {
			token: testfixtures.MissingActorTypeLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"missing access ID in attributes column": {
			token: testfixtures.MissingAccessIDLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"mismatched value for actor id in attributes column": {
			token: testfixtures.MismatchActorIDLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"mismatched value for actor type in attributes column": {
			token: testfixtures.MismatchActorTypeLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"mismatched value for access id in attributes column": {
			token: testfixtures.MismatchAccessIDLegacyProgrammaticAccessTokenPlainText,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"valid token": {
			token: testfixtures.MonalisaLegacyProgrammaticAccessTokenPlainText,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.UserOne.Login), // mismatched user ids in token
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaLegacyProgrammaticAccessToken.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaLegacyProgrammaticAccessToken.IssuedAt),
			},
		},
		"valid token extra attributes": {
			token: testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributesPlainText,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.UserOne.Login), // mismatched user ids in token
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
				pb.NewBoolAttribute(testfixtures.BoolTrueAttributeId, true),
				pb.NewBoolAttribute(testfixtures.BoolFalseAttributeId, false),
				pb.NewDoubleAttribute(testfixtures.DoubleAttributeId, 1.1),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaLegacyProgrammaticAccessTokenExtraAttributes.IssuedAt),
			},
		},
		"valid prat token future expire": {
			token: testfixtures.FutureExpiredLegacyProgrammaticAccessTokenPlainText,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.UserOne.Login), // mismatched user ids in token
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FutureExpiredLegacyProgrammaticAccessToken.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FutureExpirationTime),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.FutureExpiredLegacyProgrammaticAccessToken.IssuedAt),
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			mockStatter := mocks.Client{}
			expectedTags := stats.Tags{
				"component":                "twirp",
				"result":                   "success",
				"user_lookup":              "success",
				"credential_type":          "prat",
				"response_credential_type": pb.ProgrammaticAccessTokenType,
			}
			if tc.err != nil {
				expectedTags["result"] = "failure"
				expectedTags["user_lookup"] = "failure"
			} else {
				// user lookup wait only statted when primary prat lookup succeeds
				mockStatter.Mock.On("DistributionMs", "authentication.mint.patv2_user_lookup_wait_ms", expectedTags, mock.AnythingOfType("time.Duration")).Return()
			}

			mockStatter.Mock.On("Counter", "authentication.mint.result", expectedTags, int64(1)).Return()
			mockStatter.Mock.On("Counter", "authentication.mint.patv2_user_lookup_result", expectedTags, int64(1)).Return()
			ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

			got, err := validator.ValidateToken(ctx, tc.token)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)

			mockStatter.AssertExpectations(t)
		})
	}
}

func TestValidatePrATToken(t *testing.T) {
	validator := &MintTokenValidator{
		Store: testfixtures.AuthStore,
	}

	tests := map[string]struct {
		token             *fgpat.Token
		userLookupSuccess bool
		err               error
		want              []*pb.Attribute
	}{
		"user not found": {
			token: testfixtures.NilUserToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
		"user suspended": {
			token: testfixtures.SuspendedUserToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"token not found": {
			token: testfixtures.NotFoundToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND},
		},
		"token expired": {
			token: testfixtures.ExpiredToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"token revoked": {
			token: testfixtures.RevokedToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED},
		},
		"missing actor ID in attributes column": {
			token: testfixtures.MissingActorIDToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"missing actor type in attributes column": {
			token: testfixtures.MissingActorTypeToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"missing access ID in attributes column": {
			token: testfixtures.MissingAccessIDToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"mismatched value for actor id in attributes column": {
			token: testfixtures.MismatchActorIDToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"mismatched value for actor type in attributes column": {
			token: testfixtures.MismatchActorTypeToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"mismatched value for access id in attributes column": {
			token: testfixtures.MismatchAccessIDToken,
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC},
		},
		"valid token": {
			token:             testfixtures.MonalisaToken1,
			userLookupSuccess: true,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.MonalisaProgrammaticAccessToken.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.SixDaysFromNow),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.MonalisaProgrammaticAccessToken.IssuedAt),
			},
		},
		"valid token extra attributes": {
			token:             testfixtures.MonalisaTokenExtraAttributes,
			userLookupSuccess: true,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
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
			token:             testfixtures.FutureExpiredToken,
			userLookupSuccess: true,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, 3),
				pb.NewInt64Attribute(client.CredentialIDAttribute, int64(testfixtures.FutureExpiredProgrammaticAccessToken.ID)),
				pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.FutureExpirationTime),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, testfixtures.FutureExpiredProgrammaticAccessToken.IssuedAt),
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			mockStatter := mocks.Client{}
			expectedTags := stats.Tags{
				"component":                "twirp",
				"result":                   "success",
				"user_lookup":              "failure",
				"credential_type":          "prat",
				"response_credential_type": pb.ProgrammaticAccessTokenType,
			}
			if tc.userLookupSuccess {
				expectedTags["user_lookup"] = "success"
			}
			if tc.err != nil {
				expectedTags["result"] = "failure"
			} else {
				// user lookup wait stat only emitted when primary PrAT lookup succeeds
				mockStatter.Mock.On("DistributionMs", "authentication.mint.patv2_user_lookup_wait_ms", expectedTags, mock.AnythingOfType("time.Duration")).Return()
			}

			mockStatter.Mock.On("Counter", "authentication.mint.result", expectedTags, int64(1)).Return()
			mockStatter.Mock.On("Counter", "authentication.mint.patv2_user_lookup_result", expectedTags, int64(1)).Return()
			ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

			got, err := validator.ValidateToken(ctx, tc.token)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)

			mockStatter.AssertExpectations(t)
		})
	}
}
