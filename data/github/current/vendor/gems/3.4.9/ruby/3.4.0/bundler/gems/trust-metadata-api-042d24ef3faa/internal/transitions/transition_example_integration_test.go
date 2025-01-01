package transitions

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	_ "github.com/go-sql-driver/mysql" // mysql driver
	"github.com/jmoiron/sqlx"
)

func TestTransitionExampleRun(t *testing.T) {
	// create a new database connection
	db, err := sqlx.Connect("mysql", mysql.TestDBURI)
	if err != nil {
		t.Fatal("failed to connect to database", err)
	}
	defer cleanUpSQLX(t, db)

	// create a new transition example
	transitionExample := NewTransitionExample(db, &Args{
		ID:        202404021710,
		DryRun:    false,
		BatchSize: 2,
		MinID:     1024,
		MaxID:     1029,
	}, log.NewNullLogger())

	// run the transition
	err = transitionExample.Run(context.Background())
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}
}
