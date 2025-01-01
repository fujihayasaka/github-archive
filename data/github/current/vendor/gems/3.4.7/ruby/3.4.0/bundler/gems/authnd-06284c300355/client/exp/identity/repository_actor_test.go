package identity

import (
	"testing"

	"github.com/github/authnd/client"
	"github.com/stretchr/testify/assert"
)

func TestNewRepositoryActorForSSHPublicKey(t *testing.T) {
	repositoryID := uint64(1)
	publicKeyID := uint64(101)

	repositoryActor := NewRepositoryActorForSSHPublicKey(repositoryID, publicKeyID, nil)

	assert.NotNil(t, repositoryActor)
	assert.Equal(t, repositoryID, repositoryActor.ID())
	assert.Equal(t, ActorTypeRepository, repositoryActor.Type())
	assert.NotNil(t, repositoryActor.actorContext)
	assert.Equal(t, repositoryID, repositoryActor.ID())

	sshPublicKeyContext, ok := repositoryActor.ActorContext().(*SSHPublicKeyContext)
	assert.True(t, ok)
	assert.Equal(t, publicKeyID, sshPublicKeyContext.PublicKeyID)
}

func TestRepositoryActorActorContext(t *testing.T) {
	repositoryID := uint64(1)
	publicKeyID := uint64(101)

	repositoryActor := NewRepositoryActorForSSHPublicKey(repositoryID, publicKeyID, nil)

	context := repositoryActor.ActorContext()
	assert.NotNil(t, context)

	sshPublicKeyContext, ok := context.(*SSHPublicKeyContext)
	assert.True(t, ok)
	assert.Equal(t, repositoryID, repositoryActor.ID())
	assert.Equal(t, publicKeyID, sshPublicKeyContext.PublicKeyID)
}

func TestRepositoryActorAuthenticatedCredentialType(t *testing.T) {
	repositoryID := uint64(1)
	publicKeyID := uint64(101)

	repositoryActor := NewRepositoryActorForSSHPublicKey(repositoryID, publicKeyID, nil)

	credType := repositoryActor.AuthenticatedCredentialType()
	assert.Equal(t, client.CredentialTypeSSHPublicKey, credType)
}
