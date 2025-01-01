package upgrades_test

import (
	"context"
	"database/sql"
	"testing"

	"github.com/github/turboscan/ts/mysql/upgrades"
	"github.com/stretchr/testify/require"
)

func TestFunctionTransition(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175824).Step(0).Simple(
		"INSERT IGNORE INTO mytable (id) VALUES(1),(2),(3)",
		"INSERT IGNORE INTO mytable (id) VALUES(4),(5),(6)",
		"UPDATE mytable SET id = id + 10 WHERE id < 10 LIMIT 4",
	)
	v.Version(20200618175826).Function("mytable", func(ctx context.Context, db upgrades.DB, start, end uint64) error {
		_, err := db.ExecContext(ctx, "UPDATE mytable SET stringcol = CAST(id AS CHAR) WHERE id BETWEEN ? AND ?", start, end)
		return err
	})

	output, err := runMigrationsAndDiffSchema(t, "testdata/migrations-good", v.Build, func(t *testing.T, db *sql.DB) {
		t.Helper()
		ss := readStrings(t, db, "SELECT stringcol from mytable")
		require.Equal(t, []string{"11", "12", "13", "14", "15", "16"}, ss)
	})
	require.NoError(t, err, output)
}
