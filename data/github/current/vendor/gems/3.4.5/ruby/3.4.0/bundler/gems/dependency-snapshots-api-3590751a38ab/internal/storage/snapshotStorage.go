package storage

// This file is implicitly tested by snapshotRetrieval_test, since it's using the StoreSnapshot method to
// insert snapshots for its testing purposes.

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"strconv"
	"strings"
	"time"

	"github.com/github/dependency-snapshots-api/internal/interfaces"

	"github.com/pkg/errors"
)

// StorageSnapshot - Using a transaction, stores the given snapshot and updates all four of the necessary tables:
// `ds_build_types`, `ds_builds`, `ds_snapshot_blobs`, and `ds_snapshots`.
func (r *MySQLSnapshotsAdapter) StoreSnapshot(ctx context.Context, snapshot *interfaces.Snapshot) (snapshotID uint64, createdAt time.Time, result interfaces.SnapshotResult, returnErr error) {
	var createdTime time.Time

	// TEMPORARY HACK - set detector.name to 'unknown' if it's missing. Remove this after https://github.com/github/dependency-graph/issues/962
	if snapshot.Detector == nil {
		snapshot.Detector = &interfaces.DetectorMetadata{Name: "unknown"}
	}
	if len(snapshot.Detector.Name) == 0 {
		snapshot.Detector.Name = "unknown"
	}

	// convert snapshot into JSON
	snapshotJSON, err := snapshot.MarshalJSON()
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "marshalling snapshot failed")
	}

	if err := r.Freno.WaitForReplication(ctx); err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "snapshot creation failed waiting on replication lag")
	}

	// begin transaction to ensure we can roll back the snapshot creation if something goes wrong
	tx, err := r.DB.BeginTxx(ctx, &sql.TxOptions{
		Isolation: sql.LevelReadCommitted,
	})
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "snapshot storage transaction failed")
	}

	// bubble up snapshot creation rollback transaction failure
	defer func() {
		if p := recover(); p != nil {
			// make a last-ditch, no-error-handling effort to roll back the transaction
			tx.Rollback() // nolint: errcheck
			panic(p)
		}
		if returnErr != nil {
			txErr := tx.Rollback()
			if txErr != nil {
				returnErr = errors.Wrapf(returnErr, "with tx rollback error: %s", txErr)
			}
		}
	}()

	// get the build type ID, creating it first if necessary
	buildTypeID, err := getBuildTypeID(ctx, snapshot, tx)
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "getting build type ID failed")
	}

	// get the build ID, creating it first if necessary
	buildID, err := getBuildIDAndUpdateTime(ctx, buildTypeID, snapshot, tx)
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "getting build ID failed")
	}

	var blobURL string
	blobStorageEnabled := r.ShouldStoreBlobsInAzure && !r.ShouldStoreBlobsInDatabase

	// store snapshot in blob storage if appropriate (right now a non null blob client implies we want it in blob storage)
	if r.BlobClient != nil && blobStorageEnabled {
		blobURL, err = r.BlobClient.CreateBlob(ctx, strconv.FormatUint(snapshot.RepositoryID, 10), snapshotJSON)
		if err != nil {
			return 0, time.Time{}, interfaces.Error, errors.Wrap(err, "couldn't save snapshot JSON to blob storage")
		}
	}

	// get the blobID, creating it first if necessary
	blobID, err := getOrCreateSnapshotBlob(ctx, snapshot.RepositoryID, snapshotJSON, blobURL, tx, !blobStorageEnabled)
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "getting or creating snapshot blob failed")
	}

	// convert metadata into JSON
	metadataJSON, err := json.Marshal(snapshot.Metadata)
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "marshalling metadata failed")
	}

	// extract the source from the metadata, if possible
	var source string
	if _source, ok := snapshot.Metadata["source"]; ok {
		source = limitLength(_source.(string), 255)
	} else {
		source = ""
	}

	// insert the snapshot
	createdTime = time.Now()
	res, err := ExecuteQuery(ctx, tx, "InsertSnapshot", insertSnapshotSQLQuery,
		snapshot.RepositoryID,
		blobID,
		source,
		snapshot.SHA,
		snapshot.Internal,
		string(metadataJSON),
		createdTime,
		snapshot.Scanned,
		buildID,
		snapshot.Ref)

	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "inserting snapshot failed")
	}

	// get the new snapshot ID
	lastInsertedSnapshotID, err := res.LastInsertId()
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "getting new snapshot ID failed")
	}
	snapshotID = uint64(lastInsertedSnapshotID)
	snapshot.ID = snapshotID

	// if no errors are received from the above queries, commit the snapshot creation transaction
	err = tx.Commit()
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "committing transaction failed")
	}

	// update the canonical snapshot record if necessary. Note this happens outside the transaction.
	var updateMode interfaces.CanonicalUpdateMode
	if snapshot.Internal {
		updateMode = interfaces.InternalUpdateMode
	} else {
		updateMode = interfaces.DefaultUpdateMode
	}
	hadCanonicalUpdates, err := r.rectifyCanonicalSnapshot(ctx, r.Git, snapshot.RepositoryID, buildTypeID, updateMode)
	if err != nil {
		return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "rectifying canonical snapshot failed")
	}

	// update the denormalized dependencies table
	if hadCanonicalUpdates {
		err = r.denormalizeSnapshotDependencies(ctx, snapshot.RepositoryID)
		if err != nil {
			return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "denormalizing dependency information failed")
		}
	}

	var defaultBranch string
	if snapshot.Internal {
		// internal snapshots are only generated for the default branch, so we can skip Spokes here
		defaultBranch = strings.TrimPrefix(snapshot.Ref, "refs/heads/")
	} else {
		defaultBranch, err = r.Git.GetDefaultBranch(ctx, snapshot.RepositoryID)
		if err != nil {
			return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "rectifying canonical snapshot failed")
		}
	}

	branchName := strings.TrimPrefix(snapshot.Ref, "refs/heads/")

	if branchName != defaultBranch {
		result = interfaces.AcceptedNonDefaultBranch
	} else if branchName == defaultBranch && !hadCanonicalUpdates {
		result = interfaces.AcceptedHistorical
	} else if branchName == defaultBranch && hadCanonicalUpdates {
		result = interfaces.AcceptedCanonical
	}

	if result != interfaces.AcceptedCanonical && !r.ShouldStoreHistoricalSnapshots {
		// Note to reader: Delete is *NOT* transactionally bound with create due to calculation happening "later".
		err = deleteSnapshot(ctx, r.DB, snapshot.RepositoryID, snapshotID, &blobID)
		if err != nil {
			return 0, time.Time{}, interfaces.Error, errors.Wrapf(err, "deleting the previous snapshot failed")
		}
		snapshotID = 0
		createdTime = time.Time{}
		result = interfaces.SnapshotRemoved
	}

	return snapshotID, createdTime, result, nil
}

