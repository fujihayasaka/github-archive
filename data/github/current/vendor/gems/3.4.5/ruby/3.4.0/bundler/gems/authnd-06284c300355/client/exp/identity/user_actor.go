package identity

import (
	"errors"
	"time"

	"github.com/github/authnd/client"
)

// UserActor is an actor that represents a user
// Authenticated through a session, ssh public key, PAT, or oauth access token
type UserActor struct {
	baseActor
	actorContext interface{}
}

var _ (Actor) = (*UserActor)(nil)

// NewUserActorNoContext creates a new UserActor that does not have additional actor context
//
// userID: the ID of the user
func NewUserActorNoContext(userID uint64) *UserActor {
	return &UserActor{
		baseActor: newBaseActor(userID, ActorTypeUser, client.CredentialTypeUnknown, nil),
	}
}

// NewUserActorViaUserToServerToken creates a new UserActor that had been authenticated via a user-to-server token
// with the proper actor context
//
// userID: the ID of the user
// applicationID: the ID of the application
// applicationOwnerID: the ID of the owner of the application
// applicationOwnerType: the type of the owner of the application
// ouathAccessID: the ID of the oauth access token
func NewUserActorViaUserToServerToken(userID uint64, applicationID uint64, applicationOwnerID uint64, applicationOwnerType ApplicationOwnerType, ouathAccessID uint64, attrs map[string]interface{}) *UserActor {
	return &UserActor{
		baseActor: newBaseActor(userID, ActorTypeUser, client.CredentialTypeUserToServerToken, attrs),
		actorContext: &UserToServerActorContext{
			OauthAccess: &OauthAccessContext{
				OauthAccessID: ouathAccessID,
				Scopes:        nil, // user to server tokens do not have scopes
				Application:   NewApplicationContext(applicationID, ApplicationTypeIntegration, applicationOwnerID, applicationOwnerType),
			},
		},
	}
}

// NewUserActorViaOauthApplicationAccessToken creates a new UserActor that had been authenticated via an oauth access token from an oauth application
// with the proper actor context
//
// userID: the ID of the user
// applicationID: the ID of the application
// applicationOwnerID: the ID of the owner of the application
// applicationOwnerType: the type of the owner of the application
// oauthAccessID: the ID of the oauth access token
// scopes: the scopes of the oauth access token
func NewUserActorViaOauthApplicationAccessToken(userID uint64, applicationID uint64, applicationOwnerID uint64, applicationOwnerType ApplicationOwnerType, oauthAccessID uint64, scopes []string, attrs map[string]interface{}) *UserActor {
	return &UserActor{
		baseActor: newBaseActor(userID, ActorTypeUser, client.CredentialTypeOauthApplicationAccessToken, attrs),
		actorContext: &OauthAccessContext{
			OauthAccessID: oauthAccessID,
			Scopes:        scopes,
			Application:   NewApplicationContext(applicationID, ApplicationTypeOauthApplication, applicationOwnerID, applicationOwnerType),
		},
	}
}

// NewUserActorViaFineGrainedPersonalAccessToken creates a new UserActor that had been authenticated via a fine grained personal access token (aka programmatic access token)
// with the proper actor context
//
// userID: the ID of the user
// programmaticAccessID: the ID of the programmatic access token
// issuedAt: the time the programmatic access token was issued
// expiresAt: the time the programmatic access token will expire, or nil for no expiration
func NewUserActorViaFineGrainedPersonalAccessToken(userID uint64, programmaticAccessID uint64, issuedAt time.Time, expiresAt *time.Time, attrs map[string]interface{}) *UserActor {
	return &UserActor{
		baseActor: newBaseActor(userID, ActorTypeUser, client.CredentialTypeFineGrainedPersonalAccessToken, attrs),
		actorContext: &FineGrainedPersonalAccessTokenActorContext{
			ProgrammaticAccessID: programmaticAccessID,
			IssuedAt:             issuedAt,
			ExpiresAt:            expiresAt,
		},
	}
}

