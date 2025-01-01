package transitionsapp

import (
	"context"
	"testing"

	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	_ "github.com/go-sql-driver/mysql" // mysql driver
	"github.com/jmoiron/sqlx"
)

func TestAppRun(t *testing.T) {
	// create a new database connection
	db, err := sqlx.Connect("mysql", mysql.TestDBURI)
	if err != nil {
		t.Fatal("failed to connect to database", err)
	}
	defer cleanUp(t, db)

	// create a new transition app config
	transitionAppConfig := Config{
		AppEnv:         "test",
		MySQLDBConn:    mysql.TestDBURI,
		UseLocalClient: true,

		// transition arguments
		DryRun:    false,
		ID:        202404021710,
		BatchSize: 2,
		MinID:     1024,
		MaxID:     1029,
	}

	// create a new transition app
	transitionApp, err := New(transitionAppConfig)
	if err != nil {
		t.Fatal("failed to create transition app", err)
	}

	// run the transition app
	err = transitionApp.Run(context.Background())
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}
}

// cleanUp truncates the attestations table and shuts down the server and database connections
func cleanUp(t *testing.T, db *sqlx.DB) {
	// clean up the attestation table
	_, err := db.Exec("TRUNCATE attestations")
	if err != nil {
		t.Fatal("failed to truncate attestations table", err)
	}

	// clean up the attestations_subjects table
	_, err = db.Exec("TRUNCATE attestations_subjects")
	if err != nil {
		t.Fatal("failed to truncate attestations_subjects table", err)
	}

	// shut everything down
	db.Close()
}