const deleteSnapshotQuery = // Parameters: (repository_id int, snapshot_id int)
` DELETE FROM ds_snapshots
	WHERE repository_id = ?
    AND id = ?`

const deleteSnapshotBlobQuery = // Parameters: (repository_id int, snapshot_blob_id int)
` DELETE dsb FROM ds_snapshot_blobs dsb
  LEFT JOIN ds_snapshots ds ON dsb.id = ds.snapshot_blob_id 
	WHERE dsb.repository_id = ?
		AND dsb.id = ?
		AND ISNULL(ds.id)`

const getSnapshotBlobIDForSnapshotQuery = // Parameters: (repository_id int, snapshot_id int)
`	SELECT s.snapshot_blob_id FROM ds_snapshots s WHERE s.repository_id = ? and s.id = ? LIMIT  1 `

func deleteSnapshot(ctx context.Context, queryable Queryable, repositoryID uint64, snapshotID uint64, snapshotBlobID *uint64) error {
	if snapshotBlobID == nil {
		type blobIDContainer struct {
			ID uint64 `db:"snapshot_blob_id"`
		}

		blobID := blobIDContainer{}
		_, err := QueryRow(ctx, queryable, &blobID, "GetSnapshotBlobIDForSnapshot", getSnapshotBlobIDForSnapshotQuery, repositoryID, snapshotID)
		if err != nil {
			return errors.Wrapf(err, "querying snapshot's blob id failed")
		}

		snapshotBlobID = &blobID.ID
	}

	_, err := ExecuteQuery(ctx, queryable, "DeleteSnapshot", deleteSnapshotQuery, repositoryID, snapshotID)
	if err != nil {
		return errors.Wrapf(err, "deleting snapshot row failed")
	}

	_, err = ExecuteQuery(ctx, queryable, "DeleteSnapshotBlob", deleteSnapshotBlobQuery, repositoryID, snapshotBlobID)
	if err != nil {
		return errors.Wrapf(err, "deleting snapshot blob row failed")
	}

	// GOTCHA TIME: If you are using this code outside of the enterprise scenario (Which is snapshots in DB, no history)
	//  then you need to ENHANCE this method to clean up blobs. It should check to see if a row was deleted in DeleteSnapshotBlob,
	//  and if it was, delete the blob. That would be dead code at the time of this comment writing so it's not implemented yet.

	return nil
}

