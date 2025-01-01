package validators

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/testfixtures"

	"github.com/stretchr/testify/require"
)

func TestSSHPublicKeyValidatorValidatePublicKey(t *testing.T) {
	validator := &SSHPublicKeyValidator{
		Store: testfixtures.AuthStore,
	}

	tests := map[string]struct {
		key  string
		err  interface{} // error message, since we can't really compare the stack trace
		want []*pb.Attribute
	}{
		"not found": {
			key: `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCjN2JeCEOp0ZHk5fkOQ4XOyYg6KJ0HQUai/RIRNOY9ifvlpwGO/sH26oUD3IzEuPmEsDyFcDMY4a8FO1CAyNElHZOKygwvF90OYCqZa2y1v9ZEA5W9xzlIhtALAiTtzuy4YRn4sra1VCGagbP+WJTmookeWXxFp5thqnlIgvZkzYkjDPf6uE/iFtRHdYUsl4pkIVjfkrV1QqRSE64M9oneaj90Sd9PSlel7OlUwaaeno4gKei+fTw6XRff/duxE1Ze5lJPaRsbtxThBlpqaCDx3nEw0jCsQNH85BOcXlaZbP+gmMi4rsYYmgujfbdWDspVVnbteRzoRPANMIkTlmok8bZTuin6VYI4F0LdMFf6YKMwDOGug0NzFp7WtX/PZM3eRx5tXUqRWIL3e4f9T/E4HhGFos7qRsoPUdLv7pZfB1FaTXDKGebYSPByb/32o6Hit7NR9HJ6fJYmcLSQhNMew9bmAvJAK7zFf7N8LK2IL56ftG+Wy7GAunX/qn/Vm0U=`,
			err: &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_NOT_FOUND},
		},
		"matching fingerprint with comment": {
			key: testfixtures.MonalisaPublicKey.Key + ` monalisa@github.com`,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaPublicKey.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
			},
		},
		"matching fingerprint": {
			key: testfixtures.MonalisaPublicKey.Key,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaPublicKey.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
			},
		},
		"deploy": {
			key: testfixtures.DeployPublicKey.Key,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, 1),
				pb.NewStringAttribute(client.ActorTypeAttribute, "Repository"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.DeployPublicKey.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
			},
		},
		"nonsense": {
			key: "nonsense",
			err: fmt.Sprintf("malformed public key: %q", "nonsense"),
		},
		"outdated 2047 bit DSA key": {
			key: testfixtures.MonalisaOutdatedPublicKey.Key,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaOutdatedPublicKey.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
			},
		},
		"not verified": {
			key: testfixtures.MonalisaUnverifiedPublicKey.Key,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaUnverifiedPublicKey.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
				pb.NewBoolAttribute(client.PublicKeyNotVerifiedAttribute, true),
			},
		},
		"unsupported key algo": {
			key: testfixtures.MonalisaUnsupportedAlgoPublicKey.Key,
			want: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testfixtures.MonalisaUser.ID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
				pb.NewInt64Attribute(client.CredentialIDAttribute, testfixtures.MonalisaUnsupportedAlgoPublicKey.ID),
				pb.NewStringAttribute(client.CredentialTypeAttribute, "SSHPublicKey"),
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			got, err := validator.ValidatePublicKey(context.Background(), tc.key)

			if expectedErr, ok := tc.err.(error); ok {
				require.Equal(t, expectedErr, err)
			} else if expectedMsg, ok := tc.err.(string); ok {
				require.Equal(t, expectedMsg, err.Error())
			}
			testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
		})
	}
}
