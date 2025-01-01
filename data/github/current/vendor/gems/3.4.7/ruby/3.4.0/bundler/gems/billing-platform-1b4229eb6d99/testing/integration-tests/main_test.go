//go:build integration
// +build integration

package integrationtests_test

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"os"
	"os/signal"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/testing/integration"
	"github.com/google/uuid"
)

var databaseName string

func TestMain(m *testing.M) {
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	go func() {
		<-c
		log.Println("Interrupt signal received. Exiting...")
	}()

	schemaManager := setup()

	exitCode := integration.PrepareTesting(m)

	log.Println("Exit code", exitCode)

	if integration.PreservedData == true {
		log.Println("Skipping teardown because at least one test preserved data")
	} else {
		tearDown(schemaManager)
	}

	os.Exit(exitCode)
}

func setup() *db.SchemaManagement {
	log.Println("Setting Up Integration Tests")

	cfg, err := config.LoadWithOptions(false)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	userName := os.Getenv("GITHUB_USER")
	databaseName = fmt.Sprintf("%s-%s", userName, uuid.NewString())
	integration.DefaultClientOptions.DatabaseName = databaseName

	conn, _, err := db.NewDBConnections(cfg)
	if err != nil {
		log.Fatalf("Failed to create database connection: %v", err)
	}

	schemaManager := db.NewSchemaManagement(cfg, conn)
	if err := createDatabase(schemaManager, databaseName); err != nil {
		log.Fatalf("Failed to create database: %v", err)
	}
	log.Printf("Using Test Database:%v ", databaseName)

	// changed if we ever preserved collections during testing
	integration.PreservedData = false
	return schemaManager
}

func tearDown(schemaManager *db.SchemaManagement) {
	log.Println("Tearing Down Integration Tests")

	err := removeDatabase(schemaManager, databaseName)
	if err != nil {
		log.Fatalf("Failed to remove database: %v", err)
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