// getOrCreateSnapshotBlob - Returns the ID of the given snapshot blob, inserting it into storage first if necessary.
func getOrCreateSnapshotBlob(ctx context.Context, repositoryID uint64, blob []byte, blobURL string, db Queryable, commitJSONToDB bool) (uint64, error) {
	var blobIDWrapper struct {
		ID uint64
	}
	blobHashBase64 := sha256HashHex(blob)
	ok, err := QueryRow(ctx, db, &blobIDWrapper, "SelectBlobID", selectBlobIDSQLQuery, repositoryID, blobHashBase64, len(blob))
	if err != nil {
		return 0, errors.Wrapf(err, "selecting blob ID failed")
	}
	if ok {
		return blobIDWrapper.ID, nil
	}

	var blobURLNullable sql.NullString
	if blobURL != "" {
		blobURLNullable = sql.NullString{String: blobURL, Valid: true}
	}

	var jsonBlobToStore string
	if commitJSONToDB {
		jsonBlobToStore = string(blob)
	} else {
		jsonBlobToStore = "{}"
	}

	// Blob does not exist yet, we'll create it here
	res, err := ExecuteQuery(ctx, db, "InsertSnapshotBlob", insertSnapshotBlobSQLQuery, repositoryID, jsonBlobToStore, len(blob), blobHashBase64, blobURLNullable)
	if err != nil {
		return 0, errors.Wrapf(err, "inserting blob failed")
	}
	lastInsertedBlobID, err := res.LastInsertId()
	return uint64(lastInsertedBlobID), err
}

// getBuildID - Returns the ID of the build type in the given snapshot, inserting it into the database first if necessary.
func getBuildTypeID(ctx context.Context, snapshot *interfaces.Snapshot, queryable Queryable) (uint64, error) {
	var buildTypeIDWrapper struct {
		ID uint64
	}

	correlator := limitLength(snapshot.Job.Correlator, 255)
	detectorName := limitLength(snapshot.Detector.Name, 255)

	ok, err := QueryRow(ctx, queryable, &buildTypeIDWrapper, "SelectBuildTypeID", selectBuildTypeIDSQLQuery, snapshot.RepositoryID, correlator, detectorName)
	if err != nil {
		return 0, errors.Wrapf(err, "selecting build type ID failed")
	}
	if ok {
		return buildTypeIDWrapper.ID, nil
	}

	// the build type ID was not found, so we'll create it
	res, err := ExecuteQuery(ctx, queryable, "InsertBuildType", insertBuildTypeSQLQuery, snapshot.RepositoryID, correlator, correlator, detectorName)
	if err != nil {
		return 0, errors.Wrapf(err, "creating build type failed")
	}

	lastInsertedBuildTypeID, err := res.LastInsertId()
	if err != nil {
		return 0, errors.Wrapf(err, "getting inserted id failed")
	}
	return uint64(lastInsertedBuildTypeID), nil
}

