package types

import (
	"regexp"

	"github.com/twitchtv/twirp"
)

const (
	nullOID       = "0000000000000000000000000000000000000000"
	nullOIDSHA256 = "0000000000000000000000000000000000000000000000000000000000000000"
)

var validObjectID = regexp.MustCompile(`^[a-f0-9]{40}(?:[a-f0-9]{24})?$`)

func NewObjectID(id string) *ObjectID {
	return &ObjectID{Id: id}
}

func (o *ObjectID) Validate() error {
	if o == nil {
		return nil
	}

	if o.Id == "" {
		return twirp.RequiredArgumentError("object_id.id")
	}

	if !validObjectID.MatchString(o.Id) {
		return twirp.InvalidArgumentError("object_id.id", "must be a valid object id")
	}

	return nil
}

func (o *ObjectID) IsNull() bool {
	if o == nil || o.Id == nullOID || o.Id == nullOIDSHA256 {
		return true
	}

	return false
}
