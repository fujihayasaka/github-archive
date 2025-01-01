//go:build db

package mysqlcollationtest

import (
	"testing"

	commonTesting "github.com/github/authnd/internal/common/testing"
	"github.com/stretchr/testify/require"
)

func TestConnectionCollationIsSet(t *testing.T) {
	authndDB, _, _, _ := commonTesting.OpenTestDBs(t)
	t.Cleanup(func() {
		authndDB.Close()
	})

	var collation string
	err := authndDB.QueryRow("SELECT @@COLLATION_CONNECTION").Scan(&collation)
	require.NoError(t, err)
	require.Equal(t, "utf8mb4_unicode_520_ci", collation)
}
