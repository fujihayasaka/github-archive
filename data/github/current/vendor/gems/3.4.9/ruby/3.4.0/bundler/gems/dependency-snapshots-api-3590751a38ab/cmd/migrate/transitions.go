package main

import (
	"context"
	"fmt"
	"strconv"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/freno"
	"github.com/github/dependency-snapshots-api/internal/storage"
	"github.com/github/dependency-snapshots-api/internal/storage/blob"
	"github.com/github/go-dbmigrator"
	"github.com/jmoiron/sqlx"
)

// All transitions need to support re-run -- Transitions can be run multiple times if the their timestamp is >= migration timestamp.
// They don't need to do the full activity (e.g. they can just check if they already ran), but they should not error in this case.
func getTransitions(cfg *config.Config, db *sqlx.DB, blob blob.BlobClient, freno *freno.FrenoClient) (*dbmigrator.Transitioner, error) {
	trans := dbmigrator.NewTransitioner()

	// When writing transitions, you may need to be keenly aware of storage behavior modification enabled by Enterprise value in cfg:
	//  both the shouldStoreHistoricalSnapshots and shouldStoreBlobsInDatabase properties are influenced by Enterprise settings.

	err := trans.Add(20220822213515, getMigrationTableTransferTransition(cfg, db))
	if err != nil {
		return nil, err
	}

	err = trans.Add(20220621203053, getBlobMigrationTransition(cfg, db, blob, freno))

	if err != nil {
		return nil, err
	}

	return trans, nil
}

// getBlobMigrationTransition returns a transition that checks for snapshot_blobs
// rows that aren't stored in blob storage, and puts them there.
func getBlobMigrationTransition(cfg *config.Config, db *sqlx.DB, blob blob.BlobClient, freno *freno.FrenoClient) dbmigrator.MigrationFunc {
	return func(ctx context.Context) error {
		if cfg.Enterprise {
			return nil
		}

		type row struct {
			SnapshotBlobID uint64 `db:"id"`
			RepositoryID   uint64 `db:"repository_id"`
			BlobJSON       string `db:"blob"`
		}

		results := make([]row, 0)
		rowHandler := func(rows *sqlx.Rows) error {
			row := row{}
			err := rows.StructScan(&row)
			if err != nil {
				return err
			}
			results = append(results, row)
			return nil
		}

		err := storage.ExecuteQueryAndReadRows(ctx, db, rowHandler, "transitionToBlobStorage_getCandidates", "SELECT sb.id, sb.repository_id, sb.blob FROM ds_snapshot_blobs sb where sb.blob_url is null;")
		if err != nil {
			return err
		}

		for _, row := range results {
			blobURL, err := blob.CreateBlob(ctx, strconv.FormatUint(row.RepositoryID, 10), []byte(row.BlobJSON))
			if err != nil {
				return err
			}

			err = freno.WaitForReplication(ctx)
			if err != nil {
				return err
			}

			_, err = storage.ExecuteQuery(ctx, db, "transitionToBlobStorage_writeUpdatedURL", "UPDATE ds_snapshot_blobs SET blob_url = ? WHERE repository_id = ? AND id = ?", blobURL, row.RepositoryID, row.SnapshotBlobID)
			if err != nil {
				return err
			}
		}

		return nil
	}
}

// getMigrationTableTransferTransition returns a transition that moves rows from
// snapshots_migrations to ds_migrations
func getMigrationTableTransferTransition(cfg *config.Config, db *sqlx.DB) dbmigrator.MigrationFunc {
	return func(ctx context.Context) error {
		var count int
		err := db.QueryRow("SELECT COUNT(*) FROM snapshots_migrations;").Scan(&count)
		if err != nil {
			// No table is not scary, it just means the table has been deleted.
			contextlogger.Info(context.Background(), "Snapshot migration was skipped, no source table found.")
		} else {
			res, err := storage.ExecuteQuery(ctx, db, "transitionToMigrationTable", "INSERT IGNORE INTO ds_migrations(version, dirty) select version,dirty from snapshots_migrations;")
			if err != nil {
				return err
			}

			rows, err := res.RowsAffected()
			if err != nil {
				return err
			}

			contextlogger.Info(context.Background(), fmt.Sprintf("Transitioned migration tables, migrating %v rows", rows))
		}

		return nil
	}
}
