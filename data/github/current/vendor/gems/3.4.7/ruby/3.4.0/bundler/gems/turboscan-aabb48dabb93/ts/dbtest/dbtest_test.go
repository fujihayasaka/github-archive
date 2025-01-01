package dbtest

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestDeleteDB(t *testing.T) {
	db := RequireConnectionWithoutTransaction(t)

	require.NoError(t, db.Exec(`SELECT 1`).Error)
}
