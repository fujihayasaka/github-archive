package validators

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/pkg/errors"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/sat"
	"github.com/github/authnd/internal/common/diagnostics"
	dbmodels "github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
)

type SignedAuthTokenValidatorInterface interface {
	ValidateSignedAuthToken(ctx context.Context, token, scope string) ([]*pb.Attribute, error)
}

type SignedAuthTokenValidator struct {
	Store store.Mysql1Store
	nowFn func() time.Time
}

func NewSignedAuthTokenValidator(s store.Mysql1Store) *SignedAuthTokenValidator {
	return &SignedAuthTokenValidator{
		Store: s,
		nowFn: time.Now,
	}
}

func NewTestSignedAuthTokenValidator(s store.Store, nowFn func() time.Time, t *testing.T) *SignedAuthTokenValidator {
	if t == nil {
		panic("must not be used outside a test!")
	}
	return &SignedAuthTokenValidator{
		Store: s,
		nowFn: nowFn,
	}
}

func (v *SignedAuthTokenValidator) ValidateSignedAuthToken(ctx context.Context, token, scope string) ([]*pb.Attribute, error) {
	ctx, span := tracing.ChildSpan(ctx, "SignedAuthTokenValidator.ValidateSignedAuthToken")
	defer span.End()

	statter := diagnostics.Statter(ctx)

	tags := twstats.DefaultTags(ctx).Merge(stats.Tags{
		"credential_type": "signed_auth_token",
		"result":          "failure",
	})
	defer statter.Counter("authentication.sat.result", tags, 1)

	verifiedToken, err := sat.VerifyToken(token, scope, v.newLookupUserFunction(ctx))
	if err != nil {
		if errors.Is(err, sat.ErrorInvalidToken) || errors.Is(err, sat.ErrorUnsupportedTokenVersion) {
			tags["invalid"] = "true"
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID}
		}
		return nil, err
	}
	now := v.nowFn()
	if verifiedToken.Expires.Before(now) {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED}
	}

	tags["response_credential_type"] = "SignedAuthToken"
	tags["result"] = "success"

	result := []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, verifiedToken.UserID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewStringAttribute(client.UserLoginAttribute, verifiedToken.UserLogin),
		pb.NewStringAttribute(client.CredentialTypeAttribute, "SignedAuthToken"),
		pb.NewInt64Attribute(client.CredentialVersionAttribute, int64(verifiedToken.Version)),
		pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, verifiedToken.Expires),
	}

	if verifiedToken.SessionID > 0 {
		result = append(result, pb.NewInt64Attribute(client.SessionIDAttribute, verifiedToken.SessionID))
	}

	payloadAttrs, err := models.MapPayloadToAttributes(client.CredentialPayloadAttribute, verifiedToken.Data)
	if err != nil {
		return nil, err
	}

	result = append(result, payloadAttrs...)

	return result, nil
}

func (v *SignedAuthTokenValidator) ValidateSession(ctx context.Context, id int64) (*dbmodels.UserSession, error) {
	userSession, err := v.Store.FindUserSessionByID(ctx, id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_UNKNOWN}
		}
		return nil, err
	}
	if userSession.IsImpersonated() {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
	}
	if userSession.IsExpired(v.nowFn()) {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_EXPIRED}
	}
	if userSession.IsRevoked() {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SESSION_REVOKED}
	}
	return userSession, nil
}

func (v *SignedAuthTokenValidator) newLookupUserFunction(ctx context.Context) sat.UserLookup {
	return func(id int64, lookupType sat.LookupType) (sat.TokenUserInfo, error) {
		if lookupType != sat.LookupBySessionID && lookupType != sat.LookupByUserID {
			return sat.TokenUserInfo{}, errors.New("invalid UserLookup type for SignedAuthToken")
		}

		if lookupType == sat.LookupBySessionID {
			userSession, err := v.ValidateSession(ctx, id)
			if err != nil {
				return sat.TokenUserInfo{}, err
			}
			// we can do the user lookup now that we have the user ID
			id = userSession.UserID
		}

		user, err := v.Store.FindUserByID(ctx, id)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return sat.TokenUserInfo{}, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_UNKNOWN}
			}
			return sat.TokenUserInfo{}, err
		}

		return sat.TokenUserInfo{
			UserID:      user.ID,
			UserLogin:   user.Login,
			TokenSecret: user.TokenSecret.String,
			IsSuspended: user.IsSuspended(),
		}, nil
	}
}
