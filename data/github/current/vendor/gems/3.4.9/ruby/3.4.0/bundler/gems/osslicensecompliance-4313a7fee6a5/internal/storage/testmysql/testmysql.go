// Package testmysql provides a Testcontainers instance of mysql
// To be used in tests where we would like a real database
package testmysql

import (
	"context"
	"fmt"

	_ "github.com/go-sql-driver/mysql"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/testcontainers/testcontainers-go/modules/mysql"
)

const (
	dbName               = "test_db"
	dbUser               = "test_user"
	dbPass               = "test_password"
	pathToMigrationFiles = "file://../../db/migrations"
)

// TestDB represents the test container database
type TestDB struct {
	container        *mysql.MySQLContainer
	ConnectionString string
}

// NewTestDB creates a new instance of the test database
func NewTestDB() (*TestDB, error) {
	ctx := context.Background()
	container, err := mysql.Run(
		ctx,
		"mysql:8.0.36",
		mysql.WithDatabase(dbName),
		mysql.WithUsername(dbUser),
		mysql.WithPassword(dbPass),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to start test contaiiner %w", err)
	}

	connString, err := container.ConnectionString(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get db connection string %w", err)
	}

	t := &TestDB{
		container:        container,
		ConnectionString: connString,
	}

	return t, nil
}

// Close closes the test container
func (t *TestDB) Close() {
	if err := t.container.Terminate(context.Background()); err != nil {
		fmt.Printf("failed to terminate container %s", err)
	}
}
