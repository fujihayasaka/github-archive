package validators

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/models"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tokens"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
)

type ServerToServerTokenValidatorInterface interface {
	ValidateServerToServerToken(ctx context.Context, token string) ([]*pb.Attribute, error)
}

type ServerToServerTokenValidator struct {
	Store interface {
		store.AuthenticationTokensStore
		store.UsersStore
		store.IntegrationsStore
		store.IntegrationInstallationsStore
		store.ScopedIntegrationInstallationsStore
	}
}

func (v *ServerToServerTokenValidator) ValidateServerToServerToken(ctx context.Context, token string) ([]*pb.Attribute, error) {
	ctx = mysql.WithFeatureSurfaceName(ctx, "server_to_server_token_auth")

	// always fallback to primary reads when record not found to support read-your-own-writes. only affects clusters which
	// have a mysql.PrimaryReadExecutor wrapping their read connections (e.g. not mysql1) so it's safe to set this here,
	// which will cause the fallback to primary reads (ignoring replication lag) for tables in lodge and collab.
	ctx = mysql.ContextPrimaryReadFallbackAlways(
		mysql.ContextPrimaryReadsOnError(ctx, sql.ErrNoRows),
	)

	ctx, span := tracing.ChildSpan(ctx, "ServerToServerTokenValidator.ValidateServerToServerToken")
	defer span.End()

	span.SetAttributes(attribute.String("gh.authnd.authenticator.credential.type", "server_to_server_token"))
	ctx = diagnostics.WithLoggerFields(ctx, kvp.String("gh.authnd.authenticator.credential.type", "server_to_server"))
	diagnostics.Logger(ctx).Info("validating ServerToServerToken")

	statter := diagnostics.Statter(ctx)
	tags := twstats.DefaultTags(ctx).Merge(stats.Tags{"credential_type": "server_to_server"})

	attributes, err := v.validateToken(ctx, token)
	if attributes != nil {
		respCredType, foundCredentialType := models.GetAttributeValue(attributes, client.CredentialTypeAttribute)
		if foundCredentialType {
			tags["response_credential_type"] = respCredType.GetStringValue()
		}
	}

	if err != nil {
		tags["result"] = "failure"
		statter.Counter("authentication.s2s.result", tags, 1)
		return nil, err
	}

	tags["result"] = "success"
	statter.Counter("authentication.s2s.result", tags, 1)
	return attributes, nil
}

func (v *ServerToServerTokenValidator) validateToken(ctx context.Context, token string) ([]*pb.Attribute, error) {
	hashed := tokens.Hash(token)
	authenticationToken, err := v.Store.FindAuthenticationTokenByHash(ctx, hashed)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND}
		} else if err == common.StoreErrUnsupported {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
		}
		return nil, err
	}
	if authenticationToken.IsExpired(time.Now().UTC()) {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_EXPIRED}
	}

	var validateInstallation func(context.Context, uint64) ([]*pb.Attribute, error)
	switch authenticationToken.AuthenticatableType {
	case "IntegrationInstallation":
		validateInstallation = v.validateIntegrationInstallation

	case "ScopedIntegrationInstallation":
		validateInstallation = v.validateScopedIntegrationInstallation

	case "SiteScopedIntegrationInstallation":
		validateInstallation = v.validateSiteScopedIntegrationInstallation

	default:
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_NOT_SUPPORTED}
	}

	attrs, err := validateInstallation(ctx, authenticationToken.AuthenticatableID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND}
		}
		return nil, err
	}

	attrs = append(attrs,
		pb.NewStringAttribute(client.CredentialTypeAttribute, "ServerToServerToken"),
		pb.NewInt64Attribute(client.CredentialIDAttribute, int64(authenticationToken.ID)),
	)

	return attrs, nil
}

