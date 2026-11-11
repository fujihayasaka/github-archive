// Package testmysql provides a Testcontainers instance of mysql
// To be used in tests where we would like a real database
package testmysql

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	_ "github.com/go-sql-driver/mysql"
	"github.com/testcontainers/testcontainers-go/modules/mysql"
)

const (
	dbName = "test_db"
	dbUser = "test_user"
	dbPass = "test_password"
)

// TestDB represents the test container database
type TestDB struct {
	container        *mysql.MySQLContainer
	ConnectionString string
}

// getSQLFiles reads a directory and returns a slice of strings
// containing the names of all files with a .sql extension.
func getSQLFiles(dirPath string) ([]string, error) {
	var sqlFiles []string

	// Read all entries in the directory
	entries, err := os.ReadDir(dirPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read directory: %w", err)
	}

	// Iterate over directory entries
	for _, entry := range entries {
		// Check if it's a regular file and ends with .sql
		if !entry.IsDir() && filepath.Ext(entry.Name()) == ".sql" {
			sqlFiles = append(sqlFiles, filepath.Join(dirPath, entry.Name()))
		}
	}

	return sqlFiles, nil
}

// NewTestDB creates a new instance of the test database
func NewTestDB(schemaDirPath string) (*TestDB, error) {
	ctx := context.Background()
	sqlfiles, err := getSQLFiles(schemaDirPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get sql files: %w", err)
	}
	container, err := mysql.Run(
		ctx,
		"mysql:8.0.36",
		mysql.WithDatabase(dbName),
		mysql.WithUsername(dbUser),
		mysql.WithPassword(dbPass),
		mysql.WithScripts(sqlfiles...),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to start test container %w", err)
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
