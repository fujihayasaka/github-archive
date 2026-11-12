package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewParentSelector(t *testing.T) {
	ps := NewParentSelector()
	require.Equal(t, &ParentSelector{}, ps)
}

func TestParentSelectorValidate(t *testing.T) {
	var nilSelector *ParentSelector
	require.NoError(t, nilSelector.Validate())

	valid := NewParentSelector()
	require.NoError(t, valid.Validate())
}
