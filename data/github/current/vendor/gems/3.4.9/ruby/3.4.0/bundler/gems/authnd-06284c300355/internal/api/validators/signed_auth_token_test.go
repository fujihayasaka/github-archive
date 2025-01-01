package validators

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/testfixtures"

	"github.com/stretchr/testify/require"
)

func TestSATValidatorValidateSignedAuthToken(t *testing.T) {
	tests := map[string]struct {
		token string
		scope string
		now   time.Time
		err   error
		want  []*pb.Attribute
	}{
		"user sat not found": {
			token: testfixtures.UnknownUserSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
		"user sat suspended": {
			token: testfixtures.TrollSuspendedSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"user sat suspended and bad scope": {
			token: testfixtures.TrollSuspendedSAT,
			scope: "WrongScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID},
		},
		"user sat expired": {
			token: testfixtures.MonalisaExpiredSAT,
			scope: "expired",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED},
		},
		"user sat mismatching scopes": {
			token: testfixtures.MonalisaValidSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID},
		},
		"user sat mismatching secret": {
			token: testfixtures.MonalisaMismatchedSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID},
		},
		"invalid SAT format": {
			token: "this isn't a valid SAT format",
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID},
		},
		"valid user sat": {
			token: testfixtures.MonalisaValidSAT,
			scope: "test",
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
		"valid session sat": {
			token: testfixtures.MonalisaValidSessionSAT,
			scope: "test",
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewInt64Attribute(client.SessionIDAttribute, 6),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SignedAuthToken"),
				pb.NewInt64Attribute(client.CredentialVersionAttribute, 3),
				pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, testfixtures.MonalisaValidSessionSATExpiresAt),
				pb.NewStringAttribute(fmt.Sprintf("%s:key1", client.CredentialPayloadAttribute), "session-val1"),
				pb.NewInt64Attribute(fmt.Sprintf("%s:key2", client.CredentialPayloadAttribute), 43),
			},
		},
		"expired session sat": {
			token: testfixtures.MonalisaExpiredSessionValidSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_EXPIRED},
		},
		"hard expired session sat": {
			token: testfixtures.MonalisaHardExpiredSessionValidSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_EXPIRED},
		},
		"revoked session sat": {
			token: testfixtures.MonalisaRevokedSessionValidSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_REVOKED},
		},
		"expired and revoked session sat": {
			token: testfixtures.MonalisaExpiredAndRevokedSessionValidSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_EXPIRED},
		},
		"unknown session sat": {
			token: testfixtures.MonalisaUnknownSessionValidSAT,
			scope: "MyScope",
			err:   &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_UNKNOWN},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			validator := &SignedAuthTokenValidator{
				Store: testfixtures.AuthStore,
				nowFn: func() time.Time {
					return time.Date(2021, 01, 01, 7, 0, 0, 0, time.UTC)
				},
			}

			got, err := validator.ValidateSignedAuthToken(context.Background(), tc.token, tc.scope)
			require.Equal(t, tc.err, err)
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
		})
	}
}
