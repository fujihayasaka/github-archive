package selectors

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestQuarantineObjectsSelector(t *testing.T) {
	us := NewQuarantineObjectsSelector()
	require.Equal(t, &QuarantineObjectsSelector{}, us)
}

func TestQuarantineObjectsValidate(t *testing.T) {
	var nilSelector *QuarantineObjectsSelector
	require.NoError(t, nilSelector.Validate())

	valid := NewQuarantineObjectsSelector()
	require.NoError(t, valid.Validate())
}
