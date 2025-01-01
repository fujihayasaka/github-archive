package identity

import (
	"testing"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/assert"
)

func TestNewIntegrationActor(t *testing.T) {
	integrationID := uint64(1)
	integrationOwnerID := uint64(2)
	integrationOwnerType := ApplicationOwnerTypeUser

	integrationActor := NewIntegrationActor(integrationID, integrationOwnerID, integrationOwnerType, nil)

	assert.NotNil(t, integrationActor)
	assert.Equal(t, integrationID, integrationActor.ID())
	assert.Equal(t, ActorTypeIntegration, integrationActor.Type())
	assert.NotNil(t, integrationActor.actorContext)
	assert.NotNil(t, integrationActor.actorContext.Integration)
	assert.Equal(t, integrationID, integrationActor.actorContext.Integration.ID)
}

func TestIntegrationActorActorContext(t *testing.T) {
	integrationID := uint64(1)
	integrationOwnerID := uint64(2)
	integrationOwnerType := ApplicationOwnerTypeUser

	integrationActor := NewIntegrationActor(integrationID, integrationOwnerID, integrationOwnerType, nil)

	context := integrationActor.ActorContext()
	assert.NotNil(t, context)

	integrationActorContext, ok := context.(*IntegrationActorContext)
	assert.True(t, ok)
	assert.NotNil(t, integrationActorContext.Integration)
	assert.Equal(t, integrationID, integrationActorContext.Integration.ID)
}

func TestIntegrationActorAuthenticatedCredentialType(t *testing.T) {
	integrationID := uint64(1)
	integrationOwnerID := uint64(2)
	integrationOwnerType := ApplicationOwnerTypeUser

	integrationActor := NewIntegrationActor(integrationID, integrationOwnerID, integrationOwnerType, nil)

	credType := integrationActor.AuthenticatedCredentialType()
	assert.Equal(t, client.CredentialTypeIntegrationToken, credType)
}

func TestIntegrationActorApplication(t *testing.T) {
	integrationID := uint64(1)
	integrationOwnerID := uint64(2)
	integrationOwnerType := ApplicationOwnerTypeUser

	integrationActor := NewIntegrationActor(integrationID, integrationOwnerID, integrationOwnerType, nil)

	appContext, err := integrationActor.Application()
	assert.NoError(t, err)
	assert.NotNil(t, appContext)
	assert.Equal(t, integrationID, appContext.ID)
}
