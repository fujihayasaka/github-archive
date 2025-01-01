package parsing

import (
	"errors"

	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
)

func parseRepositoryActorFromSSHPublicKeyAttrs(actorID uint64, actorType identity.ActorType, credentialID uint64, credentialType client.CredentialType, attrs *attrActorParser) (*identity.RepositoryActor, error) {
	if actorType != identity.ActorTypeRepository {
		return nil, errors.New("actor type is not repository")
	}
	if credentialType != client.CredentialTypeSSHPublicKey {
		return nil, errors.New("credential type is not deploy key")
	}
	return identity.NewRepositoryActorForSSHPublicKey(
		actorID,
		credentialID,
		attrs.attrs,
	), nil
}
