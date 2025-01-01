package transitions

import (
	"testing"

	"github.com/jmoiron/sqlx"
)

// cleanUp truncates the attestations table and shuts down the server and database connections
func cleanUpSQLX(t *testing.T, db *sqlx.DB) {
	// clean up the attestation table
	_, err := db.Exec("TRUNCATE attestations")
	if err != nil {
		t.Fatal("failed to truncate attestations table", err)
	}

	// clean up the attestations_subject table
	_, err = db.Exec("TRUNCATE attestations_subjects")
	if err != nil {
		t.Fatal("failed to truncate attestations_subjects table", err)
	}

	// shut everything down
	db.Close()
}
