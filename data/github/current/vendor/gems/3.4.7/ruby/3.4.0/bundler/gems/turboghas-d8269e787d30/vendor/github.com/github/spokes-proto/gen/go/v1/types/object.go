package types

import (
	"strings"

	"github.com/twitchtv/twirp"
)

func NewCommitObject(oid *ObjectID, size uint64) *Object {
	return &Object{Type: Object_TYPE_COMMIT, Oid: oid, Size: size}
}

func NewTreeObject(oid *ObjectID, size uint64) *Object {
	return &Object{Type: Object_TYPE_TREE, Oid: oid, Size: size}
}

func NewBlobObject(oid *ObjectID, size uint64) *Object {
	return &Object{Type: Object_TYPE_BLOB, Oid: oid, Size: size}
}

func NewTagObject(oid *ObjectID, size uint64) *Object {
	return &Object{Type: Object_TYPE_TAG, Oid: oid, Size: size}
}

func (o *Object) Validate() error {
	if o == nil {
		return nil
	}

	if o.GetType() == Object_TYPE_INVALID {
		return twirp.InvalidArgumentError("type", "must be set")
	}

	if !strings.HasPrefix(o.GetType().String(), "TYPE_") {
		return twirp.InvalidArgumentError("type", "must be commit, tree, blob or tag")
	}

	if o.GetOid() == nil {
		return twirp.RequiredArgumentError("oid")
	}

	if err := o.GetOid().Validate(); err != nil {
		return err
	}

	return nil
}

func (o *Object) IsCommit() bool {
	return o.Type == Object_TYPE_COMMIT
}

func (o *Object) IsTree() bool {
	return o.Type == Object_TYPE_TREE
}

func (o *Object) IsBlob() bool {
	return o.Type == Object_TYPE_BLOB
}

func (o *Object) IsTag() bool {
	return o.Type == Object_TYPE_TAG
}
