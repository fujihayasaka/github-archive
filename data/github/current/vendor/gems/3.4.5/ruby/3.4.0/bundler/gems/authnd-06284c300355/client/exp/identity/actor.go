package identity

import (
	"github.com/github/authnd/client"
)

type baseActor interface {
	// ID returns the ID of the actor
	ID() uint64

	// Type returns the type of the actor (user, bot, repository, integration, oauth application)
	Type() ActorType

	// AuthenticatedCredentialType returns the type of the credential used to authenticate the actor
	AuthenticatedCredentialType() client.CredentialType

	// IsUser returns true if the actor is a user
	// Authenticated through a session, ssh public key, PAT, or oauth access token
	IsUser() bool

	// IsBot returns true if the actor is a bot
	// This means the actor is acting as an installation of an integration
	// Authenticated through a server-to-server token
	IsBot() bool

	// IsRepository returns true if the actor is a repository
	// Authenticated via deploy key (ssh key scoped to a repository)
	IsRepository() bool

	// IsIntegration returns true if the actor is an integration
	// Authenticated via JWT
	IsIntegration() bool

	// IsOauthApplication returns true if the actor is an oauth application
	// Authenticated by client_id and client_secret
	IsOauthApplication() bool

	// OauthAccess returns oauth access context if it is available for the actor
	// Returns nil if the context is not available
	OauthAccess() (*OauthAccessContext, error)

	// Application returns application context if it is available for the actor
	// Returns nil if the context is not available
	Application() (*ApplicationContext, error)

	// SSHPublicKey returns ssh public key context if it is available for the actor
	// Returns nil if the context is not available
	SSHPublicKey() (*SSHPublicKeyContext, error)

	IsAuthenticatedViaUserToServerToken() bool
	IsAuthenticatedViaOauthApplicationAccessToken() bool
	IsAuthenticatedViaFineGrainedPersonalAccessToken() bool
	IsAuthenticatedViaLegacyPersonalAccessToken() bool
	IsAuthenticatedViaSSHPublicKey() bool
	IsAuthenticatedViaServerToServerToken() bool
	IsAuthenticatedViaIntegrationToken() bool
	IsAuthenticatedViaOauthAppClientSecret() bool
	IsAuthenticatedViaSignedAuthToken() bool

	// Attributes returns the original attributes used to build the actor
	Attributes() map[string]interface{}
}

type Actor interface {
	baseActor
	ActorContext() interface{}
}

type actor struct {
	id             uint64
	actorType      ActorType
	credentialType client.CredentialType
	attributes     map[string]interface{}
}

func newBaseActor(id uint64, actorType ActorType, credentialType client.CredentialType, attributes map[string]interface{}) baseActor {
	return &actor{
		id:             id,
		actorType:      actorType,
		credentialType: credentialType,
		attributes:     attributes,
	}
}

var _ baseActor = (*actor)(nil)

// ID returns the ID of the actor
func (a *actor) ID() uint64 {
	return a.id
}

// Type returns the type of the actor (user, bot, repository, integration, oauth application)
func (a *actor) Type() ActorType {
	return a.actorType
}

// CredentialType returns the type of the credential used to authenticate the actor
func (a *actor) AuthenticatedCredentialType() client.CredentialType {
	return a.credentialType
}

// IsUser returns true if the actor is a user
// Authenticated through a session, ssh public key, PAT, or oauth access token
func (a *actor) IsUser() bool {
	return a.actorType == ActorTypeUser
}

// IsBot returns true if the actor is a bot
// This means the actor is acting as an installation of an integration
// Authenticated through a server-to-server token
func (a *actor) IsBot() bool {
	return a.actorType == ActorTypeBot
}

// IsRepository returns true if the actor is a repository
// Authenticated via deploy key (ssh key scoped to a repository)
func (a *actor) IsRepository() bool {
	return a.actorType == ActorTypeRepository
}

// IsIntegration returns true if the actor is an integration
// Authenticated via JWT
func (a *actor) IsIntegration() bool {
	return a.actorType == ActorTypeIntegration
}

// IsOauthApplication returns true if the actor is an oauth application
// Authenticated by client_id and client_secret
func (a *actor) IsOauthApplication() bool {
	return a.actorType == ActorTypeOauthApplication
}

// OauthAccess returns oauth access context if it is available for the actor
// Returns nil if the context is not available
func (a *actor) OauthAccess() (*OauthAccessContext, error) {
	return nil, nil
}

// Application returns application context if it is available for the actor
// Returns nil if the context is not available
func (a *actor) Application() (*ApplicationContext, error) {
	return nil, nil
}

// SSHPublicKey returns ssh public key context if it is available for the actor
// Returns nil if the context is not available
func (a *actor) SSHPublicKey() (*SSHPublicKeyContext, error) {
	return nil, nil
}

func (a *actor) IsAuthenticatedViaUserToServerToken() bool {
	return a.actorType == ActorTypeUser && a.credentialType == client.CredentialTypeUserToServerToken
}

func (a *actor) IsAuthenticatedViaOauthApplicationAccessToken() bool {
	return a.actorType == ActorTypeUser && a.credentialType == client.CredentialTypeOauthApplicationAccessToken
}

func (a *actor) IsAuthenticatedViaFineGrainedPersonalAccessToken() bool {
	return a.actorType == ActorTypeUser && a.credentialType == client.CredentialTypeFineGrainedPersonalAccessToken
}

func (a *actor) IsAuthenticatedViaLegacyPersonalAccessToken() bool {
	return a.actorType == ActorTypeUser && a.credentialType == client.CredentialTypeLegacyPersonalAccessToken
}

func (a *actor) IsAuthenticatedViaSSHPublicKey() bool {
	return (a.actorType == ActorTypeUser || a.actorType == ActorTypeRepository) && a.credentialType == client.CredentialTypeSSHPublicKey
}

func (a *actor) IsAuthenticatedViaServerToServerToken() bool {
	return a.actorType == ActorTypeBot && a.credentialType == client.CredentialTypeServerToServerToken
}

func (a *actor) IsAuthenticatedViaIntegrationToken() bool {
	return a.actorType == ActorTypeIntegration && a.credentialType == client.CredentialTypeIntegrationToken
}

func (a *actor) IsAuthenticatedViaOauthAppClientSecret() bool {
	return a.actorType == ActorTypeOauthApplication && a.credentialType == client.CredentialTypeOauthAppClientSecret
}

func (a *actor) IsAuthenticatedViaSignedAuthToken() bool {
	return a.credentialType == client.CredentialTypeSignedAuthToken
}

func (a *actor) Attributes() map[string]interface{} {
	return a.attributes
}
