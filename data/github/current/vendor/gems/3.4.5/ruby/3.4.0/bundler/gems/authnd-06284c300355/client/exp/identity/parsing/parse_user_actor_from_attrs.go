package parsing

import (
	"errors"
	"strconv"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
)

func parseUserActorFromAttrs(actorID uint64, actorType identity.ActorType, credentialID uint64, credentialType client.CredentialType, attrs *attrActorParser) (*identity.UserActor, error) {
	if actorType != identity.ActorTypeUser {
		return nil, errors.New("actor type is not user")
	}
	switch credentialType {
	case client.CredentialTypeUserToServerToken:
		return parseUserActorForUserToServerToken(actorID, credentialID, attrs)
	case client.CredentialTypeOauthApplicationAccessToken:
		return parseUserActorForOauthApplicationAccessToken(actorID, credentialID, attrs)
	case client.CredentialTypeLegacyPersonalAccessToken:
		return parseUserActorForLegacyPersonalAccessToken(actorID, credentialID, attrs)
	case client.CredentialTypeFineGrainedPersonalAccessToken:
		return parseUserActorForFineGrainedPersonalAccessToken(actorID, attrs)
	case client.CredentialTypeSSHPublicKey:
		return parseUserActorForSSHPublicKey(actorID, credentialID, attrs)
	case client.CredentialTypeSignedAuthToken:
		return parseUserActorForSignedAuthToken(actorID, credentialID, attrs)
	default:
		return nil, errors.New("credential type is not a supported user credential type")
	}
}

func parseUserActorForUserToServerToken(actorID uint64, credentialID uint64, attrs *attrActorParser) (*identity.UserActor, error) {
	installationIntegrationID, exists, err := attrs.int64Attribute(client.ApplicationIDAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ApplicationIDAttribute)
	}

	installationIntegrationOwnerID, exists, err := attrs.int64Attribute(client.ApplicationOwnerIDAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ApplicationOwnerIDAttribute)
	}

	rawInstallationIntegrationOwnerType, exists, err := attrs.stringAttribute(client.ApplicationOwnerTypeAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ApplicationOwnerTypeAttribute)
	}
	installationIntegrationOwnerType, err := identity.ParseApplicationOwnerType(rawInstallationIntegrationOwnerType)
	if err != nil {
		return nil, err
	}

	return identity.NewUserActorViaUserToServerToken(
		actorID,
		uint64(installationIntegrationID),
		uint64(installationIntegrationOwnerID),
		installationIntegrationOwnerType,
		uint64(credentialID),
		attrs.attrs,
	), nil
}

func parseUserActorForOauthApplicationAccessToken(actorID uint64, credentialID uint64, attrs *attrActorParser) (*identity.UserActor, error) {
	applicationID, exists, err := attrs.int64Attribute(client.ApplicationIDAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ApplicationIDAttribute)
	}

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

	scopes, exists, err := attrs.stringListAttribute(client.CredentialScopesAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.CredentialScopesAttribute)
	}

	return identity.NewUserActorViaOauthApplicationAccessToken(
		actorID,
		uint64(applicationID),
		uint64(appOwnerID),
		appOwnerType,
		uint64(credentialID),
		scopes,
		attrs.attrs,
	), nil
}

func parseUserActorForLegacyPersonalAccessToken(actorID uint64, credentialID uint64, attrs *attrActorParser) (*identity.UserActor, error) {
	scopes, exists, err := attrs.stringListAttribute(client.CredentialScopesAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.CredentialScopesAttribute)
	}

	createdAt, exists, err := attrs.timeAttribute(client.CredentialCreatedAtAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.CredentialCreatedAtAttribute)
	}

	var issuedAtPtr, expiresAtPtr *time.Time
	if issuedAt, exists, err := attrs.timeAttribute(client.CredentialIssuedAtAttribute); err != nil {
		return nil, err
	} else if exists && !issuedAt.IsZero() {
		issuedAtPtr = &issuedAt
	}

	if expiresAt, exists, err := attrs.timeAttribute(client.CredentialExpiresAtAttribute); err != nil {
		return nil, err
	} else if exists && !expiresAt.IsZero() {
		expiresAtPtr = &expiresAt
	}

	return identity.NewUserActorViaLegacyPersonalAccessToken(
		actorID,
		uint64(credentialID),
		scopes,
		createdAt,
		issuedAtPtr,
		expiresAtPtr,
		attrs.attrs,
	), nil
}

func parseUserActorForFineGrainedPersonalAccessToken(actorID uint64, attrs *attrActorParser) (*identity.UserActor, error) {
	issuedAt, exists, err := attrs.timeAttribute(client.CredentialIssuedAtAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.CredentialIssuedAtAttribute)
	}

	var expiresAtPtr *time.Time
	if expiresAt, exists, err := attrs.timeAttribute(client.CredentialExpiresAtAttribute); err != nil {
		return nil, err
	} else if exists && !expiresAt.IsZero() {
		expiresAtPtr = &expiresAt
	}

	programmaticAccessID, exists, err := attrs.int64Attribute(client.ProgrammaticAccessIDAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ProgrammaticAccessIDAttribute)
	}

	return identity.NewUserActorViaFineGrainedPersonalAccessToken(
		actorID,
		uint64(programmaticAccessID),
		issuedAt,
		expiresAtPtr,
		attrs.attrs,
	), nil
}

func parseUserActorForSSHPublicKey(actorID uint64, credentialID uint64, attrs *attrActorParser) (*identity.UserActor, error) {
	return identity.NewUserActorViaSSHPublicKey(
		actorID,
		credentialID,
		attrs.attrs,
	), nil
}

func parseUserActorForSignedAuthToken(actorID uint64, credentialID uint64, attrs *attrActorParser) (*identity.UserActor, error) {
	version, exists, err := attrs.stringAttribute(client.CredentialVersionAttribute)
	if err != nil {
		// falling back to supporting int attribute, for backwards compatibility while authnd server still provides it
		// as in int attribute result
		versionInt, _, err := attrs.int64Attribute(client.CredentialVersionAttribute)
		if err != nil {
			return nil, err
		}
		version = strconv.FormatInt(versionInt, 10)
	}
	if !exists || version == "" {
		return nil, missingRequiredAttrError(client.CredentialVersionAttribute)
	}

	expiresAt, exists, err := attrs.timeAttribute(client.CredentialExpiresAtAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.CredentialExpiresAtAttribute)
	}

	var sessionIDPtr *uint64
	sessionID, exists, err := attrs.int64Attribute(client.SessionIDAttribute)
	if err != nil {
		return nil, err
	} else if exists {
		sessionIDCast := uint64(sessionID)
		sessionIDPtr = &sessionIDCast
	}

	return identity.NewUserActorViaSignedAuthToken(
		actorID,
		version,
		expiresAt,
		sessionIDPtr,
		attrs.attrs,
	), nil
}
