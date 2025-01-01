package parsing

import (
	"errors"
	"fmt"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/client/exp/identity"
	pb "github.com/github/authnd/client/proto/authentication/v0"
)

type attrActorParser struct {
	attrs map[string]interface{}
}

// Attribute generic type which supports the the attribute types of the AuthenticateResponse
// from the RPC service and client package (resp).
type Attributes interface {
	~[]*pb.Attribute | ~map[string]interface{}
}

func newAttrActorParser[A Attributes](attributes A) (*attrActorParser, error) {
	if attributes == nil {
		return nil, errors.New("attributes cannot be nil")
	}

	if attrs, ok := any(attributes).(map[string]interface{}); ok {
		return &attrActorParser{attrs}, nil
	}

	attrs := make(map[string]interface{})
	for _, a := range any(attributes).([]*pb.Attribute) {
		v, err := a.GetValue().Unwrap()
		if err != nil {
			return nil, err
		}
		attrs[a.GetId()] = v
	}
	return &attrActorParser{attrs}, nil
}

func (a *attrActorParser) Actor() (identity.Actor, error) {
	actor, err := a.requiredIDAndTypeAttributePair(client.ActorIDAttribute, client.ActorTypeAttribute)
	if err != nil {
		return nil, err
	}
	actorType, err := identity.ParseActorType(actor.typ)
	if err != nil {
		return nil, fmt.Errorf("unsupported value for attribute type %s, received %s", client.ActorTypeAttribute, actor.typ)
	}
	actorID := uint64(actor.id)

	credentialID, _, err := a.int64Attribute(client.CredentialIDAttribute)
	if err != nil {
		return nil, err
	}
	rawCredentialType, exists, err := a.stringAttribute(client.CredentialTypeAttribute)
	if err != nil {
		return nil, err
	}
	var credentialType client.CredentialType
	if exists {
		credentialType, err = client.ParseCredentialType(rawCredentialType)
		if err != nil {
			return nil, fmt.Errorf("unsupported value for attribute type %s, received %s", client.CredentialTypeAttribute, rawCredentialType)
		}
	} else {
		credentialType = client.CredentialTypeUnknown
	}

	switch credentialType {
	case client.CredentialTypeUserToServerToken,
		client.CredentialTypeOauthApplicationAccessToken,
		client.CredentialTypeLegacyPersonalAccessToken,
		client.CredentialTypeFineGrainedPersonalAccessToken,
		client.CredentialTypeSignedAuthToken:
		return parseUserActorFromAttrs(actorID, actorType, uint64(credentialID), credentialType, a)
	case client.CredentialTypeServerToServerToken:
		return parseBotActorFromAttrs(actorID, actorType, a)
	case client.CredentialTypeIntegrationToken:
		return parseIntegrationActorFromAttrs(a)
	case client.CredentialTypeOauthAppClientSecret:
		return parseOauthApplicationActorFromAttrs(a)
	case client.CredentialTypeSSHPublicKey:
		if actorType == identity.ActorTypeUser {
			return parseUserActorForSSHPublicKey(actorID, uint64(credentialID), a)
		}
		if actorType == identity.ActorTypeRepository {
			return parseRepositoryActorFromSSHPublicKeyAttrs(actorID, actorType, uint64(credentialID), credentialType, a)
		}
		return nil, errors.New("actor type is not user or repository")
	case client.CredentialTypeUnknown:
		if actorType != identity.ActorTypeUser {
			return nil, errors.New("actor type must be a user to support unknown credential type")
		}
		return identity.NewUserActorNoContext(actorID), nil
	default:
		return nil, errors.New("credential type is not an expected type")
	}
}

func (a *attrActorParser) attribute(name string) (interface{}, bool, error) {
	value, ok := a.attrs[name]
	if ok {
		return value, true, nil
	}
	return nil, false, nil
}

func (a *attrActorParser) int64Attribute(attrName string) (int64, bool, error) {
	intVal, present, err := a.attribute(attrName)
	if err != nil {
		return 0, present, err
	}
	if !present || intVal == nil {
		return 0, present, nil
	}
	if _, ok := intVal.(int64); ok {
		returnVal := intVal.(int64)
		if returnVal < 0 {
			return 0, present, errors.New("attribute value must be greater than or equal to 0")
		}
		return returnVal, present, nil
	}
	return 0, present, invalidAttributeTypeError(attrName, "int64", intVal)
}

func (a *attrActorParser) stringAttribute(attrName string) (string, bool, error) {
	stringVal, present, err := a.attribute(attrName)
	if err != nil {
		return "", present, err
	}
	if !present || stringVal == nil {
		return "", present, nil
	}
	if _, ok := stringVal.(string); ok {
		return stringVal.(string), present, nil
	}
	return "", present, invalidAttributeTypeError(attrName, "string", stringVal)
}

func (a *attrActorParser) stringListAttribute(attrName string) ([]string, bool, error) {
	stringList, present, err := a.attribute(attrName)
	if err != nil {
		return nil, present, err
	}
	if !present || stringList == nil {
		return nil, present, nil
	}
	if _, ok := stringList.([]string); ok {
		return stringList.([]string), present, nil
	} else if list, ok := stringList.([]int64); ok && len(list) == 0 {
		// this is odd, but sometimes the list is empty and we get an int64 slice
		return []string{}, present, nil
	}
	return nil, present, invalidAttributeTypeError(attrName, "[]string", stringList)
}

func (a *attrActorParser) timeAttribute(attrName string) (time.Time, bool, error) {
	timeVal, exists, err := a.attribute(attrName)
	if err != nil {
		return time.Time{}, exists, err
	}
	if timeVal == nil {
		return time.Time{}, exists, nil
	}
	if v, ok := timeVal.(time.Time); ok {
		return v, exists, nil
	}
	return time.Time{}, exists, invalidAttributeTypeError(attrName, "time.Time", timeVal)
}

type idAndType struct {
	id  int64
	typ string
}

func (a *attrActorParser) requiredIDAndTypeAttributePair(idAttr, typeAttr string) (*idAndType, error) {
	id, present, err := a.int64Attribute(idAttr)
	if err != nil {
		return nil, err
	}
	if !present {
		return nil, missingRequiredAttrError(idAttr)
	}
	rawType, present, err := a.stringAttribute(typeAttr)
	if err != nil {
		return nil, err
	}
	if !present {
		return nil, missingRequiredAttrError(typeAttr)
	}
	return &idAndType{id: id, typ: rawType}, nil
}
