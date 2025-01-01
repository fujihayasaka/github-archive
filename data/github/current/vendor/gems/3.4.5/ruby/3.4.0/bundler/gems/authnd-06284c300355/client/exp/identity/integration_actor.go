package identity

import (
	"fmt"

	"github.com/github/authnd/client"
)

type IntegrationActorContext struct {
	Integration *ApplicationContext
}

// IntegrationActor is an actor that represents an integration
// Authenticated via JWT
type IntegrationActor struct {
	baseActor
	actorContext *IntegrationActorContext
}

var _ (Actor) = (*IntegrationActor)(nil)

// NewIntegrationActor creates a new IntegrationActor
//
// integrationID is the ID of the integration
// integrationOwnerID is the ID of the owner of the integration
// integrationOwnerType is the type of the owner of the integration
// attrs is the attributes used to build the actor
func NewIntegrationActor(integrationID uint64, integrationOwnerID uint64, integrationOwnerType ApplicationOwnerType, attrs map[string]interface{}) *IntegrationActor {
	return &IntegrationActor{
		baseActor: newBaseActor(integrationID, ActorTypeIntegration, client.CredentialTypeIntegrationToken, attrs),
		actorContext: &IntegrationActorContext{
			Integration: NewApplicationContext(integrationID, ApplicationTypeIntegration, integrationOwnerID, integrationOwnerType),
		},
	}
}

func (i *IntegrationActor) ActorContext() interface{} {
	return i.actorContext
}

func (i *IntegrationActor) Application() (*ApplicationContext, error) {
	if i.actorContext == nil || i.actorContext.Integration == nil {
		return nil, fmt.Errorf("application context not available for integration actor %d", i.ID())
	}
	return i.actorContext.Integration, nil
}
