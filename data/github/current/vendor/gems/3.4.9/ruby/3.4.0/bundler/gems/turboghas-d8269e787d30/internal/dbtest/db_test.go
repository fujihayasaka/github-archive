package dbtest_test

import (
	"testing"

	"github.com/github/turboghas/internal/dbtest"
	"github.com/stretchr/testify/require"
)

func TestConnection(t *testing.T) {
	db := dbtest.RequireConnection(t)
	_, err := db.Exec("SELECT 1")
	require.NoError(t, err)
}
