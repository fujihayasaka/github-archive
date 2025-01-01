package upgrades_test

import (
	"testing"

	"github.com/github/turboscan/ts/mysql/upgrades"

	"github.com/stretchr/testify/require"
)

func TestVersion(t *testing.T) {
	var version uint
	var ok bool
	version, ok = upgrades.VersionFromFile("1_test.go")
	require.True(t, ok)
	require.Equal(t, uint(1), version)
	version, ok = upgrades.VersionFromFile("a_test.go")
	require.False(t, ok)
	require.Equal(t, uint(0), version)
	version, ok = upgrades.VersionFromFile("-1_test.go")
	require.False(t, ok)
	require.Equal(t, uint(0), version)
}
