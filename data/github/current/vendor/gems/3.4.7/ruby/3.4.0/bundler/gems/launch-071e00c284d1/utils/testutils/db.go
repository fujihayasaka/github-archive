package testutils

import (
	"database/sql"
	"fmt"
)

func StartTests(db *sql.DB, name string) error {
	// take an advisory lock to avoid parallel execution between test
	// binaries that use the same DB resource
	_, err := db.Exec(`select GET_LOCK(?, 15)`, name)
	return err
}

func EndTests(db *sql.DB, name string) error {
	_, err := db.Exec(`select RELEASE_LOCK(?)`, name)
	return err
}

func TruncateTable(db *sql.DB, table string) error {
	_, err := db.Exec(fmt.Sprintf("TRUNCATE `%s`", table))
	return err
}