func (v *ServerToServerTokenValidator) validateIntegration(ctx context.Context, id uint64) ([]*pb.Attribute, error) {
	var attrs []*pb.Attribute

	integration, err := v.Store.FindIntegrationByID(ctx, id)
	if err != nil {
		return nil, errors.Wrap(err, "failed to find installation")
	}
	diagnostics.Logger(ctx).Info("found integration", kvp.Int64("integration.id", int64(integration.ID)))

	if integration.IsSuspended() {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_INTEGRATION_SUSPENDED}
	} else if integration.UserSpammy() {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_USER_SPAMMY}
	}
	attrs = append(attrs,
		pb.NewInt64Attribute(client.ApplicationIDAttribute, int64(integration.ID)),
		pb.NewStringAttribute(client.ApplicationTypeAttribute, "Integration"),
		pb.NewStringAttribute(client.ApplicationClientIDAttribute, integration.Key.ValueOrZero()),
		pb.NewInt64Attribute(client.ApplicationOwnerIDAttribute, int64(integration.OwnerID)),
		pb.NewStringAttribute(client.ApplicationOwnerTypeAttribute, integration.PreciseOwnerType),
	)

	bot, err := v.Store.FindUserByID(ctx, int64(integration.BotID))
	if err != nil {
		return nil, errors.Wrap(err, "failed to find bot")
	}
	diagnostics.Logger(ctx).Info("found bot", kvp.Int64("bot.id", int64(bot.ID)))

	if bot.IsSuspended() {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_SUSPENDED}
	}
	attrs = append(attrs,
		pb.NewInt64Attribute(client.ActorIDAttribute, int64(bot.ID)),
		pb.NewStringAttribute(client.ActorTypeAttribute, "Bot"),
	)
	return attrs, nil
}

func (v *ServerToServerTokenValidator) validateIntegrationInstallation(ctx context.Context, id uint64) ([]*pb.Attribute, error) {
	installation, err := v.Store.FindIntegrationInstallationByID(ctx, uint64(id))
	if err != nil {
		return nil, errors.Wrap(err, "failed to find integration installation")
	}
	diagnostics.Logger(ctx).Info("found integration installation", kvp.Int64("installation.id", int64(installation.ID)))

	if installation.IsSuspended() {
		return nil, &models.AuthenticationFailure{Code: pb.AuthenticateResponse_RESULT_FAILED_INSTALLATION_SUSPENDED}
	}

	attrs, err := v.validateIntegration(ctx, installation.IntegrationID)
	if err != nil {
		return nil, err
	}

	attrs = append(attrs,
		pb.NewInt64Attribute(client.InstallationIDAttribute, int64(installation.ID)),
		pb.NewInt64Attribute(client.InstallationTargetIDAttribute, int64(installation.TargetID)),
		pb.NewStringAttribute(client.InstallationTargetTypeAttribute, installation.PreciseTargetType),
	)

	return attrs, nil
}

func (v *ServerToServerTokenValidator) validateScopedIntegrationInstallation(ctx context.Context, id uint64) ([]*pb.Attribute, error) {
	sii, err := v.Store.FindScopedIntegrationInstallationByID(ctx, id)
	if err != nil {
		return nil, errors.Wrap(err, "failed to find scoped integration installation")
	}
	diagnostics.Logger(ctx).Info("found scoped integration installation", kvp.Int64("scoped_installation.id", int64(sii.ID)))

	attrs, err := v.validateIntegrationInstallation(ctx, sii.IntegrationInstallationID)
	if err != nil {
		return nil, err
	}

	attrs = append(attrs,
		pb.NewInt64Attribute(client.ScopedInstallationIDAttribute, int64(sii.ID)),
		pb.NewStringAttribute(client.ScopedInstallationTypeAttribute, "ScopedIntegrationInstallation"),
	)
	return attrs, nil
}

func (v *ServerToServerTokenValidator) validateSiteScopedIntegrationInstallation(ctx context.Context, id uint64) ([]*pb.Attribute, error) {
	ssii, err := v.Store.FindSiteScopedIntegrationInstallationByID(ctx, id)
	if err != nil {
		return nil, errors.Wrap(err, "failed to find scoped integration installation")
	}
	diagnostics.Logger(ctx).Info("found site scoped integration installation", kvp.Int64("site_scoped_installation.id", int64(ssii.ID)))
	attrs, err := v.validateIntegration(ctx, ssii.IntegrationID)

	if err != nil {
		return nil, err
	}

	attrs = append(attrs,
		pb.NewInt64Attribute(client.ScopedInstallationIDAttribute, int64(ssii.ID)),
		pb.NewStringAttribute(client.ScopedInstallationTypeAttribute, "SiteScopedIntegrationInstallation"),
		pb.NewInt64Attribute(client.InstallationTargetIDAttribute, int64(ssii.TargetID)),
		pb.NewStringAttribute(client.InstallationTargetTypeAttribute, ssii.PreciseTargetType),
	)
	return attrs, nil
}
