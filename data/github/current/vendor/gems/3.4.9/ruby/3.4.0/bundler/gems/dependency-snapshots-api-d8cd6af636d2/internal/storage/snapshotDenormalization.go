package storage

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"sort"
	"strconv"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/repolocks"
	"github.com/github/dependency-snapshots-api/internal/util"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/package-url/packageurl-go"
	"github.com/pkg/errors"
)

func (r *MySQLSnapshotsAdapter) denormalizeSnapshotDependencies(ctx context.Context, repositoryID uint64) (returnErr error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "CreateDependencySnapshot", "denormalizeSnapshotDependencies",
		kvp.Uint64("repositoryID", repositoryID),
	)
	defer ender()
	maxTries := 3
	baseDelay := time.Millisecond * 5

	_, err := util.Retry(maxTries, baseDelay, func() (struct{}, bool, error) {
		retryable, err := r.decomposeDependencyInformationOnce(ctx, repositoryID, maxTries)
		return struct{}{}, retryable, err
	})
	if err != nil {
		return err
	}

	return nil
}

type repositoryDependency struct {
	RepositoryID      uint64 `db:"repository_id"`
	DependencyLocator string `db:"dependency_locator"`
	DependencyVersion string `db:"dependency_version"`
	PackageURL        string `db:"purl"`
}

func (r *MySQLSnapshotsAdapter) decomposeDependencyInformationOnce(ctx context.Context, repositoryID uint64, tryCount int) (retryable bool, returnErr error) {
	const lockDuration = 20 * time.Second

	repoLock, err := r.AdapterOptions.RepoLocker.WaitLock(ctx, time.Minute, repositoryID, "denormalization_lock", lockDuration)
	if err != nil {
		if errors.Is(err, repolocks.ErrAlreadyLocked) {
			return true, err
		}
		return false, err
	}
	defer repoLock.Unlock()

	// since we don't know exactly how long this will take, we should re-acquire the lock if we're still processing past the lock duration.
	// the returned ctx will be cancelled if we ever lose the lock.
	ctx = repoLock.StartRelocker(ctx)

	// Check whether there are any updates to make by comparing a hash of the
	// canonical snapshot ids with the saved hash of the set used for the last
	// saved index
	snapshotIDs, err := r.canonicalSnapshotIDsForRepository(ctx, r.DB, repositoryID)
	if err != nil {
		return false, errors.Wrapf(err, "fetching canonical snapshot IDs for a repository failed")
	}

	storedHash, err := getIndexedSnapshotsHash(ctx, r.DB, repositoryID)
	if err != nil {
		return false, errors.Wrapf(err, "fetching indexed snapshot hash failed")
	}

	if hashSnapshotIDs(snapshotIDs) == storedHash {
		contextlogger.Info(ctx, "Skipping snapshot index update", kvp.Uint64("repositoryID", repositoryID))
		return false, nil
	}

	snapshots, err := r.canonicalSnapshotsForRepository(ctx, r.DB, repositoryID, interfaces.IncludeInternal)
	if err != nil {
		return false, errors.Wrapf(err, "fetching canonical snapshots for a repository failed")
	}

	indexedSnapshotIDs := make([]uint64, len(snapshots))
	for i, s := range snapshots {
		indexedSnapshotIDs[i] = s.ID
	}
	indexedSnapshotsHash := hashSnapshotIDs(indexedSnapshotIDs)

	afterFetch := time.Now()
	snapIds := make([]uint64, len(snapshots))
	for i, s := range snapshots {
		snapIds[i] = s.ID
	}

	repositoryDependencySet, err := generateRepositoryDependencySet(snapshots, repositoryID)
	if err != nil {
		return false, errors.Wrapf(err, "repository dependency map could not be generated")
	}

	repositoryDependencies := repositoryDependencySet.Values()

	afterGenerate := time.Now()

	// This should generally be a no-op, but it's plausible something interrupted the process the last time and we have staging entries hanging around.
	_, err = ExecuteQuery(ctx, r.DB, "CleanupStagedDependencies", deleteStagedRepositoryDependenciesQuery, repositoryID)
	if err != nil {
		return false, errors.Wrapf(err, "cleaning up staged repository dependencies failed")
	}

	if len(repositoryDependencies) > 0 {
		_, err = NamedExec(ctx, r.DB, "InsertRepositoryDependencies", insertStagedRepositoryDependenciesQuery, repositoryDependencies)
		if err != nil {
			retryable = false
			// Deadlock or cancelled query
			if db.IsMysqlDeadlockError(err) || db.IsMysqlQueryInterrupted(err) {
				retryable = true
			}

			// Report all errors here
			// Errors in the reporting function are ignored here because they are logged from within the reporter itself
			_ = r.GetReporter().Report(ctx, err, map[string]string{
				"code.function": "decomposeDependencyInformationOnce",
				"gh.repo.id":    strconv.FormatUint(repositoryID, 10),
				"gh.will_retry": strconv.FormatBool(retryable),
				"gh.try_count":  strconv.Itoa(tryCount),
			})

			// Log the error if it is not a "record not unique" error (to avoid spamming the logs)
			if !db.IsMysqlRecordNotUnique(err) {
				contextlogger.Error(ctx, "Inserting staged repository dependencies failed",
					kvp.String("code.function", "decomposeDependencyInformationOnce"),
					kvp.Uint64("gh.repo.id", repositoryID),
					kvp.String("exception.message", util.Truncate(err.Error(), 512)),
					kvp.Bool("gh.will_retry", retryable),
					kvp.Int("gh.try_count", tryCount),
				)
			}
		}
	}

	afterStagedInsert := time.Now()
	err = stageAndSwapDependencies(r, ctx, repositoryID, indexedSnapshotsHash)

	kvps := []kvp.Field{
		kvp.Int64("numberDependencies", int64(len(repositoryDependencies))),
		kvp.Uint64("repositoryID", repositoryID),
		kvp.Uint("generateTimeTakenMs", uint(afterGenerate.Sub(afterFetch).Milliseconds())),
		kvp.Uint("insertTimeTakenMs", uint(afterStagedInsert.Sub(afterGenerate).Milliseconds())),
		kvp.Uint("stageSwapTimeTakenMs", uint(time.Since(afterStagedInsert).Milliseconds())),
		kvp.Int("tryCount", tryCount),
	}
	if err != nil {
		kvps = append(kvps, kvp.String("error", err.Error()))
	}

	contextlogger.Info(ctx, "Bulk insertion of repository dependencies", kvps...)

	if err != nil {
		return retryable, errors.Wrapf(err, "bulk insertion of repository dependencies failed")
	}

	return false, nil
}

