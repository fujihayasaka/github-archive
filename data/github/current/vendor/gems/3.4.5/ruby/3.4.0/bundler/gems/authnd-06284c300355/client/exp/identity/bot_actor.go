package identity

import (
	"fmt"

	"github.com/github/authnd/client"
)

type BotActorContext struct {
	Integration  *ApplicationContext
	Installation *InstallationContext
}

// BotActor is an actor that represents a bot
// This means the actor is acting as an installation of an integration
// Authenticated through a server-to-server token
type BotActor struct {
	baseActor
	actorContext *BotActorContext
}

var _ (Actor) = (*BotActor)(nil)

func (b *BotActor) ActorContext() interface{} {
	return b.actorContext
}

// NewBotActor creates a new BotActor
//
// botID: the ID of the bot (not to be confused with the integration ID)
// applicationContext: the context of the application
// installationContext: the context of the installation
// attrs: the attributes used to build the actor
func NewBotActor(botID uint64, applicationContext *ApplicationContext, installationContext *InstallationContext, attrs map[string]interface{}) (*BotActor, error) {
	if installationContext != nil && !installationContext.isValid() {
		return nil, fmt.Errorf("invalid installation context for bot actor %d", botID)
	}
	return &BotActor{
		baseActor: newBaseActor(botID, ActorTypeBot, client.CredentialTypeServerToServerToken, attrs),
		actorContext: &BotActorContext{
			Integration:  applicationContext,
			Installation: installationContext,
		},
	}, nil
}

func (b *BotActor) Application() (*ApplicationContext, error) {
	if b.actorContext == nil {
		return nil, fmt.Errorf("application context not available for bot actor %d", b.ID())
	}
	return b.actorContext.Integration, nil
}
