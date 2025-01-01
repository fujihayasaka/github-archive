package parsing

import (
	"errors"

	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
)

func parseBotActorFromAttrs(actorID uint64, actorType identity.ActorType, attrs *attrActorParser) (*identity.BotActor, error) {
	if actorType != identity.ActorTypeBot {
		return nil, errors.New("actor type is not a bot")
	}

	var applicationContext *identity.ApplicationContext
	applicationID, exists, err := attrs.int64Attribute(client.ApplicationIDAttribute)
	if err != nil {
		return nil, err
	}
	if exists {
		appOwnerID, exists, err := attrs.int64Attribute(client.ApplicationOwnerIDAttribute)
		if err != nil {
			return nil, err
		}
		if !exists {
			return nil, missingRequiredAttrError(client.ApplicationOwnerIDAttribute)
		}

		rawAppOwnerType, exists, err := attrs.stringAttribute(client.ApplicationOwnerTypeAttribute)
		if err != nil {
			return nil, err
		}
		if !exists {
			return nil, missingRequiredAttrError(client.ApplicationOwnerTypeAttribute)
		}
		appOwnerType, err := identity.ParseApplicationOwnerType(rawAppOwnerType)
		if err != nil {
			return nil, err
		}
		applicationContext = identity.NewApplicationContext(
			uint64(applicationID),
			identity.ApplicationTypeIntegration,
			uint64(appOwnerID),
			appOwnerType,
		)
	}

	installationContext, err := installationContext(attrs)
	if err != nil {
		return nil, err
	}

	return identity.NewBotActor(
		actorID,
		applicationContext,
		installationContext,
		attrs.attrs,
	)
}

// parses installation context for IntegrationInstallation, ScopedIntegrationInstallation, and SiteScopedIntegrationInstallation
// returns nil if installation.id and scoped_installation.id are both missing (indicating that there is no installation context present)
func installationContext(attrs *attrActorParser) (*identity.InstallationContext, error) {
	// installation ID is only available/required for IntegrationInstallation and ScopedIntegrationInstallation
	installationID, installationIDExists, err := attrs.int64Attribute(client.InstallationIDAttribute)
	if err != nil {
		return nil, err
	}
	scopedInstallationID, scopedInstallationIDExists, err := attrs.int64Attribute(client.ScopedInstallationIDAttribute)
	if err != nil {
		return nil, err
	}

	// for now, we'll support parsing bot actors that don't have an associated installation
	// still unclear if this is a valid use case but we know that tests in the monolith setup like this in some cases (e.g. creating an integration and running integration.bot)
	if !installationIDExists && !scopedInstallationIDExists {
		return nil, nil
	}

	installationTargetID, exists, err := attrs.int64Attribute(client.InstallationTargetIDAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.InstallationTargetIDAttribute)
	}

	rawInstallationTargetType, exists, err := attrs.stringAttribute(client.InstallationTargetTypeAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.InstallationTargetTypeAttribute)
	}
	installationTargetType, err := identity.ParseInstallationTargetType(rawInstallationTargetType)
	if err != nil {
		return nil, err
	}

	// if the scoped installation ID is not present, then this is definitely a plain old IntegrationInstallation
	if installationIDExists && !scopedInstallationIDExists {
		return identity.NewIntegrationInstallation(
			uint64(installationID),
			uint64(installationTargetID),
			installationTargetType,
		), nil
	}
	scopedInstallationType, exists, err := attrs.stringAttribute(client.ScopedInstallationTypeAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ScopedInstallationTypeAttribute)
	}

	switch scopedInstallationType {
	// ScopedIntegrationInstallation has a installation ID (the IntegrationInstallation ID) and a scoped installation ID
	case string(identity.InstallationTypeScopedIntegrationInstallation):
		if !installationIDExists {
			return nil, missingRequiredAttrError(client.InstallationIDAttribute)
		}
		if !scopedInstallationIDExists {
			return nil, missingRequiredAttrError(client.ScopedInstallationIDAttribute)
		}
		return identity.NewScopedIntegrationInstallation(
			uint64(installationID),
			uint64(scopedInstallationID),
			uint64(installationTargetID),
			installationTargetType,
		), nil
	// SiteScopedIntegrationInstallation only has a scoped installation ID
	case string(identity.InstallationTypeSiteScopedIntegrationInstallation):
		if !scopedInstallationIDExists {
			return nil, missingRequiredAttrError(client.ScopedInstallationIDAttribute)
		}
		return identity.NewSiteScopedIntegrationInstallation(
			uint64(scopedInstallationID),
			uint64(installationTargetID),
			installationTargetType,
		), nil
	default:
		return nil, errors.New("invalid scoped installation type")
	}
}
