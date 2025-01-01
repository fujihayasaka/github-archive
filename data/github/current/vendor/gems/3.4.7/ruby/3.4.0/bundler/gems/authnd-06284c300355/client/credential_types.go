package client

import "fmt"

type CredentialType string

var (
	CredentialTypeUnknown CredentialType = "Unknown"

	// Maps to underlying UserActor
	CredentialTypeUserToServerToken              CredentialType = "UserToServerToken"
	CredentialTypeOauthApplicationAccessToken    CredentialType = "OAuthApplicationToken"
	CredentialTypeLegacyPersonalAccessToken      CredentialType = "PersonalAccessToken"
	CredentialTypeFineGrainedPersonalAccessToken CredentialType = "ProgrammaticAccessToken"
	CredentialTypeSignedAuthToken                CredentialType = "SignedAuthToken"

	// Maps to underlying UserActor or RepositoryActor
	CredentialTypeSSHPublicKey CredentialType = "SSHPublicKey"

	// Maps to underlying UserActor or OrganizationActor
	CredentialTypeOauthAppClientSecret CredentialType = "OauthAppClientSecret" //nolint:gosec // these are not hardcoded creds

	// Maps to underlying BotActor
	CredentialTypeServerToServerToken CredentialType = "ServerToServerToken"

	// Maps to underlying IntegrationActor
	CredentialTypeIntegrationToken CredentialType = "IntegrationToken" // JWT
)

func ParseCredentialType(val string) (CredentialType, error) {
	switch val {
	case string(CredentialTypeUserToServerToken):
		return CredentialTypeUserToServerToken, nil
	case string(CredentialTypeOauthApplicationAccessToken):
		return CredentialTypeOauthApplicationAccessToken, nil
	case string(CredentialTypeLegacyPersonalAccessToken):
		return CredentialTypeLegacyPersonalAccessToken, nil
	case string(CredentialTypeFineGrainedPersonalAccessToken):
		return CredentialTypeFineGrainedPersonalAccessToken, nil
	case string(CredentialTypeSSHPublicKey):
		return CredentialTypeSSHPublicKey, nil
	case string(CredentialTypeSignedAuthToken):
		return CredentialTypeSignedAuthToken, nil
	case string(CredentialTypeOauthAppClientSecret):
		return CredentialTypeOauthAppClientSecret, nil
	case string(CredentialTypeServerToServerToken):
		return CredentialTypeServerToServerToken, nil
	case string(CredentialTypeIntegrationToken):
		return CredentialTypeIntegrationToken, nil
	case string(CredentialTypeUnknown):
		return CredentialTypeUnknown, nil
	default:
		return "", fmt.Errorf("unknown CredentialType: %s", val)
	}
}
