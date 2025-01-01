package validators

import (
	"context"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common/testfixtures"

	"github.com/stretchr/testify/require"
)

func TestLoginValidatorValidateLoginPassword(t *testing.T) {
	validator := &LoginValidator{
		Store: testfixtures.AuthStore,
	}

	tests := map[string]struct {
		login, password string
		err             error
		want            []*pb.Attribute
	}{
		"not found": {
			login:    "madmax",
			password: "banana",
			err:      &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN},
		},
		"wrong password": {
			login:    "monalisa",
			password: "cakeplease",
			err:      &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PASSWORD_MISMATCH},
		},
		"suspended user": {
			login:    "troll",
			password: "trollyourfriends",
			err:      &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED},
		},
		"correct password": {
			login:    "monalisa",
			password: "passworD1",
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewStringAttribute(client.UserLoginAttribute, testfixtures.MonalisaUser.Login),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "LoginPassword"),
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			got, err := validator.ValidateLoginPassword(context.Background(), tc.login, tc.password)
			require.Equal(t, tc.err, err)
			require.Equal(t, tc.want, got)
		})
	}
}
