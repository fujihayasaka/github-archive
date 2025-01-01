package parsing

import (
	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
)

func parseOauthApplicationActorFromAttrs(attrs *attrActorParser) (*identity.OauthApplicationActor, error) {
	applicationID, exists, err := attrs.int64Attribute(client.ApplicationIDAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ApplicationIDAttribute)
	}

	appOwnerID, exists, err := attrs.int64Attribute(client.ApplicationOwnerIDAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ApplicationOwnerIDAttribute)
	}

	rawAppOwnerType, exists, err := attrs.stringAttribute(client.ApplicationOwnerTypeAttribute)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, missingRequiredAttrError(client.ApplicationOwnerTypeAttribute)
	}
	appOwnerType, err := identity.ParseApplicationOwnerType(rawAppOwnerType)
	if err != nil {
		return nil, err
	}

	return identity.NewOauthApplicationActor(
		uint64(applicationID),
		uint64(appOwnerID),
		appOwnerType,
		attrs.attrs,
	), nil
}
