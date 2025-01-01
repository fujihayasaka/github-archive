package types

import (
	"github.com/twitchtv/twirp"
)

func NewTreeishWithObjectID(oid *ObjectID) *Treeish {
	return &Treeish{Treeish: &Treeish_Oid{Oid: oid}}
}

func NewTreeishWithReference(reference *Reference) *Treeish {
	return &Treeish{Treeish: &Treeish_Reference{Reference: reference}}
}

func (t *Treeish) Validate() error {
	if t == nil {
		return nil
	}

	switch tt := t.GetTreeish().(type) {
	case *Treeish_Oid:
		if tt.Oid == nil {
			return twirp.RequiredArgumentError("treeish.oid")
		}
		return tt.Oid.Validate()
	case *Treeish_Reference:
		if tt.Reference == nil {
			return twirp.RequiredArgumentError("treeish.reference")
		}
		return tt.Reference.Validate()
	default:
		return twirp.RequiredArgumentError("treeish")
	}

	return nil
}
