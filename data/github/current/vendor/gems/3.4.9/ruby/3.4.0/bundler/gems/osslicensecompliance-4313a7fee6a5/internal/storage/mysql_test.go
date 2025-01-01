package storage_test

import (
	"database/sql"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/nullblob"
	"github.com/github/osslicensecompliance/internal/storage/testmysql"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newMysqlStorage(t *testing.T, _ string, _ stats.Client) (*storage.Storage, error) {
	t.Helper()
	testDB, err := testmysql.NewTestDB()
	require.NoError(t, err)
	t.Cleanup(func() { testDB.Close() })

	db, err := sql.Open("mysql", fmt.Sprintf("%s?parseTime=true", testDB.ConnectionString))
	if err != nil {
		return nil, err
	}
	t.Cleanup(func() {
		err = db.Close()
		if err != nil {
			t.Errorf("failed to close database connection: %v", err)
		}
	})

	// See docs for more information: https://github.com/github/go/blob/main/docs/database_access.md
	db.SetConnMaxIdleTime(25 * time.Second)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetMaxIdleConns(32)
	db.SetMaxOpenConns(64)

	return storage.NewStorage(db, nullblob.NewBucket(), nullblob.NewBucket(), nullblob.NewBucket(), nil)
}

// This test is slow as creates a mysql instance and runs migrations
// Therefore, it is only run in CI
func TestMysqlSetup_RunsMigrations(t *testing.T) {
	if os.Getenv("CI") != "true" {
		t.Skip("Only run in CI")
	}
	_, err := newMysqlStorage(t, "", nil)
	assert.NoError(t, err)
}
