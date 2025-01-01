package identity

import (
	"fmt"

	"github.com/github/authnd/client"
)

type OauthApplicationActorContext struct {
	OauthApplication *ApplicationContext
}

// OauthApplicationActor is an actor that represents an oauth application
// Authenticated by client_id and client_secret
type OauthApplicationActor struct {
	baseActor
	actorContext *OauthApplicationActorContext
}

var _ (Actor) = (*OauthApplicationActor)(nil)

// NewOauthApplicationActor creates a new OauthApplicationActor that had been authenticated via an oauth application client id/secret
//
// oauthApplicationID: the ID of the oauth application
// oauthApplicationOwnerID: the ID of the owner of the oauth application
// oauthApplicationOwnerType: the type of the owner of the oauth application
// attrs: the attributes used to build the actor
func NewOauthApplicationActor(oauthApplicationID uint64, oauthApplicationOwnerID uint64, oauthApplicationOwnerType ApplicationOwnerType, attrs map[string]interface{}) *OauthApplicationActor {
	return &OauthApplicationActor{
		baseActor: newBaseActor(oauthApplicationID, ActorTypeOauthApplication, client.CredentialTypeOauthAppClientSecret, attrs),
		actorContext: &OauthApplicationActorContext{
			OauthApplication: NewApplicationContext(oauthApplicationID, ApplicationTypeOauthApplication, oauthApplicationOwnerID, oauthApplicationOwnerType),
		},
	}
}

func (a *OauthApplicationActor) ActorContext() interface{} {
	return a.actorContext
}

func (a *OauthApplicationActor) Application() (*ApplicationContext, error) {
	if a.actorContext == nil || a.actorContext.OauthApplication == nil {
		return nil, fmt.Errorf("application context not available for oauth application actor %d", a.ID())
	}

	return a.actorContext.OauthApplication, nil
}
