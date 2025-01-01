package testing

import (
	"os"
	"testing"

	"github.com/github/authnd/internal/common/config"
	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/github-telemetry-go/log"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"
)

func IsProximaMode() bool {
	return os.Getenv("PROXIMA_MODE") == "1"
}

func OpenTestDBs(t *testing.T) (*sqlx.DB, *sqlx.DB, *sqlx.DB, *sqlx.DB) {
	t.Helper()

	var authndDBName = "github_test_authnd"
	var dotcomDBName = "github_test"
	var collabDBName = "github_test_collab"
	var lodgeDBName = "github_test_lodge"

	if IsProximaMode() {
		t.Log("Running in proxima test mode")
		authndDBName = "github_test_proxima_authnd"
		dotcomDBName = "github_test_proxima"
		collabDBName = "github_test_proxima_collab"
		lodgeDBName = "github_test_proxima_lodge"
	} else {
		t.Log("Running in dotcom test mode")
	}

	authndDB := openDB(t, authndDBName)
	dotcomDB := openDB(t, dotcomDBName)
	collabDB := openDB(t, collabDBName)
	lodgeDB := openDB(t, lodgeDBName)

	t.Cleanup(func() {
		authndDB.Close()
		dotcomDB.Close()
		collabDB.Close()
		lodgeDB.Close()
	})

	return authndDB, dotcomDB, collabDB, lodgeDB
}

type testDatabaseGetter struct {
	t   *testing.T
	dbs map[string]*sqlx.DB
}

func (p *testDatabaseGetter) GetDB(schema string) (*sqlx.DB, error) {
	p.t.Helper()

	db, ok := p.dbs[schema]
	require.True(p.t, ok, "no db found for '%s' schema", schema)
	return db, nil
}

func NewTestDatabaseGetter(t *testing.T) store.DatabaseGetter {
	t.Helper()

	authndDB, mysql1DB, collabDB, lodgeDB := OpenTestDBs(t)
	return &testDatabaseGetter{t: t, dbs: map[string]*sqlx.DB{
		schemas.AuthndRO: authndDB,
		schemas.AuthndRW: authndDB,
		schemas.Mysql1RO: mysql1DB,
		schemas.CollabRO: collabDB,
		schemas.CollabRW: collabDB,
		schemas.LodgeRO:  lodgeDB,
		schemas.LodgeRW:  lodgeDB,
	}}
}

func openDB(t *testing.T, name string) *sqlx.DB {
	t.Helper()

	dbConfig := config.TestDBConfig(name)
	logger, err := log.NewFromConfig(log.Config{
		LogLevel:           "debug",
		LogConsoleEncoding: "console",
	})
	require.NoError(t, err)

	database, err := db.Open(logger, dbConfig)
	require.NoError(t, err)

	var dummy int
	err = database.QueryRow("SELECT 1").Scan(&dummy)
	if err != nil && err.Error() == "dial tcp [::1]:3001: connect: connection refused" {
		require.Failf(t, "%s DB is not running, run 'script/setup'", name)
	}
	require.NoError(t, err)

	return database
}
