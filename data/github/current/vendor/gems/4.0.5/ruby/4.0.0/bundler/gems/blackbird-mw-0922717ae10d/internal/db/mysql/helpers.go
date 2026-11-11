package mysql

import (
	"fmt"
	"os"
	"testing"

	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/schemas"
)

// Helper function that returns a database connection to test database.
func testDB(t *testing.T) *sqlx.DB {
	t.Helper()
	if os.Getenv("RUN_DB_TESTS") == "" && os.Getenv("RUN_INT_TESTS") == "" {
		t.Skipf("RUN_DB_TESTS or RUN_INT_TESTS is not set, skipping %s", t.Name())
	}

	db := schemas.DB("localhost-test", "")

	resetDB(t, db)
	t.Cleanup(func() { resetDB(t, db) })

	return db
}

func resetDB(t *testing.T, db *sqlx.DB) {
	tables := dirtyTables(t, db)

	for _, table := range tables {
		// NOTE: Can't use bindvars on table names
		stmt := fmt.Sprintf("TRUNCATE TABLE `%s`", table)
		_, err := db.Exec(stmt)
		require.NoError(t, err)
	}

	require.Empty(t, dirtyTables(t, db), "failed to truncate tables")
}

func dirtyTables(t *testing.T, db *sqlx.DB) []string {
	query := `
SELECT table_name
  FROM information_schema.tables
 WHERE table_rows >= 1 AND table_schema = 'blackbird_test'
`

	var tables []string
	err := db.Select(&tables, query)
	require.NoError(t, err)
	return tables
}
