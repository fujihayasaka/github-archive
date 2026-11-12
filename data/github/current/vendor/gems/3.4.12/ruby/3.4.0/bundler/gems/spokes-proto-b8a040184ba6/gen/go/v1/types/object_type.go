package types

import (
	"strings"

	"github.com/twitchtv/twirp"
)

func NewObjectTypeFromTypeString(s string) *ObjectType {
	switch s {
	case "commit":
		return &ObjectType{Type: Object_TYPE_COMMIT}
	case "tree":
		return &ObjectType{Type: Object_TYPE_TREE}
	case "blob":
		return &ObjectType{Type: Object_TYPE_BLOB}
	case "tag":
		return &ObjectType{Type: Object_TYPE_TAG}
	default:
		return &ObjectType{Type: Object_TYPE_INVALID}
	}
}

func (o ObjectType) Validate() error {
	if o.GetType() == Object_TYPE_INVALID {
		return twirp.InvalidArgumentError("type", "must be commit, tree, blob or tag")
	}

	if !strings.HasPrefix(o.GetType().String(), "TYPE_") {
		return twirp.InvalidArgumentError("type", "must be commit, tree, blob or tag")
	}
	return nil
}
