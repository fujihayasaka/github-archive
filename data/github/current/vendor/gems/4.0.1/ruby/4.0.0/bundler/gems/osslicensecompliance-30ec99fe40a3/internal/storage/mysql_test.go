package storage_test

import (
	"database/sql"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/sequence"
	"github.com/github/osslicensecompliance/internal/storage/testmysql"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newMysqlStorage(t *testing.T, _ string, _ stats.Client) (*storage.Storage, *sql.DB, error) {
	t.Helper()
	testDB, err := testmysql.NewTestDB("../../schemas")
	require.NoError(t, err)
	t.Cleanup(func() { testDB.Close() })

	db, err := sql.Open("mysql", fmt.Sprintf("%s?parseTime=true", testDB.ConnectionString))
	if err != nil {
		return nil, nil, err
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

	s, err := storage.NewStorage(db, storage.NewNullBucket(), storage.NewNullBucket(), storage.NewNullBucket(), sequence.NewMySQLGenerator(db), nil, log.NewNullLogger())
	if err != nil {
		return nil, nil, err
	}
	return s, db, nil
}

// This test is slow as creates a mysql instance and runs migrations
// Therefore, it is only run in CI
func TestMysqlSetup_RunsMigrations(t *testing.T) {
	if os.Getenv("CI") != "true" {
		t.Skip("Only run in CI")
	}
	_, _, err := newMysqlStorage(t, "", nil)
	assert.NoError(t, err)
}

func TestMySqlCanCreateCheckJob(t *testing.T) {
	if os.Getenv("CI") != "true" {
		t.Skip("Only run in CI")
	}
	mySQLStorage, db, err := newMysqlStorage(t, "", nil)
	require.NoError(t, err)
	require.NotNil(t, db)

	ctx := t.Context()
	businessID := uint64(3)
	job := models.CheckJob{
		RepositoryID:      10,
		PullRequestNumber: 1,
		BaseSHA:           "abc123",
		CommitSHA:         "def456",
		OrganizationID:    2,
		EnterpriseID:      &businessID,
	}
	returnedJob, err := mySQLStorage.CreateCheckJob(ctx, job)
	require.NoError(t, err)
	require.NotZero(t, returnedJob.ID)

	rj2, err := mySQLStorage.CreateCheckJob(ctx, job)
	require.Nil(t, rj2)
	require.ErrorIs(t, err, storage.ErrCheckAlreadyExists)
}