// getBuildIDAndUpdateTime - Returns the ID of the build in the given snapshot, inserting it into the database first if necessary.
// Also updates the build with the Scanned time.
func getBuildIDAndUpdateTime(ctx context.Context, buildTypeID uint64, snapshot *interfaces.Snapshot, queryable Queryable) (uint64, error) {
	var buildIDWrapper struct {
		ID uint64
	}

	// first check if the build already exists
	ok, err := QueryRow(ctx, queryable, &buildIDWrapper, "SelectBuildID", selectBuildIDSQLQuery, snapshot.RepositoryID, snapshot.Job.ID, buildTypeID)
	if err != nil {
		return 0, errors.Wrapf(err, "selecting build ID failed")
	}
	if ok {
		// it does exist, so we'll update the time
		_, err := ExecuteQuery(ctx, queryable, "UpdateBuild", updateBuildSQLQuery, snapshot.Scanned, snapshot.RepositoryID, buildIDWrapper.ID)
		if err != nil {
			return 0, errors.Wrapf(err, "updating build failed")
		}
		return buildIDWrapper.ID, nil
	}

	// the build ID doesn't exist, so we'll create it
	res, err := ExecuteQuery(ctx, queryable, "InsertBuild", insertBuildSQLQuery, snapshot.RepositoryID, snapshot.Job.ID, buildTypeID, snapshot.Scanned)
	if err != nil {
		return 0, errors.Wrapf(err, "inserting build failed")
	}

	// and return the ID, or an error if not found after create
	lastInsertedID, err := res.LastInsertId()
	if err != nil {
		return 0, errors.Wrapf(err, "getting last inserted id failed")
	}

	return uint64(lastInsertedID), nil
}

func sha256HashHex(bs []byte) string {
	hash := sha256.Sum256(bs)
	return hex.EncodeToString(hash[:])
}

// Parameters: (repository_id int, blob string, blob_size_bytes int, blob_hash string, blob_url string)
const insertSnapshotBlobSQLQuery = "insert into ds_snapshot_blobs" +
	// "blob" is a reserved name in MySQL, so it needs its own backticks.
	"( repository_id, `blob`, blob_size_bytes, created_at, blob_hash, blob_url)" +
	"values ( ?, ?, ?, now(), ?, ? )"

// Parameters: (repository_id int, blob_hash string, blob_size_bytes int)
const selectBlobIDSQLQuery = `
	select id
	from ds_snapshot_blobs
	where repository_id = ?
	and blob_hash = ?
	and blob_size_bytes = ?
	order by created_at desc
	limit 1`

// Parameters: (repository_id int, snapshot_blob_id int, source string,
// sha string, metadata string, created_at time.Time, scanned_at time.Time, build_id int,
// branch_ref string)
const insertSnapshotSQLQuery = `
	insert into ds_snapshots (
		repository_id,
		snapshot_blob_id,
		source,
		sha,
		internal,
		metadata,
		created_at,
		scanned_at,
		build_id,
		branch_ref
	) values (
		?,
		?,
		?,
		?,
		?,
		?,
		?,
		?,
		?,
		?)`

// Parameters: (repository_id int, external_type_id string, detector_name string)
const selectBuildTypeIDSQLQuery = `
	select id
	from ds_build_types
	where repository_id = ?
	and external_type_id = ?
	and detector_name = ?`

// Parameters: (repository_id int, external_build_id string, build_type_id int)
const selectBuildIDSQLQuery = `
	select id
	from ds_builds
	where repository_id = ?
    and external_build_id = ?
	and build_type_id = ?`

// Parameters: (scanned_at time.Time, repository_id int, build_id int)
const updateBuildSQLQuery = `
	update ds_builds
	set scanned_at = ?,
	updated_at = now()
	where repository_id = ?
    and id = ?`

// Parameters: (repository_id int, external_type_id string, external_type_id_display string, detector_name string)
const insertBuildTypeSQLQuery = `
	insert into ds_build_types (
		repository_id,
		external_type_id,
		external_type_id_display,
		detector_name,
		created_at,
		updated_at
	) values (
		?,
		?,
		?,
		?,
		now(),
		now()
	)`

// Parameters: (repository_id int, external_build_id string, build_type_id int, scanned_at time.Time)
const insertBuildSQLQuery = `
	insert into ds_builds (
		repository_id,
		external_build_id,
		build_type_id,
		scanned_at,
		created_at,
		updated_at
	) values (
		?,
		?,
		?,
		?,
		now(),
		now()
	)`

func limitLength(s string, maxLength int) string {
	if len(s) > maxLength {
		return s[:maxLength]
	}
	return s
}
