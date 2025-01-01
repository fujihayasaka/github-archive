package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewTreeishWithObjectID(t *testing.T) {
	id := NewObjectID(oid)
	tt := NewTreeishWithObjectID(id)
	require.Equal(t, &Treeish{Treeish: &Treeish_Oid{Oid: id}}, tt)
}

func TestNewTreeishWithReference(t *testing.T) {
	ref := NewReference([]byte("refs/heads/main"))
	tt := NewTreeishWithReference(ref)
	require.Equal(t, &Treeish{Treeish: &Treeish_Reference{Reference: ref}}, tt)
}

func TestNewTreeishWithRevision(t *testing.T) {
	rev := NewRevision([]byte("main"))
	tt := NewTreeishWithRevision(rev)
	require.Equal(t, &Treeish{Treeish: &Treeish_Revision{Revision: rev}}, tt)
}

func TestTreeishValidateErrors(t *testing.T) {
	var tests = []struct {
		name    string
		treeish *Treeish
		err     string
	}{
		{"empty", &Treeish{}, "twirp error invalid_argument: treeish is required"},
		{"missing object id", &Treeish{Treeish: &Treeish_Oid{}}, "twirp error invalid_argument: treeish.oid is required"},
		{"invalid object id", NewTreeishWithObjectID(nil), "twirp error invalid_argument: treeish.oid is required"},
		{"missing reference", &Treeish{Treeish: &Treeish_Reference{}}, "twirp error invalid_argument: treeish.reference is required"},
		{"invalid reference", NewTreeishWithReference(nil), "twirp error invalid_argument: treeish.reference is required"},
		{"missing revision", &Treeish{Treeish: &Treeish_Revision{}}, "twirp error invalid_argument: treeish.revision is required"},
		{"invalid revision", NewTreeishWithRevision(nil), "twirp error invalid_argument: treeish.revision is required"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.treeish.Validate(), tt.err)
		})
	}
}

func TestTreeishValidate(t *testing.T) {
	var tt *Treeish
	require.NoError(t, tt.Validate())

	id := NewObjectID(oid)
	tt = NewTreeishWithObjectID(id)
	require.NoError(t, tt.Validate())

	ref := NewReference([]byte("refs/heads/main"))
	tt = NewTreeishWithReference(ref)
	require.NoError(t, tt.Validate())

	rev := NewRevision([]byte("main"))
	tt = NewTreeishWithRevision(rev)
	require.NoError(t, tt.Validate())
}
