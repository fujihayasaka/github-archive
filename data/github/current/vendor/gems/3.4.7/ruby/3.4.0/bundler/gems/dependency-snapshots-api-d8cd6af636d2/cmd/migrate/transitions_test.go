package main

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/db"
	frenomock "github.com/github/dependency-snapshots-api/internal/freno/mock"
	"github.com/github/dependency-snapshots-api/internal/storage"
	blobmock "github.com/github/dependency-snapshots-api/internal/storage/blob/testutility"
	"github.com/github/dependency-snapshots-api/internal/testutil"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/require"
)

func TestConvertFromBlobURLTransition(t *testing.T) {
	cfg := testutil.CreateTestConfig(t)
	cfg.Enterprise = false

	testDB, err := testutil.NewNamedTestDB(t, testutil.CreateTestConfig(t), log.NewNullLogger(), stats.NullStatter, "transitions_test")
	require.NoError(t, err)

	sqlxDB, err := db.NewSqlxDatabase(testDB.DB.GetRawSQLDBPrimary())
	require.NoError(t, err)

	t.Cleanup(func() {
		sqlxDB.Close()
	})

	blob := blobmock.GetTestBlobStorage(t)
	freno := frenomock.NewMockFrenoClient()
	transitioner := getBlobMigrationTransition(cfg, sqlxDB, blob, freno)

	snapshotBlob := "{\"someKey\": \"someValue\"}"
	res, err := storage.ExecuteQuery(
		context.Background(),
		sqlxDB,
		"insert row to convert",
		"INSERT INTO ds_snapshot_blobs (`blob`, blob_size_bytes, created_at, blob_hash, repository_id) VALUES (?, ?, ?, ?, ?)",
		snapshotBlob, len(snapshotBlob), time.Now(), "caa3e3d15a140a8b3b1c875b0e7b9e78f353729a6fa2afb595418cf336d2ba9c", 123456,
	)
	require.NoError(t, err)
	lastID, err := res.LastInsertId()
	require.NoError(t, err)

	err = transitioner(context.Background())
	require.NoError(t, err)

	type blobURL struct {
		BlobURL sql.NullString `db:"blob_url"`
	}

	blobURLContainer := new(blobURL)
	found, err := storage.QueryRow(
		context.Background(),
		sqlxDB,
		blobURLContainer,
		"select row that was transitioned",
		"SELECT blob_url FROM ds_snapshot_blobs WHERE repository_id = ? AND id = ?",
		123456, lastID,
	)
	require.NoError(t, err)
	require.True(t, found)
	require.True(t, blobURLContainer.BlobURL.Valid)

	contents, err := blob.GetBlob(context.Background(), blobURLContainer.BlobURL.String)
	require.NoError(t, err)
	require.Equal(t, snapshotBlob, string(contents))
}

func TestConvertFromBlobURLTransition_DoesntUploadWhenBlobStoreDisabled(t *testing.T) {
	cfg := testutil.CreateTestConfig(t)
	cfg.Enterprise = true

	testDB, err := testutil.NewNamedTestDB(t, testutil.CreateTestConfig(t), log.NewNullLogger(), stats.NullStatter, "transitions_test")
	require.NoError(t, err)

	sqlxDB, err := db.NewSqlxDatabase(testDB.DB.GetRawSQLDBPrimary())
	require.NoError(t, err)

	t.Cleanup(func() {
		sqlxDB.Close()
	})

	blob := blobmock.GetTestBlobStorage(t)
	freno := frenomock.NewMockFrenoClient()
	transitioner := getBlobMigrationTransition(cfg, sqlxDB, blob, freno)

	snapshotBlob := "{\"someKey\": \"someValue\" }"
	res, err := storage.ExecuteQuery(
		context.Background(),
		sqlxDB,
		"insert row to convert",
		"INSERT INTO ds_snapshot_blobs (`blob`, blob_size_bytes, created_at, blob_hash, repository_id) VALUES (?, ?, ?, ?, ?)",
		snapshotBlob, len(snapshotBlob), time.Now(), "caa3e3d15a140a8b3b1c875b0e7b9e78f353729a6fa2afb595418cf336d2ba9c", 123456,
	)
	require.NoError(t, err)
	lastID, err := res.LastInsertId()
	require.NoError(t, err)

	err = transitioner(context.Background())
	require.NoError(t, err)

	type blobURL struct {
		BlobURL sql.NullString `db:"blob_url"`
	}

	blobURLContainer := new(blobURL)
	found, err := storage.QueryRow(
		context.Background(),
		sqlxDB,
		blobURLContainer,
		"select row that was transitioned",
		"SELECT blob_url FROM ds_snapshot_blobs WHERE repository_id = ? AND id = ?",
		123456, lastID,
	)
	require.NoError(t, err)
	require.True(t, found)
	require.False(t, blobURLContainer.BlobURL.Valid)
}
