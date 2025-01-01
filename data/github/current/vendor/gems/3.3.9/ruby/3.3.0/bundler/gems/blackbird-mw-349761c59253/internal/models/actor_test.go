package models

import (
	"context"
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

func Test_Equal(t *testing.T) {
	ctx := context.Background()
	a := NewAnonymousActor()
	b := NewAnonymousActor()
	require.True(t, a.Equal(ctx, b))
	b.ID = 1
	require.False(t, a.Equal(ctx, b))
	a.ID = 1
	require.True(t, a.Equal(ctx, b))
	a.AccessibleOrganizationIDs = map[uint32]bool{1: true, 2: true, 3: true}
	b.AccessibleOrganizationIDs = map[uint32]bool{1: true, 2: true, 3: true}
	require.True(t, a.Equal(ctx, b))
}
