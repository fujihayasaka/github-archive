package identity

import (
	"fmt"
	"testing"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/assert"
)

func TestNewOauthApplicationActor(t *testing.T) {
	oauthApplicationID := uint64(1)
	oauthApplicationOwnerID := uint64(2)
	oauthApplicationOwnerType := ApplicationOwnerTypeUser

	oauthApplicationActor := NewOauthApplicationActor(oauthApplicationID, oauthApplicationOwnerID, oauthApplicationOwnerType, nil)

	assert.NotNil(t, oauthApplicationActor)
	assert.Equal(t, oauthApplicationID, oauthApplicationActor.ID())
	assert.Equal(t, ActorTypeOauthApplication, oauthApplicationActor.Type())
	assert.NotNil(t, oauthApplicationActor.actorContext)
	assert.NotNil(t, oauthApplicationActor.actorContext.OauthApplication)
	assert.Equal(t, oauthApplicationID, oauthApplicationActor.actorContext.OauthApplication.ID)
}

func TestOauthApplicationActorActorContext(t *testing.T) {
	oauthApplicationID := uint64(1)
	oauthApplicationOwnerID := uint64(2)
	oauthApplicationOwnerType := ApplicationOwnerTypeUser

	oauthApplicationActor := NewOauthApplicationActor(oauthApplicationID, oauthApplicationOwnerID, oauthApplicationOwnerType, nil)

	context := oauthApplicationActor.ActorContext()
	assert.NotNil(t, context)

	oauthActorContext, ok := context.(*OauthApplicationActorContext)
	assert.True(t, ok)
	assert.NotNil(t, oauthActorContext.OauthApplication)
	assert.Equal(t, oauthApplicationID, oauthActorContext.OauthApplication.ID)
}

func TestOauthApplicationActorAuthenticatedCredentialType(t *testing.T) {
	oauthApplicationID := uint64(1)
	oauthApplicationOwnerID := uint64(2)
	oauthApplicationOwnerType := ApplicationOwnerTypeUser

	oauthApplicationActor := NewOauthApplicationActor(oauthApplicationID, oauthApplicationOwnerID, oauthApplicationOwnerType, nil)

	credType := oauthApplicationActor.AuthenticatedCredentialType()
	assert.Equal(t, client.CredentialTypeOauthAppClientSecret, credType)
}

func TestOauthApplicationActorApplication(t *testing.T) {
	oauthApplicationID := uint64(1)
	oauthApplicationOwnerID := uint64(2)
	oauthApplicationOwnerType := ApplicationOwnerTypeUser

	oauthApplicationActor := NewOauthApplicationActor(oauthApplicationID, oauthApplicationOwnerID, oauthApplicationOwnerType, nil)

	appContext, err := oauthApplicationActor.Application()
	assert.NoError(t, err)
	assert.NotNil(t, appContext)
	assert.Equal(t, oauthApplicationID, appContext.ID)
}

func TestOauthApplicationActorApplicationError(t *testing.T) {
	// Test when application context is not available (e.g., nil)
	oauthApplicationActor := &OauthApplicationActor{
		baseActor: newBaseActor(1, ActorTypeOauthApplication, client.CredentialTypeOauthAppClientSecret, nil),
	}

	_, err := oauthApplicationActor.Application()
	assert.Error(t, err)
	assert.EqualError(t, err, fmt.Sprintf("application context not available for oauth application actor %d", oauthApplicationActor.ID()))
}
