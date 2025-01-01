package identity

import (
	"errors"

	"github.com/github/authnd/client"
)

// RepositoryActor is an actor that represents a repository
// Authenticated via deploy key (ssh key scoped to a repository)
type RepositoryActor struct {
	baseActor
	actorContext interface{}
}

var _ (Actor) = (*RepositoryActor)(nil)

// NewRepositoryActorNoContext creates a new RepositoryActor that does not have additional actor context
//
// repositoryID: the ID of the repository
func NewRepositoryActorNoContext(repositoryID uint64) *RepositoryActor {
	return &RepositoryActor{
		baseActor: newBaseActor(repositoryID, ActorTypeRepository, client.CredentialTypeUnknown, nil),
	}
}

// NewRepositoryActorForSSHPublicKey creates a new RepositoryActor that has been authenticated via a ssh public key for a repository
//
// repositoryID: the ID of the repository
// publicKeyID: the ID of the public key
// attrs: the attributes used to build the actor
func NewRepositoryActorForSSHPublicKey(repositoryID uint64, publicKeyID uint64, attrs map[string]interface{}) *RepositoryActor {
	return &RepositoryActor{
		baseActor: newBaseActor(repositoryID, ActorTypeRepository, client.CredentialTypeSSHPublicKey, attrs),
		actorContext: &SSHPublicKeyContext{
			PublicKeyID: publicKeyID,
		},
	}
}

func (r *RepositoryActor) ActorContext() interface{} {
	return r.actorContext
}

// SSHPublicKey returns ssh public key context if it is available for the actor
// Returns nil if the context is not available
func (r *RepositoryActor) SSHPublicKey() (*SSHPublicKeyContext, error) {
	if r.IsAuthenticatedViaSSHPublicKey() {
		sshPublicKeyCtx, ok := r.actorContext.(*SSHPublicKeyContext)
		if !ok {
			return nil, errors.New("unexpected actor context type for repository actor with ssh public key credential type")
		}
		return sshPublicKeyCtx, nil
	}
	return nil, nil
}
