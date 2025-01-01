package upgrades_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts/mysql/upgrades"
)

func TestOrdering(t *testing.T) {
	require.NoError(t, upgrades.CheckOrdering(os.DirFS("testdata/migrations-good")))
}

func TestOrderingMissingDirectory(t *testing.T) {
	require.EqualError(t, upgrades.CheckOrdering(os.DirFS("testdata/missing")), "no migrations found at testdata/missing")
}

func TestBadOrdering(t *testing.T) {
	require.EqualError(t, upgrades.CheckOrdering(os.DirFS("testdata/migrations-bad-ordering")), "LATEST should have version 20200618175825 but has 20200618175826: please move your migration to the end of the migration chain and update LATEST")
}
