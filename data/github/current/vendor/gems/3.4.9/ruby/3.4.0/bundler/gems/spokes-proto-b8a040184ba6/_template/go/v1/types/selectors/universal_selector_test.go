package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewUniversalSelector(t *testing.T) {
	us := NewUniversalSelector()
	require.Equal(t, &UniversalSelector{}, us)
}

func TestUniversalSelectorValidate(t *testing.T) {
	var nilSelector *UniversalSelector
	require.NoError(t, nilSelector.Validate())

	valid := NewUniversalSelector()
	require.NoError(t, valid.Validate())
}
