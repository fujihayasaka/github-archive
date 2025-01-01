package testing

import (
	"context"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/github/authnd/internal/common/testfixtures"
	commonTesting "github.com/github/authnd/internal/common/testing"

	authndClient "github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"

	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	tw "github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
)

func TestLoginPassword(t *testing.T, client pb.Authenticator) {
	tests := map[string]struct {
		req  *pb.AuthenticateRequest
		resp *pb.AuthenticateResponse
		err  error
	}{
		"credentials not defined": {
			req: &pb.AuthenticateRequest{},
			err: tw.RequiredArgumentError("credentials"),
		},
		"login is nil": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Password: "mayday",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.login_password.login"),
		},
		"login is empty string": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login:    "",
							Password: "mayday",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.login_password.login"),
		},
		"password is nil": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login: "octocat",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.login_password.password"),
		},
		"password is empty string": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login:    "octocat",
							Password: "",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.login_password.password"),
		},
		"not found": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login:    "octocat",
							Password: "mayday",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN,
			},
		},
		"incorrect password": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login:    "monalisa",
							Password: "password1",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_PASSWORD_MISMATCH,
			},
		},
		"suspended user": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login:    "troll",
							Password: "trollyourfriends",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED,
			},
		},
		"valid login password": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login:    testfixtures.MonalisaUser.Login,
							Password: "passworD1",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewStringAttribute("user.login", testfixtures.MonalisaUser.Login),
					pb.NewStringAttribute("credential.type", "LoginPassword"),
				},
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := applyDefaultHeaders(t, context.Background())
			resp, err := client.Authenticate(ctx, tc.req)

			require.Equal(t, tc.err, err)

			// using require.Equal doesn't work on protobuf structs.
			// https://github.com/stretchr/testify/issues/758
			if equal := proto.Equal(tc.resp, resp); !equal {
				require.FailNowf(t, "Response doesn't match", "Not Equal: \nexpected: %+v\nactual  : %+v\n", tc.resp, resp)
			}
		})
	}
}

