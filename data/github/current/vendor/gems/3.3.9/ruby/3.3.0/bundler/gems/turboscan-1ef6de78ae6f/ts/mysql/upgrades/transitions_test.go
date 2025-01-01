package upgrades

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestStep(t *testing.T) {
	tr := Transitions()

	require.Equal(t, uint64(10), tr.Step(10).(*transitions).step)
	require.Equal(t, uint64(10000), tr.(*transitions).step)
}

func TestVersion(t *testing.T) {
	tr := Transitions()

	require.Equal(t, uint(10), tr.Version(10).(*transitions).versionFunc())
	require.Panics(t, func() {
		// this should use the default version function which will panic when the filename
		// does not match the transition pattern
		tr.(*transitions).versionFunc()
	})
}
