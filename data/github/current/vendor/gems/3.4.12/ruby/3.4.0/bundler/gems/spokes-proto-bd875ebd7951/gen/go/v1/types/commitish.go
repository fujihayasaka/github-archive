package types

import (
	"github.com/twitchtv/twirp"
)

func NewCommitishWithObjectID(oid *ObjectID) *Commitish {
	return &Commitish{Commitish: &Commitish_Oid{Oid: oid}}
}

func NewCommitishWithReference(reference *Reference) *Commitish {
	return &Commitish{Commitish: &Commitish_Reference{Reference: reference}}
}

func NewCommitishWithRevision(revision *Revision) *Commitish {
	return &Commitish{Commitish: &Commitish_Revision{Revision: revision}}
}

func (t *Commitish) Validate() error {
	if t == nil {
		return nil
	}

	switch tt := t.GetCommitish().(type) {
	case *Commitish_Oid:
		if tt.Oid == nil {
			return twirp.RequiredArgumentError("commitish.oid")
		}
		return tt.Oid.Validate()
	case *Commitish_Reference:
		if tt.Reference == nil {
			return twirp.RequiredArgumentError("commitish.reference")
		}
		return tt.Reference.Validate()
	case *Commitish_Revision:
		if tt.Revision == nil {
			return twirp.RequiredArgumentError("commitish.revision")
		}
		return tt.Revision.Validate()
	default:
		return twirp.RequiredArgumentError("commitish")
	}

	return nil
}
