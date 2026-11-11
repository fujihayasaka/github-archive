package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestQuarantineCommitsSelector(t *testing.T) {
	us := NewQuarantineCommitsSelector()
	require.Equal(t, &QuarantineCommitsSelector{}, us)
}

func TestQuarantineCommitsValidate(t *testing.T) {
	var nilSelector *QuarantineCommitsSelector
	require.NoError(t, nilSelector.Validate())

	valid := NewQuarantineCommitsSelector()
	require.NoError(t, valid.Validate())
}
