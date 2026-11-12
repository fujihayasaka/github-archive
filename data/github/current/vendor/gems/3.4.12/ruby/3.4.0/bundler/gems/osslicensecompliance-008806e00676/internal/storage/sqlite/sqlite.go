// Package sqlite provides a  sqlite database setup with migrations run
// Used for tests and for local development
package sqlite

import (
	"database/sql"

	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "modernc.org/sqlite"
)

func getSqliteSchemaDDL() []string {
	return []string{
		"BEGIN;",
		`CREATE TABLE IF NOT EXISTS olc_check_jobs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			status TEXT NOT NULL,
			created_at DATETIME NOT NULL,
			check_started_at DATETIME NOT NULL,
			repository_id INTEGER NOT NULL,
			organization_id INTEGER NOT NULL,
			pull_request_id INTEGER NOT NULL,
			pull_request_number INTEGER NOT NULL,
			enterprise_id INTEGER,
			base_sha TEXT NOT NULL,
			commit_sha TEXT NOT NULL,
			expected_snapshots INTEGER NOT NULL,
			received_snapshots INTEGER NOT NULL
		);`,
		"CREATE UNIQUE INDEX IF NOT EXISTS index_olc_pr on olc_check_jobs (repository_id, pull_request_number);",
		`CREATE TABLE IF NOT EXISTS olc_alerts (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			number INTEGER NOT NULL,
			status TEXT NOT NULL,
			resolution TEXT DEFAULT NULL,
			created_at DATETIME NOT NULL,
			repository_id INTEGER NOT NULL,
			organization_id INTEGER NOT NULL,
			enterprise_id INTEGER,
			manifest_name TEXT NOT NULL,
			manifest_line_number INTEGER NOT NULL,
			package_ecosystem INTEGER NOT NULL,
			package_name TEXT NOT NULL,
			package_version TEXT NOT NULL,
			spdx_license_expression TEXT NOT NULL,
			pull_request_number INTEGER
		);`,
		"CREATE UNIQUE INDEX IF NOT EXISTS index_olc_alert on olc_alerts (repository_id, number);",
		`CREATE TABLE IF NOT EXISTS olc_alert_events (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			alert_id INTEGER NOT NULL,
			event_type TEXT NOT NULL,
			user_id INTEGER,
			occurred_at DATETIME NOT NULL,
			event_body TEXT NOT NULL
		);`,
		"CREATE INDEX IF NOT EXISTS index_olc_event on olc_alert_events (alert_id, event_type);",
		"COMMIT;",
	}
}

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

	// Enable foreign key support
	if _, err := db.Exec("PRAGMA foreign_keys = ON;"); err != nil {
		return nil, err
	}

	// Run the schema to create tables
	queries := getSqliteSchemaDDL()
	for _, query := range queries {
		if _, err := db.Exec(query); err != nil {
			return nil, err
		}
	}

	return db, nil
}
