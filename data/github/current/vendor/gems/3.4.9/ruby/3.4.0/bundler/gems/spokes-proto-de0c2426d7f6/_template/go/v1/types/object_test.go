package types

import (
	"math/rand"
	"testing"

	"github.com/stretchr/testify/require"
)

var (
	objectID = NewObjectID("bf93d0d133de075e0e623f4b96c4c028b86dcdf7")
	size     = rand.Uint64()
)

func TestNewCommitObject(t *testing.T) {
	o := NewCommitObject(objectID, size, 0)
	require.Equal(t, &Object{Type: Object_TYPE_COMMIT, Oid: objectID, Size: size}, o)
}

func TestNewTreeObject(t *testing.T) {
	o := NewTreeObject(objectID, size, 0)
	require.Equal(t, &Object{Type: Object_TYPE_TREE, Oid: objectID, Size: size}, o)
}

func TestNewBlobObject(t *testing.T) {
	o := NewBlobObject(objectID, size, 0)
	require.Equal(t, &Object{Type: Object_TYPE_BLOB, Oid: objectID, Size: size}, o)
}

func TestNewTagObject(t *testing.T) {
	o := NewTagObject(objectID, size)
	require.Equal(t, &Object{Type: Object_TYPE_TAG, Oid: objectID, Size: size}, o)
}

func TestObjectValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		o    *Object
		err  string
	}{
		{"empty", &Object{}, "twirp error invalid_argument: type must be set"},
		{"invalid type", &Object{Type: Object_TYPE_INVALID, Oid: objectID}, "twirp error invalid_argument: type must be set"},
		{"bogus type", &Object{Type: 123, Oid: objectID}, "twirp error invalid_argument: type must be commit, tree, blob or tag"},
		{"missing oid", &Object{Type: Object_TYPE_COMMIT}, "twirp error invalid_argument: oid is required"},
		{"invalid oid", &Object{Type: Object_TYPE_COMMIT, Oid: &ObjectID{}}, "twirp error invalid_argument: object_id.id is required"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.EqualError(t, tt.o.Validate(), tt.err)
		})
	}
}

func TestObjectValidate(t *testing.T) {
	var o *Object
	require.NoError(t, o.Validate())
}

func TestObjectIsCommit(t *testing.T) {
	o := NewTreeObject(objectID, size, 0)
	require.False(t, o.IsCommit())

	o = NewCommitObject(objectID, size, 0)
	require.True(t, o.IsCommit())
}

func TestObjectIsTree(t *testing.T) {
	o := NewCommitObject(objectID, size, 0)
	require.False(t, o.IsTree())

	o = NewTreeObject(objectID, size, 0)
	require.True(t, o.IsTree())
}

func TestObjectIsBlob(t *testing.T) {
	o := NewTagObject(objectID, size)
	require.False(t, o.IsBlob())

	o = NewBlobObject(objectID, size, 0)
	require.True(t, o.IsBlob())
}

func TestObjectIsTag(t *testing.T) {
	o := NewBlobObject(objectID, size, 0)
	require.False(t, o.IsTag())

	o = NewTagObject(objectID, size)
	require.True(t, o.IsTag())
}
