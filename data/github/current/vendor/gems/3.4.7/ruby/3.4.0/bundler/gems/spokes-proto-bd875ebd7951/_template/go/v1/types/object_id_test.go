package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

const (
	oid       = "da0b8bc63b985d79ecebc1ec7dddcd0d048892ab"
	oidSHA256 = "473a0f4c3be8a93681a267e3b1e9a7dcda1185436fe141f7749120a303721813"
)

func TestNewObjectID(t *testing.T) {
	id := NewObjectID(oid)
	require.Equal(t, &ObjectID{Id: oid}, id)

	id = NewObjectID(oidSHA256)
	require.Equal(t, &ObjectID{Id: oidSHA256}, id)
}

func TestObjectIDValidate(t *testing.T) {
	var nilID *ObjectID
	require.NoError(t, nilID.Validate())

	missingID := NewObjectID("")
	require.EqualError(t, missingID.Validate(), "twirp error invalid_argument: object_id.id is required")

	invalidID := NewObjectID("Hello world")
	require.EqualError(t, invalidID.Validate(), "twirp error invalid_argument: object_id.id must be a valid object id")

	validID := NewObjectID(oid)
	require.NoError(t, validID.Validate())

	validID = NewObjectID(oidSHA256)
	require.NoError(t, validID.Validate())

	validID = NewObjectID(nullOID)
	require.NoError(t, validID.Validate())

	validID = NewObjectID(nullOIDSHA256)
	require.NoError(t, validID.Validate())
}

func TestObjectIDIsNull(t *testing.T) {
	var nilID *ObjectID
	require.True(t, nilID.IsNull())
	require.True(t, NewObjectID(nullOID).IsNull())
	require.True(t, NewObjectID(nullOIDSHA256).IsNull())
	require.False(t, NewObjectID(oid).IsNull())
	require.False(t, NewObjectID(oidSHA256).IsNull())
}
