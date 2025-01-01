package validators

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/api/utils"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	commonmodels "github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
)

type OAuthValidatorInterface interface {
	ValidateOAuthAccessToken(ctx context.Context, token string) ([]*pb.Attribute, error)
}

type OAuthValidator struct {
	Store store.Mysql1Store
}

func (o *OAuthValidator) ValidateOAuthAccessToken(ctx context.Context, token string) ([]*pb.Attribute, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "oauth_access_token_auth")

	ctx, span := tracing.ChildSpan(ctx, "OAuthValidator.ValidateOAuthAccessToken")
	defer span.End()

	span.SetAttributes(attribute.String("gh.authnd.authenticator.credential.type", "oauth_access_token"))
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.authenticator.credential.type", "oauth_access_token"))
	diagnostics.Logger(ctx).Info("validating OAuthAccessToken")

	statter := diagnostics.Statter(ctx)
	tags := twstats.DefaultTags(ctx).Merge(stats.Tags{"credential_type": "oauth_access_token"})

	attributes, err := o.validateToken(ctx, token)
	if attributes != nil {
		respCredType, foundCredentialType := models.GetAttributeValue(attributes, client.CredentialTypeAttribute)
		if foundCredentialType {
			tags["response_credential_type"] = respCredType.GetStringValue()
		}
	}

	if err != nil {
		tags["result"] = "failure"
		statter.Counter("authentication.oauth.result", tags, 1)
		return nil, err
	}

	tags["result"] = "success"
	statter.Counter("authentication.oauth.result", tags, 1)
	return attributes, nil
}

func (o *OAuthValidator) validateToken(ctx context.Context, token string) ([]*pb.Attribute, error) {
	currentTime := time.Now()
	hashed := hashToken(token)
	access, err := o.Store.FindOAuthAccessByHash(ctx, hashed)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND}
		} else if err == common.StoreErrUnsupported {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
		}
		return nil, err
	}

	if access.IsApplicationOwnerSpammy() {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_APPLICATION_OWNER_SPAMMY}
	}

	attributes := []*pb.Attribute{
		pb.NewInt64Attribute(client.ActorIDAttribute, access.UserID),
		pb.NewStringAttribute(client.ActorTypeAttribute, "User"),
		pb.NewInt64Attribute(client.CredentialIDAttribute, access.ID),
	}

	ctx = diagnostics.WithLoggerFields(ctx, kvp.Int64("gh.user.id", access.UserID), kvp.Int64("gh.oauth.access.id", access.ID))
	diagnostics.Logger(ctx).Info("resolved userId and token for OAuthAccessToken")

	if !access.TokenLastEight.Valid || access.TokenLastEight.String != token[32:] {
		return attributes, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_LAST_EIGHT_MISMATCH}
	}

	// If there's an expiry, and it's lapsed, just fail now.
	if access.IsExpired(currentTime) {
		return attributes, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED}
	}

	if access.UserID > 0 {
		// kickoff user validation in the background to ensure they exist and that they are valid
		awaitUser, cancelUserLookup := utils.ValidateUserInBackground(ctx, func(innerContext context.Context) (*commonmodels.User, error) {
			return o.Store.FindUserByID(innerContext, access.UserID)
		})

		sso, ssoErr := o.Store.FindOrganizationSSOByOAuthAccessID(ctx, access.ID)
		if ssoErr != nil && ssoErr != sql.ErrNoRows {
			cancelUserLookup()
			return attributes, ssoErr
		}

		user, err := validateUser(awaitUser)
		if err != nil {
			return nil, err
		}

		attributes = append(attributes,
			pb.NewStringAttribute(client.UserLoginAttribute, user.Login),
		)

		accessData, err := access.ReadRawData()
		if err != nil {
			return attributes, err
		}

		if accessData.Scopes != nil {
			attributes = append(attributes,
				pb.NewStringListAttribute(client.CredentialScopesAttribute, accessData.Scopes...),
			)
		}

		orgIDs := []int64{}
		for _, orgSSO := range sso {
			if !orgSSO.IsRevoked() {
				orgIDs = append(orgIDs, orgSSO.OrganizationID)
			}
		}

		attributes = append(attributes,
			pb.NewIntegerListAttribute(client.OrganizationSSOAuthorizedIdsAttribute, orgIDs...),
		)

		credentialType, err := access.GetCredentialType()
		if err != nil {
			return attributes, err
		}

		attributes = append(attributes,
			pb.NewStringAttribute(client.CredentialTypeAttribute, credentialType),
		)

		if credentialType == "OAuthApplicationToken" || credentialType == "UserToServerToken" {
			if access.IsApplicationAndSuspended() {
				return attributes, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED}
			}
			attributes = append(attributes,
				pb.NewInt64Attribute(client.ApplicationIDAttribute, access.ApplicationID),
				pb.NewStringAttribute(client.ApplicationTypeAttribute, access.ApplicationType.String),
				pb.NewStringAttribute(client.ApplicationClientIDAttribute, access.ApplicationKey.ValueOrZero()),
				pb.NewInt64Attribute(client.ApplicationOwnerIDAttribute, access.ApplicationOwnerID.ValueOrZero()),
				pb.NewStringAttribute(client.ApplicationOwnerTypeAttribute, access.ApplicationOwnerType.ValueOrZero()),
			)
		} else if credentialType == "PersonalAccessToken" {
			attributes = append(attributes,
				pb.NewTimeAttribute(client.CredentialCreatedAtAttribute, access.CreatedAt.Time))

			if access.LastIssuedAt.Valid {
				attributes = append(attributes,
					pb.NewTimeAttribute(client.CredentialIssuedAtAttribute, access.LastIssuedAt.Time))
			}

			if access.ExpiresAt.Valid {
				attributes = append(attributes,
					pb.NewTimeAttribute(client.CredentialExpiresAtAttribute, time.Unix(access.ExpiresAt.Int64, 0)))
			}
		}

		return attributes, nil
	}

	return attributes, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
}

// hashToken returns a base64 encoded sha256 hashed version of the token.
func hashToken(token string) string {
	hash := sha256.New()
	hash.Write([]byte(token)) //nolint: errcheck
	sum := hash.Sum(nil)
	return base64.StdEncoding.EncodeToString(sum)
}
