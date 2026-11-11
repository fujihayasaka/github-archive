package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewRootSelector(t *testing.T) {
	rs := NewRootSelector()
	require.Equal(t, &RootSelector{}, rs)
}

func TestRootSelectorValidate(t *testing.T) {
	var nilSelector *RootSelector
	require.NoError(t, nilSelector.Validate())

	valid := NewRootSelector()
	require.NoError(t, valid.Validate())
}
