package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewCommitishWithObjectID(t *testing.T) {
	id := NewObjectID(oid)
	tt := NewCommitishWithObjectID(id)
	require.Equal(t, &Commitish{Commitish: &Commitish_Oid{Oid: id}}, tt)
}

func TestNewCommitishWithReference(t *testing.T) {
	ref := NewReference([]byte("refs/heads/main"))
	tt := NewCommitishWithReference(ref)
	require.Equal(t, &Commitish{Commitish: &Commitish_Reference{Reference: ref}}, tt)
}

func TestNewCommitishWithRevision(t *testing.T) {
	rev := NewRevision([]byte("main"))
	tt := NewCommitishWithRevision(rev)
	require.Equal(t, &Commitish{Commitish: &Commitish_Revision{Revision: rev}}, tt)
}

func TestCommitishValidateErrors(t *testing.T) {
	var tests = []struct {
		name      string
		Commitish *Commitish
		err       string
	}{
		{"empty", &Commitish{}, "twirp error invalid_argument: commitish is required"},
		{"missing object id", &Commitish{Commitish: &Commitish_Oid{}}, "twirp error invalid_argument: commitish.oid is required"},
		{"invalid object id", NewCommitishWithObjectID(nil), "twirp error invalid_argument: commitish.oid is required"},
		{"missing reference", &Commitish{Commitish: &Commitish_Reference{}}, "twirp error invalid_argument: commitish.reference is required"},
		{"invalid reference", NewCommitishWithReference(nil), "twirp error invalid_argument: commitish.reference is required"},
		{"missing revision", &Commitish{Commitish: &Commitish_Revision{}}, "twirp error invalid_argument: commitish.revision is required"},
		{"invalid revision", NewCommitishWithRevision(nil), "twirp error invalid_argument: commitish.revision is required"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.Commitish.Validate(), tt.err)
		})
	}
}

func TestCommitishValidate(t *testing.T) {
	var tt *Commitish
	require.NoError(t, tt.Validate())

	id := NewObjectID(oid)
	tt = NewCommitishWithObjectID(id)
	require.NoError(t, tt.Validate())

	ref := NewReference([]byte("refs/heads/main"))
	tt = NewCommitishWithReference(ref)
	require.NoError(t, tt.Validate())

	rev := NewRevision([]byte("main"))
	tt = NewCommitishWithRevision(rev)
	require.NoError(t, tt.Validate())
}