func TestSSHPublicKey(t *testing.T, client pb.Authenticator) {
	tests := map[string]struct {
		req  *pb.AuthenticateRequest
		resp *pb.AuthenticateResponse
		err  error
	}{
		"invalid": {
			req: &pb.AuthenticateRequest{},
			err: tw.RequiredArgumentError("credentials"),
		},
		"public key is nil": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.ssh_public_key.key"),
		},
		"public key is empty string": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: "",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.ssh_public_key.key"),
		},
		"not found": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCjN2JeCEOp0ZHk5fkOQ4XOyYg6KJ0HQUai/RIRNOY9ifvlpwGO/sH26oUD3IzEuPmEsDyFcDMY4a8FO1CAyNElHZOKygwvF90OYCqZa2y1v9ZEA5W9xzlIhtALAiTtzuy4YRn4sra1VCGagbP+WJTmookeWXxFp5thqnlIgvZkzYkjDPf6uE/iFtRHdYUsl4pkIVjfkrV1QqRSE64M9oneaj90Sd9PSlel7OlUwaaeno4gKei+fTw6XRff/duxE1Ze5lJPaRsbtxThBlpqaCDx3nEw0jCsQNH85BOcXlaZbP+gmMi4rsYYmgujfbdWDspVVnbteRzoRPANMIkTlmok8bZTuin6VYI4F0LdMFf6YKMwDOGug0NzFp7WtX/PZM3eRx5tXUqRWIL3e4f9T/E4HhGFos7qRsoPUdLv7pZfB1FaTXDKGebYSPByb/32o6Hit7NR9HJ6fJYmcLSQhNMew9bmAvJAK7zFf7N8LK2IL56ftG+Wy7GAunX/qn/Vm0U= sid@gitlab.com`,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_NOT_FOUND,
			},
		},
		"valid public key": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: testfixtures.MonalisaPublicKey.Key,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaPublicKey.UserID.Int64),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewInt64Attribute("credential.id", testfixtures.MonalisaPublicKey.ID),
					pb.NewStringAttribute("credential.type", "SSHPublicKey"),
				},
			},
		},
		"deploy": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: testfixtures.DeployPublicKey.Key,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.DeployPublicKey.RepositoryID.Int64),
					pb.NewStringAttribute("actor.type", "Repository"),
					pb.NewInt64Attribute("credential.id", testfixtures.DeployPublicKey.ID),
					pb.NewStringAttribute("credential.type", "SSHPublicKey"),
				},
			},
		},
		"mismatch": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: testfixtures.MismatchSuppliedKeyRaw,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_MISMATCH,
			},
		},
		"outdated 2047 bit DSA key": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: testfixtures.MonalisaOutdatedPublicKey.Key,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewInt64Attribute("credential.id", testfixtures.MonalisaOutdatedPublicKey.ID),
					pb.NewStringAttribute("credential.type", "SSHPublicKey"),
				},
			},
		},
		"unsupported key algo": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: testfixtures.MonalisaUnsupportedAlgoPublicKey.Key,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewInt64Attribute("credential.id", testfixtures.MonalisaUnsupportedAlgoPublicKey.ID),
					pb.NewStringAttribute("credential.type", "SSHPublicKey"),
				},
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := applyDefaultHeaders(t, context.Background())
			resp, err := client.Authenticate(ctx, tc.req)

			require.Equal(t, tc.err, err)

			// using require.Equal doesn't work on protobuf structs.
			// https://github.com/stretchr/testify/issues/758
			if equal := proto.Equal(tc.resp, resp); !equal {
				require.FailNowf(t, "Response doesn't match", "Not Equal: \nexpected: %+v\nactual  : %+v\n", tc.resp, resp)
			}
		})
	}
}

func TestAccessTokens(t *testing.T, client pb.Authenticator) {
	tests := map[string]struct {
		req  *pb.AuthenticateRequest
		resp *pb.AuthenticateResponse
		err  error
	}{
		"token is nil": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.access_token.token"),
		},
		"token is empty string": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: "",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.access_token.token"),
		},
		"not found": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: "ghp_859d21d07aed3b5ee810656a93e8b5a3812a",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND,
			},
		},
		"mismatched token_last_eight": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.MismatchedEightToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_LAST_EIGHT_MISMATCH,
			},
		},
		"matching token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.MonalisaToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewInt64Attribute("credential.id", testfixtures.MonalisaOAuthAccess.ID),
					pb.NewStringAttribute("user.login", testfixtures.MonalisaUser.Login),
					pb.NewIntegerListAttribute("organization.sso_authorized_ids", testfixtures.MonalisaOAuthSSOAuthorization.OrganizationID),
					pb.NewStringAttribute("credential.type", "PersonalAccessToken"),
					pb.NewTimeAttribute("credential.created_at_utc", testfixtures.MonalisaOAuthAccess.CreatedAt.Time),
					pb.NewTimeAttribute("credential.issued_at_utc", testfixtures.MonalisaOAuthAccess.LastIssuedAt.Time),
					pb.NewTimeAttribute("credential.expires_at_utc", time.Unix(testfixtures.MonalisaOAuthAccess.ExpiresAt.Int64, 0)),
				},
			},
		},
		"expired app token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.ExpiredGitAppOauthToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED,
			},
		},
		"expired PAT": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.ExpiredPersonalAccessToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED,
			},
		},
		"matching token, one scope": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.MonalisaGistToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewInt64Attribute("credential.id", testfixtures.MonalisaGistOAuthAccess.ID),
					pb.NewStringAttribute("user.login", testfixtures.MonalisaUser.Login),
					pb.NewStringListAttribute("credential.scopes", "gist"),
					pb.NewIntegerListAttribute("organization.sso_authorized_ids"),
					pb.NewStringAttribute("credential.type", "PersonalAccessToken"),
					pb.NewTimeAttribute("credential.created_at_utc", testfixtures.MonalisaGistOAuthAccess.CreatedAt.Time),
				},
			},
		},
		"oauth app token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.OAuthApplicationToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute(authndClient.ActorIDAttribute, testfixtures.RandomUser.ID),
					pb.NewStringAttribute(authndClient.ActorTypeAttribute, "User"),
					pb.NewInt64Attribute(authndClient.CredentialIDAttribute, testfixtures.ApplicationOauthAccess.ID),
					pb.NewStringAttribute(authndClient.UserLoginAttribute, testfixtures.RandomUser.Login),
					pb.NewIntegerListAttribute(authndClient.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
					pb.NewStringAttribute(authndClient.CredentialTypeAttribute, "OAuthApplicationToken"),
					pb.NewInt64Attribute(authndClient.ApplicationIDAttribute, testfixtures.DefaultOAuthApplication.ID),
					pb.NewStringAttribute(authndClient.ApplicationTypeAttribute, "OauthApplication"),
					pb.NewStringAttribute(authndClient.ApplicationClientIDAttribute, testfixtures.OAuthApplicationKey),
					pb.NewInt64Attribute(authndClient.ApplicationOwnerIDAttribute, int64(testfixtures.ApplicationOauthAccess.ApplicationOwnerID.ValueOrZero())),
					pb.NewStringAttribute(authndClient.ApplicationOwnerTypeAttribute, testfixtures.ApplicationOauthAccess.ApplicationOwnerType.ValueOrZero()),
				},
			},
		},
		"legacy oauth app token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.LegacyOauthApplicationToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute(authndClient.ActorIDAttribute, testfixtures.RandomUser.ID),
					pb.NewStringAttribute(authndClient.ActorTypeAttribute, "User"),
					pb.NewInt64Attribute(authndClient.CredentialIDAttribute, testfixtures.LegacyApplicationOauthAccess.ID),
					pb.NewStringAttribute(authndClient.UserLoginAttribute, testfixtures.RandomUser.Login),
					pb.NewIntegerListAttribute(authndClient.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
					pb.NewStringAttribute(authndClient.CredentialTypeAttribute, "OAuthApplicationToken"),
					pb.NewInt64Attribute(authndClient.ApplicationIDAttribute, testfixtures.DefaultOAuthApplication.ID),
					pb.NewStringAttribute(authndClient.ApplicationTypeAttribute, "OauthApplication"),
					pb.NewStringAttribute(authndClient.ApplicationClientIDAttribute, testfixtures.OAuthApplicationKey),
					pb.NewInt64Attribute(authndClient.ApplicationOwnerIDAttribute, int64(testfixtures.LegacyApplicationOauthAccess.ApplicationOwnerID.ValueOrZero())),
					pb.NewStringAttribute(authndClient.ApplicationOwnerTypeAttribute, testfixtures.LegacyApplicationOauthAccess.ApplicationOwnerType.ValueOrZero()),
				},
			},
		},
		"u2s token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.GitAppOauthToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute(authndClient.ActorIDAttribute, testfixtures.RandomUser.ID),
					pb.NewStringAttribute(authndClient.ActorTypeAttribute, "User"),
					pb.NewInt64Attribute(authndClient.CredentialIDAttribute, testfixtures.GithubAppOauthAccess.ID),
					pb.NewStringAttribute(authndClient.UserLoginAttribute, testfixtures.RandomUser.Login),
					pb.NewIntegerListAttribute(authndClient.OrganizationSSOAuthorizedIdsAttribute, []int64{}...),
					pb.NewStringAttribute(authndClient.CredentialTypeAttribute, "UserToServerToken"),
					pb.NewInt64Attribute(authndClient.ApplicationIDAttribute, int64(testfixtures.DefaultIntegration.ID)),
					pb.NewStringAttribute(authndClient.ApplicationTypeAttribute, "Integration"),
					pb.NewStringAttribute(authndClient.ApplicationClientIDAttribute, testfixtures.IntegrationKey),
					pb.NewInt64Attribute(authndClient.ApplicationOwnerIDAttribute, int64(testfixtures.GithubAppOauthAccess.ApplicationOwnerID.ValueOrZero())),
					pb.NewStringAttribute(authndClient.ApplicationOwnerTypeAttribute, testfixtures.GithubAppOauthAccess.ApplicationOwnerType.ValueOrZero()),
				},
			},
		},
		"spammy owner of oauth app token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.SpammyGHOToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_APPLICATION_OWNER_SPAMMY,
			},
		},
		"spammy user owner of integration": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.SpammyUserGHUToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_APPLICATION_OWNER_SPAMMY,
			},
		},
		"spammy business owner of integration": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.SpammyBusinessGHUToken,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_APPLICATION_OWNER_SPAMMY,
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := applyDefaultHeaders(t, context.Background())
			resp, err := client.Authenticate(ctx, tc.req)

			require.Equal(t, tc.err, err)

			// using require.Equal doesn't work on protobuf structs.
			// https://github.com/stretchr/testify/issues/758
			if equal := proto.Equal(tc.resp, resp); !equal {
				require.FailNowf(t, "Response doesn't match", "Not Equal: \nexpected: %+v\nactual  : %+v\n", tc.resp, resp)
			}
		})
	}
}

func TestPrATTokens(t *testing.T, client pb.Authenticator) {
	tests := map[string]struct {
		req  *pb.AuthenticateRequest
		resp *pb.AuthenticateResponse
		err  error
	}{
		"token is nil": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.access_token.token"),
		},
		"token is empty string": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: "",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.access_token.token"),
		},
		"cannot parse token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: "github_pat_1c0ffeecafec0ffeecafe1_c0ffeecafec0ffeecafec0ffeecafec0ffeecafec0ffeecafe123456789",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID,
			},
		},
		"matching prat token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.MonalisaToken1.Value,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewInt64Attribute("access.id", int64(testfixtures.MonalisaProgrammaticAccessToken.AccessID)),
					pb.NewInt64Attribute("credential.id", int64(testfixtures.MonalisaProgrammaticAccessToken.ID)),
					pb.NewTimeAttribute("credential.expires_at_utc", testfixtures.SixDaysFromNow),
					pb.NewTimeAttribute("credential.issued_at_utc", testfixtures.MonalisaProgrammaticAccessToken.IssuedAt),
					pb.NewStringAttribute("credential.type", pb.ProgrammaticAccessTokenType),
					pb.NewStringAttribute("user.login", testfixtures.MonalisaUser.Login),
				},
			},
		},
		"expired prat token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.ExpiredToken.Value,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED,
			},
		},
		"revoked prat token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.RevokedToken.Value,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED,
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := applyDefaultHeaders(t, context.Background())
			resp, err := client.Authenticate(ctx, tc.req)

			require.Equal(t, tc.err, err)

			// using require.Equal doesn't work on protobuf structs.
			// https://github.com/stretchr/testify/issues/758
			if equal := proto.Equal(tc.resp, resp); !equal {
				require.FailNowf(t, "Response doesn't match", "Not Equal: \nexpected: %+v\nactual  : %+v\n", tc.resp, resp)
			}
		})
	}
}

func TestEnterpriseNotSupported(t *testing.T, client pb.Authenticator) {
	tests := map[string]struct {
		req  *pb.AuthenticateRequest
		resp *pb.AuthenticateResponse
	}{
		"sats unsupported": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaValidSAT2,
							Scope: "test",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED,
			},
		},
		"login/password unsupported": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_LoginPassword{
						LoginPassword: &pb.LoginPassword{
							Login:    testfixtures.MonalisaUser.Login,
							Password: "passworD1",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED,
			},
		},
		"ssh keys unsupported": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SshPublicKey{
						SshPublicKey: &pb.SSHPublicKey{
							Key: testfixtures.MonalisaPublicKey.Key,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED,
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := applyDefaultHeaders(t, context.Background())
			resp, err := client.Authenticate(ctx, tc.req)
			require.Equal(t, tc.resp.Result, resp.Result)
			require.Nil(t, err)

			// require.EqualError(t, tc.err, err.Error())
			// require.Nil(t, resp)
		})
	}
}

func TestSignedAuthToken(t *testing.T, client pb.Authenticator) {
	tests := map[string]struct {
		req  *pb.AuthenticateRequest
		resp *pb.AuthenticateResponse
		err  error
	}{
		"user sat invalid": {
			req: &pb.AuthenticateRequest{},
			err: tw.RequiredArgumentError("credentials"),
		},
		"token is nil": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Scope: "MyScope",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.signedAuthToken.token"),
		},
		"token is empty string": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: "",
							Scope: "MyScope",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.signedAuthToken.token"),
		},
		"scope is nil": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaValidSAT,
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.signedAuthToken.scope"),
		},
		"scope is empty string": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaValidSAT,
							Scope: "",
						},
					},
				},
			},
			err: tw.RequiredArgumentError("credentials.signedAuthToken.scope"),
		},
		"user sat not found": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.UnknownUserSAT,
							Scope: "MyScope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN,
			},
		},
		"user sat matching": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaValidSAT2,
							Scope: "test",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("user.login", testfixtures.MonalisaUser.Login),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewStringAttribute("credential.type", "SignedAuthToken"),
					pb.NewInt64Attribute("credential.version", 3),
					pb.NewTimeAttribute("credential.expires_at_utc", testfixtures.MonalisaValidSAT2ExpiresAt),
					pb.NewStringAttribute("credential.payload:key1", "val1"),
					pb.NewInt64Attribute("credential.payload:key2", 42),
				},
			},
		},
		"user sat mismatched scope": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaValidSAT2,
							Scope: "wrong-scope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID,
			},
		},
		"user sat expired": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaExpiredSAT,
							Scope: "expired",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED,
			},
		},
		"user sat suspended with bad scope": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.TrollSuspendedSAT,
							Scope: "trololol",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID,
			},
		},
		"user sat suspended": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.TrollSuspendedSAT,
							Scope: "MyScope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED,
			},
		},
		"user sat with array data": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaValidSATWithArrayData,
							Scope: "test",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED,
			},
		},
		"session-scoped valid sat": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaValidSessionSAT,
							Scope: "test",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("actor.id", testfixtures.MonalisaUser.ID),
					pb.NewStringAttribute("user.login", testfixtures.MonalisaUser.Login),
					pb.NewStringAttribute("actor.type", "User"),
					pb.NewStringAttribute("credential.type", "SignedAuthToken"),
					pb.NewInt64Attribute("session.id", 6),
					pb.NewInt64Attribute("credential.version", 3),
					pb.NewTimeAttribute("credential.expires_at_utc", testfixtures.MonalisaValidSessionSATExpiresAt),
					pb.NewStringAttribute("credential.payload:key1", "session-val1"),
					pb.NewInt64Attribute("credential.payload:key2", 43),
				},
			},
		},
		"expired session sat": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaExpiredSessionValidSAT,
							Scope: "MyScope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_SESSION_EXPIRED,
			},
		},
		"hard expired session sat": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaHardExpiredSessionValidSAT,
							Scope: "MyScope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_SESSION_EXPIRED,
			},
		},
		"revoked session sat": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaRevokedSessionValidSAT,
							Scope: "MyScope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_SESSION_REVOKED,
			},
		},
		"unknown session sat": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.MonalisaUnknownSessionValidSAT,
							Scope: "MyScope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_SESSION_UNKNOWN,
			},
		},
		"inpersonated session sat": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_SignedAuthToken{
						SignedAuthToken: &pb.SignedAuthToken{
							Token: testfixtures.ImpersonatedSessionValidSAT,
							Scope: "MyScope",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED,
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := applyDefaultHeaders(t, context.Background())
			resp, err := client.Authenticate(ctx, tc.req)

			require.Equal(t, tc.err, err)
			if tc.resp != nil {
				require.Equal(t, tc.resp.Result, resp.Result)
				testhelpers.RequireEqualAttributeSlices(t, tc.resp.Attributes, resp.Attributes, true)
			}
		})
	}
}

func TestServerToServerTokens(t *testing.T, client pb.Authenticator) {
	tests := map[string]struct {
		req  *pb.AuthenticateRequest
		resp *pb.AuthenticateResponse
		err  error
	}{
		"not found": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: "ghs_859d21d07aed3b5ee810656a93e8b5a3812a",
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND,
			},
		},
		"unscoped token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.UnscopedAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("application.id", int64(testfixtures.DefaultIntegration.ID)),
					pb.NewStringAttribute("application.type", "Integration"),
					pb.NewStringAttribute("application.client_id", testfixtures.IntegrationKey),
					pb.NewInt64Attribute("application.owner.id", int64(testfixtures.DefaultIntegration.OwnerID)),
					pb.NewStringAttribute("application.owner.type", testfixtures.DefaultIntegration.AbstractOwnerType),
					pb.NewInt64Attribute("actor.id", testfixtures.BotUser.ID),
					pb.NewStringAttribute("actor.type", "Bot"),
					pb.NewInt64Attribute("installation.id", int64(testfixtures.DefaultIntegrationInstallation.ID)),
					pb.NewInt64Attribute("installation.target.id", int64(testfixtures.DefaultIntegrationInstallation.TargetID)),
					pb.NewStringAttribute("installation.target.type", testfixtures.DefaultIntegrationInstallation.AbstractTargetType),
					pb.NewStringAttribute("credential.type", "ServerToServerToken"),
					pb.NewInt64Attribute("credential.id", int64(testfixtures.UnscopedAuthenticationToken.ID)),
				},
			},
		},
		"scoped token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.ScopedAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("application.id", int64(testfixtures.DefaultIntegration.ID)),
					pb.NewStringAttribute("application.type", "Integration"),
					pb.NewStringAttribute("application.client_id", testfixtures.IntegrationKey),
					pb.NewInt64Attribute("application.owner.id", int64(testfixtures.DefaultIntegration.OwnerID)),
					pb.NewStringAttribute("application.owner.type", testfixtures.DefaultIntegration.AbstractOwnerType),
					pb.NewInt64Attribute("actor.id", testfixtures.BotUser.ID),
					pb.NewStringAttribute("actor.type", "Bot"),
					pb.NewInt64Attribute("installation.id", int64(testfixtures.DefaultIntegrationInstallation.ID)),
					pb.NewInt64Attribute("installation.target.id", int64(testfixtures.DefaultIntegrationInstallation.TargetID)),
					pb.NewStringAttribute("installation.target.type", testfixtures.DefaultIntegrationInstallation.AbstractTargetType),
					pb.NewInt64Attribute("scoped_installation.id", int64(testfixtures.DefaultScopedIntegrationInstallation.ID)),
					pb.NewStringAttribute("scoped_installation.type", "ScopedIntegrationInstallation"),
					pb.NewStringAttribute("credential.type", "ServerToServerToken"),
					pb.NewInt64Attribute("credential.id", int64(testfixtures.ScopedAuthenticationToken.ID)),
				},
			},
		},
		"site scoped token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.SiteScopedAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("application.id", int64(testfixtures.DefaultIntegration.ID)),
					pb.NewStringAttribute("application.type", "Integration"),
					pb.NewStringAttribute("application.client_id", testfixtures.IntegrationKey),
					pb.NewInt64Attribute("application.owner.id", int64(testfixtures.DefaultIntegration.OwnerID)),
					pb.NewStringAttribute("application.owner.type", testfixtures.DefaultIntegration.AbstractOwnerType),
					pb.NewInt64Attribute("actor.id", testfixtures.BotUser.ID),
					pb.NewStringAttribute("actor.type", "Bot"),
					pb.NewInt64Attribute("scoped_installation.id", int64(testfixtures.DefaultSiteScopedIntegrationInstallation.ID)),
					pb.NewStringAttribute("scoped_installation.type", "SiteScopedIntegrationInstallation"),
					pb.NewInt64Attribute("installation.target.id", int64(testfixtures.DefaultSiteScopedIntegrationInstallation.TargetID)),
					pb.NewStringAttribute("installation.target.type", testfixtures.DefaultSiteScopedIntegrationInstallation.AbstractTargetType),
					pb.NewStringAttribute("credential.type", "ServerToServerToken"),
					pb.NewInt64Attribute("credential.id", int64(testfixtures.SiteScopedAuthenticationToken.ID)),
				},
			},
		},
		"expired token": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.ExpiredAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED,
			},
		},
		"integration suspended": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.SuspendIntegrationAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_INTEGRATION_SUSPENDED,
			},
		},
		"integration user spammy": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.SpammyUserAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_USER_SPAMMY,
			},
		},
		"integration for suspended bot": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.SuspendedBotAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED,
			},
		},
		"installation user suspended": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.InstallationUserSuspendedAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_INSTALLATION_SUSPENDED,
			},
		},
		"installation integrator suspended": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.InstallationIntegratorSuspendedAuthenticationTokenValue,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_FAILED_INSTALLATION_SUSPENDED,
			},
		},
		// this test exercises the "precise" owner_type and target_type attribute resolution
		"owned by organization": {
			req: &pb.AuthenticateRequest{
				Credentials: &pb.Credentials{
					Kind: &pb.Credentials_AccessToken{
						AccessToken: &pb.AccessToken{
							Token: testfixtures.UnscopedAuthenticationTokenValueForOrgInstallation,
						},
					},
				},
			},
			resp: &pb.AuthenticateResponse{
				Result: pb.AuthenticateResponse_RESULT_SUCCESS,
				Attributes: []*pb.Attribute{
					pb.NewInt64Attribute("application.id", int64(testfixtures.IntegrationOwnedByOrg.ID)),
					pb.NewStringAttribute("application.type", "Integration"),
					pb.NewStringAttribute("application.client_id", testfixtures.IntegrationOwnedByOrgKey),
					pb.NewInt64Attribute("application.owner.id", int64(testfixtures.IntegrationOwnedByOrg.OwnerID)),
					pb.NewStringAttribute("application.owner.type", "Organization"), // YAY
					pb.NewInt64Attribute("actor.id", testfixtures.BotUser.ID),
					pb.NewStringAttribute("actor.type", "Bot"),
					pb.NewInt64Attribute("installation.id", int64(testfixtures.IntegrationInstallationOnOrganizationAndOwnedByOrg.ID)),
					pb.NewInt64Attribute("installation.target.id", int64(testfixtures.IntegrationInstallationOnOrganizationAndOwnedByOrg.TargetID)),
					pb.NewStringAttribute("installation.target.type", "Organization"), // YAY
					pb.NewStringAttribute("credential.type", "ServerToServerToken"),
					pb.NewInt64Attribute("credential.id", int64(testfixtures.UnscopedAuthenticationTokenOwnedByOrgAndInstalledOnOrg.ID)),
				},
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			ctx := applyDefaultHeaders(t, context.Background())
			resp, err := client.Authenticate(ctx, tc.req)

			require.Equal(t, tc.err, err)

			// using require.Equal doesn't work on protobuf structs.
			// https://github.com/stretchr/testify/issues/758
			if equal := proto.Equal(tc.resp, resp); !equal {
				require.FailNowf(t, "Response doesn't match", "Not Equal: \nexpected: %+v\nactual  : %+v\n", tc.resp, resp)
			}
		})
	}
}

func TestUnknownCredentialType(t *testing.T, client pb.Authenticator) {
	req := &pb.AuthenticateRequest{
		Credentials: &pb.Credentials{
			Kind: nil,
		},
	}

	ctx := applyDefaultHeaders(t, context.Background())
	resp, err := client.Authenticate(ctx, req)

	require.EqualError(t, err, "twirp error internal: unknown credential type: <nil>")
	twirpErr := tw.InternalError("unknown credential type: <nil>")
	require.ErrorAs(t, err, &twirpErr)
	require.Nil(t, resp)
}

func TestMissingTenantIdContextHeader(t *testing.T, client pb.Authenticator) {
	req := &pb.AuthenticateRequest{
		Credentials: &pb.Credentials{
			Kind: &pb.Credentials_AccessToken{
				AccessToken: &pb.AccessToken{
					Token: testfixtures.MonalisaToken1.Value,
				},
			},
		},
	}

	ctx := setSpecificHeaders(t, context.Background(), map[string]string{
		"Catalog-Service":           "test-catalog-service",
		"X-GitHub-Tenant-Shortcode": testfixtures.DefaultBusiness.Shortcode,
	})
	resp, err := client.Authenticate(ctx, req)

	require.EqualError(t, err, "twirp error internal: Error from intermediary with HTTP status code 400 \"Bad Request\"")
	twirpErr := tw.InternalError("missing X-GitHub-Tenant-ID header")
	require.ErrorAs(t, err, &twirpErr)
	require.Nil(t, resp)
}

func TestMissingTenantShortcodeContextHeader(t *testing.T, client pb.Authenticator) {
	req := &pb.AuthenticateRequest{
		Credentials: &pb.Credentials{
			Kind: &pb.Credentials_AccessToken{
				AccessToken: &pb.AccessToken{
					Token: testfixtures.MonalisaToken1.Value,
				},
			},
		},
	}

	ctx := setSpecificHeaders(t, context.Background(), map[string]string{
		"Catalog-Service":    "test-catalog-service",
		"X-GitHub-Tenant-ID": strconv.Itoa(int(testfixtures.DefaultBusiness.ID)),
	})
	resp, err := client.Authenticate(ctx, req)

	require.EqualError(t, err, "twirp error internal: Error from intermediary with HTTP status code 400 \"Bad Request\"")
	twirpErr := tw.InternalError("missing X-GitHub-Tenant-Shortcode header")
	require.ErrorAs(t, err, &twirpErr)
	require.Nil(t, resp)
}

func applyDefaultHeaders(t *testing.T, ctx context.Context) context.Context {
	headers := make(http.Header)
	headers.Add("Catalog-Service", "test-catalog-service")
	if commonTesting.IsProximaMode() {
		headers.Add("X-GitHub-Tenant-ID", "12345")
		headers.Add("X-GitHub-Tenant-Shortcode", testfixtures.DefaultBusiness.Shortcode)
	}

	ctx, err := twirp.WithHTTPRequestHeaders(ctx, headers)
	require.NoError(t, err)
	return ctx
}

func setSpecificHeaders(t *testing.T, ctx context.Context, toApply map[string]string) context.Context {
	headers := make(http.Header)
	for title, value := range toApply {
		headers.Add(title, value)
	}
	ctx, err := twirp.WithHTTPRequestHeaders(ctx, headers)
	require.NoError(t, err)
	return ctx
}
