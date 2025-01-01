package helpers

import (
	"context"
	"fmt"
	"math/rand"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/testing/integration"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
)

// To use this for unit testing:
// Define a database name constant within the test file
//
// func YourUnitTestName(t *testing.T) {
// 	schemaManager := Setup(t, databaseName)
// 	defer TearDown(t, databaseName, schemaManager) // this will run after the test function completes
// 	db, logger := NewUnitTestDB(t, databaseName, schemaManager)
// 	... do test stuff
// }

func NewUnitTestDB(t *testing.T, databaseName string, schemaManager *db.SchemaManagement) (interfaces.Database, log.Logger) {
	cfg, err := config.LoadWithOptions(false)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	cfg.DatabaseName = databaseName

	telem, err := telemetry.NewFromEnv()
	if err != nil {
		t.Fatalf("Failed configuring telemetry: %v", err)
	}

	statter := cfg.StatsClient()
	logger := log.NewNullLogger()
	tracer := telem.Tracer.Tracer
	DB := db.NewDatabase(cfg, logger, statter, tracer)

	return DB, logger
}

func Setup(t *testing.T, databaseName string) *db.SchemaManagement {
	t.Log("Setting Up Integration Tests")

	cfg, err := config.LoadWithOptions(false)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	integration.DefaultClientOptions.DatabaseName = databaseName

	conn, _, err := db.NewDBConnections(cfg)
	if err != nil {
		t.Fatalf("Failed to create database connection: %v", err)
	}

	schemaManager := db.NewSchemaManagement(cfg, conn)
	if err := createDatabase(schemaManager, databaseName); err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	t.Logf("Using Test Database:%v ", databaseName)

	// changed if we ever preserved collections during testing
	return schemaManager
}

func TearDown(t *testing.T, databaseName string, schemaManager *db.SchemaManagement) {
	t.Log("Tearing Down Integration Tests")

	err := removeDatabase(schemaManager, databaseName)
	if err != nil {
		t.Fatalf("Failed to remove database: %v", err)
	}
}

func createDatabase(schemaManager *db.SchemaManagement, databaseName string) error {
	for i := 0; i < 10; i++ {
		if err := schemaManager.EnsureDatabaseExists(context.Background(), databaseName); err != nil {
			if db.Is429ToManyRequests(err) {
				n := rand.Intn(100)
				time.Sleep(time.Duration(n) * time.Millisecond)
				continue
			}
			return err
		} else {
			return nil
		}
	}

	return fmt.Errorf("exhausted 429 retries")
}

func removeDatabase(schemaManager *db.SchemaManagement, databaseName string) error {
	for i := 0; i < 10; i++ {
		if err := schemaManager.RemoveDatabase(context.Background(), databaseName); err != nil {
			if db.Is429ToManyRequests(err) {
				n := rand.Intn(100)
				time.Sleep(time.Duration(n) * time.Millisecond)
				continue
			}
			return err
		} else {
			return nil
		}
	}

	return fmt.Errorf("exhausted 429 retries")
}
