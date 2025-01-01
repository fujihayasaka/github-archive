package validators

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	apimodels "github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/utils"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tokens/fgpat"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
)

type MintTokenValidatorInterface interface {
	ValidateToken(ctx context.Context, token *fgpat.Token) (attributes []*pb.Attribute, err error)
}

type MintTokenValidator struct {
	Store interface {
		store.ProgrammaticAccessTokensStore
		store.UsersStore
	}
}

func (o *MintTokenValidator) ValidateToken(ctx context.Context, token *fgpat.Token) ([]*pb.Attribute, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "mint_token_auth")

	ctx, span := tracing.ChildSpan(ctx, "MintTokenValidator.ValidateToken")
	defer span.End()

	span.SetAttributes(attribute.String("gh.authnd.authenticator.credential.type", "prat"))
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.authenticator.credential.type", "prat"))
	diagnostics.Logger(ctx).Info("validating ProgrammaticAccessToken")

	statter := diagnostics.Statter(ctx)
	tags := twstats.DefaultTags(ctx).Merge(stats.Tags{
		"result":                   "failure",
		"user_lookup":              "failure",
		"credential_type":          "prat",
		"response_credential_type": pb.ProgrammaticAccessTokenType,
	})
	defer func() {
		statter.Counter("authentication.mint.result", tags, 1)
		statter.Counter("authentication.mint.patv2_user_lookup_result", tags, 1)
	}()

	header, ok := token.Header.(*fgpat.V1Header)
	if !ok || header == nil || header.TokenType != fgpat.ProgrammaticAccessTokenType {
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_INVALID}
	}
	ctx = diagnostics.WithLoggerFields(ctx, kvp.Uint32("gh.user.id", header.UserID))

	userLookupStart := time.Now()
	awaitUser, cancelUserLookup := utils.ValidateUserInBackground(ctx, func(innerContext context.Context) (*models.User, error) {
		diagnostics.Logger(innerContext).Info("looking up user for token")
		user, userErr := o.Store.FindUserByID(innerContext, int64(header.UserID))
		if userErr != nil {
			diagnostics.Logger(innerContext).WithError(userErr).Info("failed to lookup user for v1 token")
			return nil, userErr
		}
		return user, nil
	})

	// validate the prat token
	attr, err := o.validateV1Token(ctx, token)
	if err != nil {
		cancelUserLookup()
		return nil, err
	}

	// validate the user
	user, err := validateUser(awaitUser)
	if err != nil {
		return nil, err
	}

	tags["result"] = "success"
	tags["user_lookup"] = "success"
	attr = append(attr, pb.NewStringAttribute(client.UserLoginAttribute, user.Login))
	statter.DistributionMs("authentication.mint.patv2_user_lookup_wait_ms", tags, time.Since(userLookupStart))
	return attr, nil
}

type tokenLookup func(context.Context, string) (*models.MintTokenCommon, error)

func (o *MintTokenValidator) validateToken(ctx context.Context, hashedToken string, lookupToken tokenLookup) ([]*pb.Attribute, error) {
	logger := diagnostics.Logger(ctx)

	currentTimeUTC := time.Now().UTC()
	token, err := lookupToken(ctx, hashedToken)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND}
		} else if err == common.StoreErrUnsupported {
			return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
		}
		return nil, err
	}

	if token.IsExpired(currentTimeUTC) {
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED}
	}

	if token.IsRevoked() {
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED}
	}

	// all promoted attributes still exist in the attributes field
	attributes, err := apimodels.DeserializeAttributes(token.Attributes)
	if err != nil {
		return nil, err
	}
	attributes = append(attributes, pb.NewInt64Attribute(client.CredentialIDAttribute, int64(token.ID)))
	if token.ExpiresAt.Valid {
		attributes = append(attributes, pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, token.ExpiresAt.Time))
	}
	attributes = append(attributes, pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, token.IssuedAt))

	// check that promoted attributes values match the associated the DB columns' values
	actorIDAttr := apimodels.GetAttributeById(attributes, client.ActorIDAttribute)
	if actorIDAttr == nil {
		logger.Error("promoted attribute missing from attributes column", kvp.String("gh.authnd.authenticator.actor.attr", client.ActorIDAttribute))
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}
	} else if actorIDAttr.Value.GetIntegerValue() != int64(token.ActorID) {
		logger.Error("mismatch between promoted column and attribute column for promoted attribute",
			kvp.String("gh.authnd.authenticator.actor.attr", client.ActorIDAttribute),
			kvp.Int64("gh.authnd.authenticator.actor.value", actorIDAttr.Value.GetIntegerValue()),
			kvp.Int64("gh.authnd.authenticator.promoted.value", int64(token.ActorID)))
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}
	}
	actorTypeAttr := apimodels.GetAttributeById(attributes, client.ActorTypeAttribute)
	if actorTypeAttr == nil {
		logger.Error("promoted attribute missing from attributes column", kvp.String("actor.attr", client.ActorTypeAttribute))
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}
	} else if actorTypeAttr.Value.GetStringValue() != token.ActorType {
		logger.Error("mismatch between promoted column and attribute column for promoted attribute",
			kvp.String("gh.authnd.authenticator.actor.attr", client.ActorTypeAttribute),
			kvp.String("gh.authnd.authenticator.actor.value", actorTypeAttr.Value.GetStringValue()),
			kvp.String("gh.authnd.authenticator.promoted.value", token.ActorType))
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}
	}

	return attributes, nil
}

func (o *MintTokenValidator) validateV1Token(ctx context.Context, tk *fgpat.Token) ([]*pb.Attribute, error) {
	logger := diagnostics.Logger(ctx)

	var accessID uint64
	lookupToken := func(ctx context.Context, hashedToken string) (*models.MintTokenCommon, error) {
		token, err := o.Store.FindProgrammaticAccessTokenByHash(ctx, hashedToken)
		if err != nil {
			return nil, err
		}
		accessID = token.AccessID
		return token.MintTokenCommon, nil
	}

	attrs, err := o.validateToken(ctx, tk.Hash(), lookupToken)
	if err != nil {
		return nil, err
	}

	// check that promoted attributes values match the associated the DB columns' values. the actorID and actorType
	// are checked in the 'validateToken' call above.
	accessIDAttr := apimodels.GetAttributeById(attrs, client.ProgrammaticAccessIDAttribute)
	if accessIDAttr == nil {
		logger.Error("promoted attribute missing from attributes column", kvp.String("gh.authnd.authenticator.actor.attr", client.ProgrammaticAccessIDAttribute))
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}
	} else if accessIDAttr.Value.GetIntegerValue() != int64(accessID) {
		logger.Error("mismatch between promoted column and attribute column for promoted attribute",
			kvp.String("gh.authnd.authenticator.actor.attr", client.ActorIDAttribute),
			kvp.Int64("gh.authnd.authenticator.actor.value", accessIDAttr.Value.GetIntegerValue()),
			kvp.Int64("gh.authnd.authenticator.promoted.value", int64(accessID)))
		return nil, &apimodels.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_GENERIC}
	}

	attrs = append(attrs, pb.NewStringAttribute(client.CredentialTypeAttribute, pb.ProgrammaticAccessTokenType))
	return attrs, nil
}
