package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewObjectTypeFromTypeString(t *testing.T) {
	req := NewObjectTypeFromTypeString("commit")
	require.Equal(t, req, &ObjectType{Type: Object_TYPE_COMMIT})
	require.NoError(t, req.Validate())

	req = NewObjectTypeFromTypeString("tag")
	require.Equal(t, req, &ObjectType{Type: Object_TYPE_TAG})
	require.NoError(t, req.Validate())

	req = NewObjectTypeFromTypeString("tree")
	require.Equal(t, req, &ObjectType{Type: Object_TYPE_TREE})
	require.NoError(t, req.Validate())

	req = NewObjectTypeFromTypeString("blob")
	require.Equal(t, req, &ObjectType{Type: Object_TYPE_BLOB})
	require.NoError(t, req.Validate())
}

func TestObjectTypeValidateErrors(t *testing.T) {
	objectType := &ObjectType{Type: 123}
	require.EqualError(t, objectType.Validate(), "twirp error invalid_argument: type must be commit, tree, blob or tag")

	objectType = NewObjectTypeFromTypeString("invalid")
	require.EqualError(t, objectType.Validate(), "twirp error invalid_argument: type must be commit, tree, blob or tag")
}
