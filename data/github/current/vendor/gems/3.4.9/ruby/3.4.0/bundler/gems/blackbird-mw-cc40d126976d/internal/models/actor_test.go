package models

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_MarshalUnMarshal(t *testing.T) {
	a := NewAnonymousActor()
	a.ID = 1

	data, err := a.Marshal()
	require.NoError(t, err)

	var b Actor
	err = b.Unmarshal(data)
	require.NoError(t, err)
	require.Equal(t, a.ID, b.ID)
}
