// Package fixtures provides test setup utilities for database testing.
package fixtures

import (
	"os"
	"testing"

	"github.com/github/go-dbkit"
	"github.com/github/go-dbkit/dbtest"
	"github.com/pkg/errors"
)

type config struct {
	SQLEnvConfig *dbkit.EnvConfig
}

func newConfigFromEnvironment() (*config, error) {
	sqlEnvConfig, err := dbkit.NewConfigFromEnvironment()
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &config{SQLEnvConfig: sqlEnvConfig}, nil
}

// SetupDB initializes and returns a test database configuration.
func SetupDB(t *testing.T, clusterName string) *dbtest.TestDBConfig {
	// Connect to known database to create a new, random one
	cfg, _ := newConfigFromEnvironment()
	dbConfig, err := cfg.SQLEnvConfig.DBConfigFor(clusterName)
	if err != nil {
		t.Fatalf("Failed to get database config: %v", err)
	}

	dbConfig.MysqlConfig.Params = map[string]string{
		"transaction_isolation": "\"READ-UNCOMMITTED\"",
	}

	filePath := os.Getenv("REPO_ROOT") + "/db/" + clusterName + "-structure.sql"

	schema, err := dbtest.LoadScriptFromFile(filePath)
	if err != nil {
		t.Fatalf("Failed to load schema: %v", err)
	}

	db := dbtest.NewTestDBConfig(dbConfig)
	db.DBPrefix = "configsd_test_"
	db.SetupScripts = append(db.SetupScripts, schema)
	return db
}
