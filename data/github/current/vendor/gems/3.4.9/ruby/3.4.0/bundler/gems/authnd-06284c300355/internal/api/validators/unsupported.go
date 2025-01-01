package validators

import (
	"context"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common/tokens/fgpat"
)

// UpsupportedValidator is a validator that implements all validator functions but always returns an error indicating that they're not supported.
// For dependency injection use for environments where certain credential types are not supported.
type UnsupportedValidator struct {
}

func (u *UnsupportedValidator) ValidateLoginPassword(ctx context.Context, login, password string) ([]*pb.Attribute, error) {
	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
}

func (u *UnsupportedValidator) ValidatePublicKey(ctx context.Context, key string) ([]*pb.Attribute, error) {
	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
}

func (u *UnsupportedValidator) ValidateOAuthAccessToken(ctx context.Context, token string) ([]*pb.Attribute, error) {
	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
}

func (u *UnsupportedValidator) ValidateSignedAuthToken(ctx context.Context, token, scope string) ([]*pb.Attribute, error) {
	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
}

func (u *UnsupportedValidator) ValidateToken(ctx context.Context, token *fgpat.Token) (attributes []*pb.Attribute, err error) {
	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
}

func (u *UnsupportedValidator) ValidateServerToServerToken(ctx context.Context, token string) (attributes []*pb.Attribute, err error) {
	return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
}
