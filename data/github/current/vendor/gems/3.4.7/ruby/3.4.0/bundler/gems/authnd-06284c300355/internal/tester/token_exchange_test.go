package tester

import (
	"context"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
)

func TestTokenExchangeTokenTestSuccess(t *testing.T) {
	cfg, err := NewConfigFromEnvironment()
	if err != nil {
		t.Fatal(err)
	}
	ctx, err := cfg.NewRootContext()
	if err != nil {
		t.Fatal(err)
	}

	s2sToken := "ghs_garbagegarbage"
	jwtToken := "jwt.garbage.garbage"

	exchangeTest := &tokenExchangeTest{
		cfg:        cfg,
		runTracker: tokenExchangeTracker,
		createTokenFunc: func() (string, error) {
			return s2sToken, nil
		},
		authenticatorFunc: func(_ stats.Client) (client.Authenticator, error) {
			return &mockAuthndClient{
				authFunc: func(req *client.AuthenticateRequest) (*client.AuthenticateResponse, error) {
					if req.Credentials.GetAccessToken().GetToken() != s2sToken {
						return &client.AuthenticateResponse{Result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND}, nil
					}

					return &client.AuthenticateResponse{
						Result: pb.AuthenticateResponse_RESULT_SUCCESS,
						Attributes: map[string]interface{}{
							client.CredentialIDAttribute:           int64(999),
							client.CredentialTypeAttribute:         string(client.CredentialTypeServerToServerToken),
							client.ActorIDAttribute:                int64(13),
							client.ActorTypeAttribute:              "Bot",
							client.ApplicationIDAttribute:          AppID,
							client.ApplicationOwnerIDAttribute:     AppOwnerID,
							client.ApplicationOwnerTypeAttribute:   AppOwnerType,
							client.ApplicationClientIDAttribute:    ClientID,
							client.ApplicationTypeAttribute:        "Integration",
							client.InstallationIDAttribute:         InstallationID,
							client.InstallationTargetIDAttribute:   InstallationTargetID,
							client.InstallationTargetTypeAttribute: InstallationTargetType,
						},
					}, nil
				},
			}, nil
		},
		exchangeTokenFunc: func(_ stats.Client) (client.TokenExchanger, error) {
			return &mockTokenExchanger{
				exchangeFunc: func(ctx context.Context, request *client.ExchangeTokenRequest, opts ...client.RequestOption) (*client.ExchangeTokenResponse, error) {
					if request.Credentials.GetAccessToken().GetToken() != s2sToken {
						return &client.ExchangeTokenResponse{Result: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND}, nil
					}

					return &client.ExchangeTokenResponse{
						Result: pb.AuthenticateResponse_RESULT_SUCCESS,
						Token:  jwtToken,
					}, nil
				},
			}, nil
		},
		exchangeTokenVerifierFunc: func(_ stats.Client) (tokenVerifier, error) {
			return &mockExchangeTokenVerifier{
				verifyFunc: func(token string) ([]*pb.Attribute, error) {
					return []*pb.Attribute{
						pb.NewInt64Attribute(client.CredentialIDAttribute, 999),
						pb.NewStringAttribute(client.CredentialTypeAttribute, string(client.CredentialTypeServerToServerToken)),
						pb.NewInt64Attribute(client.ActorIDAttribute, 13),
						pb.NewStringAttribute(client.ActorTypeAttribute, "Bot"),
						pb.NewInt64Attribute(client.ApplicationIDAttribute, AppID),
						pb.NewInt64Attribute(client.ApplicationOwnerIDAttribute, AppOwnerID),
						pb.NewStringAttribute(client.ApplicationOwnerTypeAttribute, AppOwnerType),
						pb.NewStringAttribute(client.ApplicationClientIDAttribute, ClientID),
						pb.NewStringAttribute(client.ApplicationTypeAttribute, "Integration"),
						pb.NewInt64Attribute(client.InstallationIDAttribute, InstallationID),
						pb.NewInt64Attribute(client.InstallationTargetIDAttribute, InstallationTargetID),
						pb.NewStringAttribute(client.InstallationTargetTypeAttribute, InstallationTargetType),
					}, nil
				},
			}, nil
		},
	}

	err = exchangeTest.Run(ctx)
	assert.Nil(t, err)
}
