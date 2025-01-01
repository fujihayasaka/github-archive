package parsing

import (
	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
)

func ActorFromAuthenticateAttributes[A Attributes](rawAttrs A) (identity.Actor, error) {
	attrActorParser, err := newAttrActorParser(rawAttrs)
	if err != nil {
		return nil, err
	}
	return attrActorParser.Actor()
}

// Passing in verifier for now, but could eventually be a function on the verifier itself
func ActorFromExchangeToken(exhangeToken string, verifier *client.ExchangeTokenVerifier) (identity.Actor, error) {
	attrs, err := verifier.VerifyToken(exhangeToken)
	if err != nil {
		return nil, err
	}
	return ActorFromAuthenticateAttributes(attrs)
}