// NewUserActorViaLegacyPersonalAccessToken creates a new UserActor that had been authenticated via a legacy personal access token
// with the proper actor context
//
// userID: the ID of the user
// oauthAccessID: the ID of the oauth access
// scopes: the scopes of the oauth access token
// createdAt: the time the programmatic access token was issued
// issuedAt: the time the programmatic access token was issued (may be nil for no issued at time)
// expiresAt: the time the programmatic access token will expire, or nil for no expiration
func NewUserActorViaLegacyPersonalAccessToken(userID uint64, oauthAccessID uint64, scopes []string, createdAt time.Time, issuedAt *time.Time, expiresAt *time.Time, attrs map[string]interface{}) *UserActor {
	return &UserActor{
		baseActor: newBaseActor(userID, ActorTypeUser, client.CredentialTypeLegacyPersonalAccessToken, attrs),
		actorContext: &OauthAccessContext{
			OauthAccessID: oauthAccessID,
			Scopes:        scopes,
			CreatedAt:     createdAt,
			IssuedAt:      issuedAt,
			ExpiresAt:     expiresAt,
			Application:   NewApplicationContext(PersonalAccessTokenApplicationID, ApplicationTypeOauthApplication, 0, ""),
		},
	}
}

// NewUserActorViaSSHPublicKey creates a new UserActor that had been authenticated via SSH public key
// with the proper actor context
//
// userID: the ID of the user
// publicKeyID: the ID of the public key used to authenticate the user
func NewUserActorViaSSHPublicKey(userID uint64, publicKeyID uint64, attrs map[string]interface{}) *UserActor {
	return &UserActor{
		baseActor: newBaseActor(userID, ActorTypeUser, client.CredentialTypeSSHPublicKey, attrs),
		actorContext: &SSHPublicKeyContext{
			PublicKeyID: publicKeyID,
		},
	}
}

// NewUserActorViaSignedAuthToken creates a new UserActor that had been authenticated via a signed auth token
// with the proper actor context
//
// userID: the ID of the user
// version: the version of the signed auth token
// expiresAt: the time the signed auth token will expire
// sessionID: the ID of the session (may be nil if not a session sat)
func NewUserActorViaSignedAuthToken(userID uint64, version string, expiresAt time.Time, sessionID *uint64, attrs map[string]interface{}) *UserActor {
	return &UserActor{
		baseActor: newBaseActor(userID, ActorTypeUser, client.CredentialTypeSignedAuthToken, attrs),
		actorContext: &SignedAuthTokenActorContext{
			Version:   version,
			ExpiresAt: expiresAt,
			SessionID: sessionID,
		},
	}
}

func (u *UserActor) ActorContext() interface{} {
	return u.actorContext
}

func (u *UserActor) OauthAccess() (*OauthAccessContext, error) {
	if u.IsAuthenticatedViaUserToServerToken() {
		userToServerCtx, ok := u.actorContext.(*UserToServerActorContext)
		if !ok {
			return nil, errors.New("unexpected authentication context type")
		}
		return userToServerCtx.OauthAccess, nil
	}
	if u.IsAuthenticatedViaOauthApplicationAccessToken() || u.IsAuthenticatedViaLegacyPersonalAccessToken() {
		oauthAccessCtx, ok := u.actorContext.(*OauthAccessContext)
		if !ok {
			return nil, errors.New("unexpected authentication context type")
		}
		return oauthAccessCtx, nil
	}
	return nil, nil
}

func (u *UserActor) SSHPublicKey() (*SSHPublicKeyContext, error) {
	if u.IsAuthenticatedViaSSHPublicKey() {
		sshPublicKeyCtx, ok := u.actorContext.(*SSHPublicKeyContext)
		if !ok {
			return nil, errors.New("unexpected actor context type for user actor with ssh public key credential type")
		}
		return sshPublicKeyCtx, nil
	}
	return nil, nil
}