func stageAndSwapDependencies(r *MySQLSnapshotsAdapter, ctx context.Context, repositoryID uint64, snapshotHash string) error {
	tx, err := r.DB.BeginTxx(ctx, &sql.TxOptions{
		Isolation: sql.LevelReadCommitted,
	})
	if err != nil {
		return errors.Wrapf(err, "beginning a transaction failed")
	}

	_, err = ExecuteQuery(ctx, tx, "DeleteUnstagedDependencies", deleteUnstagedRepositoryDependenciesQuery, repositoryID)
	if err != nil {
		return errors.Wrapf(err, "cleaning up unstaged repository dependencies failed")
	}

	_, err = ExecuteQuery(ctx, tx, "SwapStagedRepositoryDependencies", swapStagedRepositoryDependenciesQuery, repositoryID)
	if err != nil {
		return errors.Wrapf(err, "swapping staged repository dependencies failed")
	}

	_, err = ExecuteQuery(ctx, tx, "UpdateSnapshotHash", updateIndexedSnapshotHashQuery, repositoryID, snapshotHash, snapshotHash)
	if err != nil {
		return errors.Wrapf(err, "updating indexed snapshot hash failed")
	}

	err = tx.Commit()
	if err != nil {
		return errors.Wrapf(err, "committing transaction to swap dependencies failed")
	}
	return nil
}

func hashSnapshotIDs(ids []uint64) string {
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	idString := fmt.Sprintf("%v", ids)
	bs := sha256.Sum256([]byte(idString))
	hash := hex.EncodeToString(bs[:])
	return hash
}

func generateRepositoryDependencySet(snapshots []*interfaces.Snapshot, repositoryID uint64) (util.Set[repositoryDependency], error) {
	repositoryDependencySet := util.NewSet[repositoryDependency]()
	for _, s := range snapshots {
		for _, m := range s.Manifests {
			for _, d := range m.Resolved {
				purl, err := packageurl.FromString(d.PackageURL)

				if err != nil {
					return repositoryDependencySet, err
				}

				locatorPurl := getDependencyLocatorPURL(purl)
				strippedPurl := getStrippedPURLWithVersion(purl)
				repositoryDependencySet.Add(repositoryDependency{RepositoryID: repositoryID, DependencyLocator: locatorPurl.String(), DependencyVersion: purl.Version, PackageURL: strippedPurl.String()})
			}
		}
	}
	return repositoryDependencySet, nil
}

// Parameters: (repository_id bigint)
const getIndexedSnapshotsHashQuery = `
    SELECT snapshots_hash
    FROM ds_repository_denormalization_snapshots
	WHERE repository_id = ?
`

func getIndexedSnapshotsHash(ctx context.Context, queryable Queryable, repositoryID uint64) (string, error) {
	var hashStruct struct {
		SnapshotHash string `db:"snapshots_hash"`
	}
	ok, err := QueryRow(ctx, queryable, &hashStruct, "GetIndexedSnapshotsHash", getIndexedSnapshotsHashQuery, repositoryID)
	if !ok || err != nil {
		return "", err
	}

	return hashStruct.SnapshotHash, nil
}

// Parameters: (repository_id bigint, hash string)
const updateIndexedSnapshotHashQuery = `
	INSERT INTO ds_repository_denormalization_snapshots (
		repository_id,
		snapshots_hash
    ) values (
		?, ?
	)
    ON DUPLICATE KEY UPDATE
    snapshots_hash = ?
`

// Parameters: (repository_id bigint)
const deleteStagedRepositoryDependenciesQuery = `
	DELETE FROM ds_repository_dependencies_staged
	WHERE repository_id = ? AND staged = 1
`

// Parameters: (repository_id bigint)
const deleteUnstagedRepositoryDependenciesQuery = `
	DELETE FROM ds_repository_dependencies_staged
	WHERE repository_id = ? AND staged = 0
`

// Parameters: (repository_id bigint, repository_id bigint)
const swapStagedRepositoryDependenciesQuery = `
	UPDATE ds_repository_dependencies_staged
	SET staged = staged ^ 1
	WHERE repository_id = ?;
`

// Parameters: (repository_id bigint, dependency_locator string, purl string)
const insertStagedRepositoryDependenciesQuery = `
	insert into ds_repository_dependencies_staged (
		repository_id,
		staged,
		dependency_locator,
		dependency_version,
		purl
	) values (
		:repository_id, 1, :dependency_locator, :dependency_version, :purl
	)`
