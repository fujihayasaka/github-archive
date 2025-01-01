// Package sqlite provides a  sqlite database setup with migrations run
// Used for tests and for local development
package sqlite

import (
	"database/sql"

	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "modernc.org/sqlite"
)

// New creates a sqlite database with migrations ran
func New(persistLocation string) (*sql.DB, error) {
	ploc := ":memory:"
	if persistLocation != "" {
		ploc = persistLocation
	}
	db, err := sql.Open("sqlite", ploc)
	if err != nil {
		return nil, err
	}

	db.SetMaxOpenConns(1)

	return db, nil
}
