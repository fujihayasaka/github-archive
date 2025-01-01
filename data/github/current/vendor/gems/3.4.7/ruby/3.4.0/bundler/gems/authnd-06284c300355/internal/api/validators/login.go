package validators

import (
	"context"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/utils"
	commonmodels "github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/tracing"

	"golang.org/x/crypto/bcrypt"
)

type LoginValidatorInterface interface {
	ValidateLoginPassword(ctx context.Context, login, password string) ([]*pb.Attribute, error)
}

// LoginValidator validates Login, Password credentials.
type LoginValidator struct {
	Store store.UsersStore
}

func (l *LoginValidator) ValidateLoginPassword(ctx context.Context, login, password string) ([]*pb.Attribute, error) {
	ctx, span := tracing.ChildSpan(ctx, "LoginValidator.ValidateLoginPassword")
	defer span.End()

	awaitUser, _ := utils.ValidateUserInBackground(ctx, func(innerContext context.Context) (*commonmodels.User, error) {
		return l.Store.FindUserByLogin(ctx, login)
	})
	user, err := validateUser(awaitUser)
	if err != nil {
		return nil, err
	}

	if user.BcryptAuthToken.Valid {
		err = bcrypt.CompareHashAndPassword([]byte(user.BcryptAuthToken.String), []byte(password))
	} else {
		err = bcrypt.ErrMismatchedHashAndPassword
	}
	if err != nil {
		if err == bcrypt.ErrMismatchedHashAndPassword {
			err = &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_PASSWORD_MISMATCH}
		}
		return nil, err
	}

	return []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, user.ID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewStringAttribute(client.UserLoginAttribute, user.Login),
		pb.NewStringAttribute(client.CredentialTypeAttribute, "LoginPassword"),
	}, nil
}
