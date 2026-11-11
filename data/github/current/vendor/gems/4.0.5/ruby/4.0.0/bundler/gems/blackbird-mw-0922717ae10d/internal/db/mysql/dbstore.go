package mysql

import (
	"context"
	"database/sql"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	throttler "github.com/github/go-freno-client/v2"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/repofilter"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"

	"golang.org/x/sync/semaphore"
)

// Store implements the store.Store interface.
type Store struct {
	db        db.RetryableDB
	throttler throttler.Throttler
	sem       *semaphore.Weighted
}

func New(conn db.RetryableDB, throttler throttler.Throttler) *Store {
	return &Store{
		db:        conn,
		throttler: throttler,
		sem:       semaphore.NewWeighted(10),
	}
}

func (s *Store) GetCorpusState(ctx context.Context, corpus routing.Corpus) (*db.CorpusState, error) {
	start := time.Now()
	defer func() { statting.DistributionMs(ctx, "get_corpus_state.query.duration", time.Since(start)) }()

	q := `
SELECT corpus_id, epoch_id, ingest_mode
FROM blackbird_corpus_state
WHERE corpus_id=?
LIMIT 1
`
	var state db.CorpusState
	err := sqlx.GetContext(ctx, s.db, &state, q, corpus)
	if err != nil {
		// We return a default value so that tests don't have to seed the database
		if errors.Is(err, sql.ErrNoRows) {
			return &db.CorpusState{Corpus: corpus}, nil
		}
		return nil, errors.Wrap(err, "couldn't find corpus state")
	}

	return &state, nil
}

func (s *Store) CreateEpoch(ctx context.Context, corpus routing.Corpus, description string) (*db.Epoch, error) {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, errors.Wrap(err, "could not start transaction to create epoch")
	}
	defer tx.Rollback() //nolint:errcheck

	sql := `
INSERT INTO blackbird_epochs (corpus_id, description, created_at, updated_at)
VALUES (?, ?, UTC_TIMESTAMP(), UTC_TIMESTAMP())
`
	res, err := tx.ExecContext(ctx, sql, corpus, description)
	if err != nil {
		return nil, errors.Wrap(err, "error creating epoch")
	}

	epochID, err := res.LastInsertId()
	if err != nil {
		return nil, errors.Wrap(err, "could not get epoch ID")
	}

	logging.Info(ctx, fmt.Sprintf("created epoch ID %d for corpus %s", epochID, corpus.String()))

	mode := db.IngestModeUnknown

	sql = `
INSERT INTO blackbird_corpus_state (corpus_id, epoch_id, ingest_mode)
VALUES (?, ?, ?)
ON DUPLICATE KEY UPDATE epoch_id=VALUES(epoch_id), ingest_mode=VALUES(ingest_mode)
`
	_, err = tx.ExecContext(ctx, sql, corpus, epochID, mode)
	if err != nil {
		return nil, errors.Wrap(err, "error updating corpus state to new epoch")
	}

	if err := tx.Commit(); err != nil {
		return nil, errors.Wrap(err, "could not update corpus state")
	}

	logging.Info(ctx, fmt.Sprintf("switched to %s ingest mode", mode.String()))
	statting.Counter(ctx, "ingest_mode_changed", 1, stats.Tags{"corpus": corpus.String(), "mode": mode.String()})

	return &db.Epoch{
		EpochID:     types.EpochID(epochID),
		Corpus:      corpus,
		Description: description,
	}, nil
}

func (s *Store) GetEpoch(ctx context.Context, epochID types.EpochID) (*db.Epoch, error) {
	q := `
SELECT id, corpus_id, description
FROM blackbird_epochs
WHERE id=?
LIMIT 1
`
	var epoch db.Epoch
	err := sqlx.GetContext(ctx, s.db, &epoch, q, epochID)
	if err != nil {
		// We return a default value so that tests don't have to seed the database
		if errors.Is(err, sql.ErrNoRows) {
			return &db.Epoch{EpochID: epochID}, nil
		}
		return nil, errors.Wrap(err, "couldn't find epoch")
	}
	return &epoch, nil
}

func (s *Store) UpdateEpochDescription(ctx context.Context, epochID types.EpochID, description string) error {
	q := "UPDATE blackbird_epochs SET description=? WHERE id=?"
	_, err := s.db.ExecContext(ctx, q, description, epochID)
	if err != nil {
		return fmt.Errorf("UpdateEpochDescription failed: %w", err)
	}
	return nil
}

func repoFromExternalData(apiRepo *github.Repository, refTip *gitaccess.RefTip, commitSeqNo sql.NullInt64) *db.Repository {
	return &db.Repository{
		RepoID:          apiRepo.ID,
		OwnerID:         apiRepo.OwnerID,
		OwnerLogin:      apiRepo.OwnerLogin,
		Name:            apiRepo.Name,
		IsPublic:        apiRepo.Public,
		IsArchived:      apiRepo.Archived,
		PushedAt:        sql.NullTime{Time: apiRepo.PushedAt, Valid: !apiRepo.PushedAt.IsZero()},
		CreatedAt:       sql.NullTime{Time: apiRepo.CreatedAt, Valid: !apiRepo.CreatedAt.IsZero()},
		HasLicense:      sql.NullBool{Bool: apiRepo.LicenseName != "", Valid: true},
		NumWatchers:     sql.NullInt32{Int32: apiRepo.NumWatchers, Valid: true},
		NumStars:        sql.NullInt32{Int32: apiRepo.NumStars, Valid: true},
		HasReadme:       sql.NullBool{Bool: apiRepo.HasReadme, Valid: true},
		PublicForkCount: sql.NullInt32{Int32: apiRepo.PublicForkCount, Valid: true},
		CommitSeqNo:     commitSeqNo,
		CommitOID:       refTip.CommitOID.Bytes(),
		NetworkID:       sql.NullInt32{Int32: int32(apiRepo.NetworkID), Valid: true},
		LicenseName:     sql.NullString{String: apiRepo.LicenseName, Valid: true},
		IsFork:          sql.NullBool{Bool: apiRepo.IsFork, Valid: true},
		Experiments:     apiRepo.Experiments,
		RepoSeqNo:       sql.NullInt64{Int64: int64(apiRepo.RepoSeqNo), Valid: true},
		BusinessID:      sql.NullInt64{Int64: int64(apiRepo.BusinessID), Valid: apiRepo.BusinessID != 0},
		BusinessSlug:    sql.NullString{String: apiRepo.BusinessSlug, Valid: apiRepo.BusinessSlug != ""},
	}
}

func (s *Store) insertRepository(ctx context.Context, dbRepo *db.Repository) (*db.Repository, error) {
	logging.Info(ctx, "inserting repository")
	start := time.Now()
	defer func() { statting.DistributionMs(ctx, "insert_repository.duration", time.Since(start)) }()

	q := `
INSERT IGNORE INTO blackbird_repositories (
  id, owner_id, owner_login, name, is_public, is_archived, pushed_at, created_at, deleted_at,
  has_license, num_watchers, num_stars, has_readme, public_fork_count, seq_no, commit_oid,
  network_id, license_name, is_fork, experiments, repo_seq_no, business_id, business_slug
)
VALUES (
  :id, :owner_id, :owner_login, :name, :is_public, :is_archived, :pushed_at, :created_at, :deleted_at,
  :has_license, :num_watchers, :num_stars, :has_readme, :public_fork_count, :seq_no, :commit_oid,
  :network_id, :license_name, :is_fork, :experiments, :repo_seq_no, :business_id, :business_slug
)`

	result, err := s.db.NamedExecContext(ctx, q, dbRepo)
	if err != nil {
		return nil, err
	}
	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, err
	}
	// This means another process raced and already inserted the repository.
	// The caller should retry the task.
	if rowsAffected == 0 {
		return nil, db.ErrInsertRaced
	}

	logging.Info(ctx, "repository inserted", kvp.Int64("repo_id", int64(dbRepo.RepoID)), kvp.String("commit_oid", hex.EncodeToString(dbRepo.CommitOID)))
	return dbRepo, nil
}

func (s *Store) updateRepository(ctx context.Context, dbRepo *db.Repository) (*db.Repository, error) {
	logging.Info(ctx, "updating repository")
	start := time.Now()
	defer func() { statting.DistributionMs(ctx, "update_repository.duration", time.Since(start)) }()

	q := `
UPDATE blackbird_repositories
SET
    owner_id          = :owner_id,
    owner_login       = :owner_login,
    name              = :name,
    is_public         = :is_public,
    is_archived       = :is_archived,
    pushed_at         = :pushed_at,
    created_at        = :created_at,
    has_license       = :has_license,
    num_watchers      = :num_watchers,
    num_stars         = :num_stars,
    has_readme        = :has_readme,
    public_fork_count = :public_fork_count,
    network_id        = :network_id,
    commit_oid        = :commit_oid,
    license_name      = :license_name,
    is_fork           = :is_fork,
    repo_seq_no       = :repo_seq_no,
    experiments       = :experiments,
    business_id       = :business_id,
    business_slug     = :business_slug,
    -- If :seq_no is NULL, this sets seq_no = 1; otherwise increments by 1
    seq_no            = IFNULL(:seq_no + 1, 1),
    deleted_at        = :deleted_at
WHERE
    id = :id
    AND (
      -- match when both sides are non-NULL and equal
      (seq_no = :seq_no)
      -- If :seq_no and seq_no are both NULL (i.e. never been set), MySQL requires an IS NULL check to match
      OR (seq_no IS NULL AND :seq_no IS NULL)
    );`

	result, err := s.db.NamedExecContext(ctx, q, dbRepo)
	if err != nil {
		return nil, err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, err
	}
	// This indicates the update did not succeed, most likely because another process raced
	// and updated the repository record before this process could complete the update.
	// The caller should retry the task.
	if rowsAffected == 0 {
		return nil, db.ErrUpdateRaced
	}

	// Retain the previous commit seq no for logging purposes only.
	prevCommitSeqNo := dbRepo.CommitSeqNo.Int64

	// The update succeeded, we need to increment the dbRepo's commit sequence number to reflect the DB's value.
	dbRepo.CommitSeqNo = sql.NullInt64{Int64: prevCommitSeqNo + 1, Valid: true}

	logging.Info(ctx, "repository updated", kvp.Int64("repo_id", int64(dbRepo.RepoID)), kvp.Int64("previous_seq_no", prevCommitSeqNo), kvp.Int64("current_seq_no", dbRepo.CommitSeqNo.Int64), kvp.String("commit_oid", hex.EncodeToString(dbRepo.CommitOID)))
	return dbRepo, nil
}

func (s *Store) RepositorySequence(ctx context.Context, repoID types.RepoID, fn db.RepoInfoFn) (*db.RepositoryResult, error) {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "repository_sequence.duration", time.Since(start))
	}()

	dbRepo, err := s.GetRepositoryByID(ctx, repoID)
	if err != nil {
		return nil, err
	}

	repoState := db.RepoInfoStateNew
	if dbRepo != nil {
		repoState = db.RepoInfoStateExisting
	}

	// get the external repo state from the callback
	startCallback := time.Now()
	skip, apiRepo, refTip, err := fn(ctx, repoState)
	if err != nil {
		statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "error"})
		logging.Error(ctx, "callback failed, aborting sequence number", kvp.Err(err), kvp.Duration("duration_ms", time.Since(startCallback)))
		return nil, err
	}

	if skip != nil {
		statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "skip"})
		return &db.RepositoryResult{Repository: dbRepo, GitHubRepository: apiRepo, RefTip: refTip, SkipReason: skip}, nil
	}
	statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "success"})

	if err := db.WaitOnThrottler(ctx, s.throttler, 1*time.Minute); err != nil {
		return nil, err
	}
	err = s.sem.Acquire(ctx, 1)
	if err != nil {
		return nil, err
	}
	defer s.sem.Release(1)

	if dbRepo == nil {
		repoToInsert := repoFromExternalData(apiRepo, refTip, sql.NullInt64{Int64: 1, Valid: true})
		dbRepo, err = s.insertRepository(ctx, repoToInsert)
		if err != nil {
			return nil, err
		}
		return &db.RepositoryResult{Repository: dbRepo, GitHubRepository: apiRepo, RefTip: refTip}, nil
	}

	// When the repo record exists but the callback metadata is the same as the database state, we can skip the update.
	if !db.RepositoryStateChanged(ctx, dbRepo, apiRepo, refTip) {
		return &db.RepositoryResult{Repository: dbRepo, GitHubRepository: apiRepo, RefTip: refTip}, nil
	}

	repoToUpdate := repoFromExternalData(apiRepo, refTip, dbRepo.CommitSeqNo)
	dbRepo, err = s.updateRepository(ctx, repoToUpdate)
	if err != nil {
		return nil, err
	}

	return &db.RepositoryResult{Repository: dbRepo, GitHubRepository: apiRepo, RefTip: refTip}, nil
}

func (s *Store) ErroredRepositorySequence(ctx context.Context, repoID types.RepoID, shouldDelete bool) (*db.SequenceNumbers, error) {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "errored_repository_sequence.duration", time.Since(start))
	}()

	dbRepo, err := s.GetRepositoryByID(ctx, repoID)
	if err != nil {
		return nil, err
	}

	if err := db.WaitOnThrottler(ctx, s.throttler, 1*time.Minute); err != nil {
		return nil, err
	}
	err = s.sem.Acquire(ctx, 1)
	if err != nil {
		return nil, err
	}
	defer s.sem.Release(1)

	if dbRepo == nil {
		// Note: All repos inserted by this code path have a `deleted_at` timestamp and will be removed eventually by GC.
		// NewDummyRepository automatically sets a DeletedAt timestamp to the current time.
		repoToInsert := db.NewDummyRepository(repoID)
		repoToInsert.CommitSeqNo = sql.NullInt64{Int64: 1, Valid: true}
		dbRepo, err = s.insertRepository(ctx, repoToInsert)
		if err != nil {
			return nil, err
		}
	} else {
		if shouldDelete {
			dbRepo.DeletedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
		}

		dbRepo, err = s.updateRepository(ctx, dbRepo)
		if err != nil {
			return nil, err
		}
	}

	return &db.SequenceNumbers{
		CommitSeqNo: uint64(dbRepo.CommitSeqNo.Int64),
		RepoSeqNo:   types.RepoSeqNo(dbRepo.RepoSeqNo.Int64),
	}, nil
}

// LoadRepositories looks up all records matching the filter in the
// blackbird_repositories table.
func (s *Store) LoadRepositories(ctx context.Context, filter repofilter.F, fn db.LoadRepoFn) error {
	start := time.Now()
	const defaultRepoBatchSize = 200_000
	err := s.LoadRepositoriesInBatches(ctx, defaultRepoBatchSize, filter, func(ctx context.Context, repos []*db.Repository) bool {
		for _, repo := range repos {
			if cont := fn(ctx, repo); !cont {
				return false
			}
		}

		return true
	})
	if err != nil {
		return err
	}

	statting.DistributionMs(ctx, "query.dbstore.load_all_repositories", time.Since(start))

	return nil
}

// LoadRepositoriesInBatches fetches all records matching the filter in the
// blackbird_repositories table in batches of size batchSize and passes them to
// fn.
func (s *Store) LoadRepositoriesInBatches(ctx context.Context, batchSize int, filter repofilter.F, fn db.LoadRepoBatchFn) error {
	return s.loadRepositoriesInBatchesWithQuerier(ctx, s.db, batchSize, filter, fn)
}

func (s *Store) loadRepositoriesInBatchesWithQuerier(
	ctx context.Context,
	querier sqlx.QueryerContext,
	batchSize int,
	filter repofilter.F,
	fn db.LoadRepoBatchFn,
) error {
	lastID := types.RepoID(0)

	start := time.Now()
	q := `
SELECT
  id, owner_id, owner_login, name, is_public, source_topic, deleted_at, is_archived, pushed_at, created_at, has_license, num_watchers, num_stars,
  has_readme, public_fork_count, seq_no, commit_oid, network_id, license_name, is_fork, experiments, repo_seq_no, business_id, business_slug
FROM blackbird_repositories
WHERE %s
ORDER BY id ASC
LIMIT ?
`
	for {
		batchStart := time.Now()
		repos := make([]*db.Repository, 0, batchSize)

		var where string
		var args []interface{}
		if lastID > 0 {
			where, args = filterToWhere(repofilter.And(repofilter.IDGreater(lastID), filter))
		} else {
			where, args = filterToWhere(filter)
		}
		q := fmt.Sprintf(q, where)

		err := sqlx.SelectContext(ctx, querier, &repos, q, append(args, batchSize)...)
		if err != nil {
			return errors.Wrap(err, "could not select repositories")
		}
		statting.DistributionMs(ctx, "query.dbstore.load_repository_batch", time.Since(batchStart))

		if cont := fn(ctx, repos); !cont {
			break
		}

		if len(repos) < batchSize {
			break
		}

		lastID = repos[len(repos)-1].RepoID
	}

	statting.DistributionMs(ctx, "query.dbstore.load_all_repositories_in_batches", time.Since(start))

	return nil

}

// GetRepositoryByID directly queries the blackbird_repositories table for a
// single repository. This must be kept up to date whenever the blackbird_repositories
// schema is updated. If no repo is found returns a nil value for the Repository,
// and nil for the error.
func (s *Store) GetRepositoryByID(ctx context.Context, id types.RepoID) (*db.Repository, error) {
	var repo db.Repository
	q := `
SELECT
  id, owner_id, owner_login, name, is_public, source_topic, deleted_at, is_archived, pushed_at, created_at, has_license, num_watchers, num_stars,
  has_readme, public_fork_count, seq_no, commit_oid, network_id, license_name, is_fork, experiments, repo_seq_no, business_id, business_slug
FROM blackbird_repositories
WHERE id = ?
`
	err := s.db.GetContext(ctx, &repo, q, id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, errors.WithMessagef(err, "failed to find repo %d", id)
	}

	// Workaround for trailing zero bytes stripped by migration blackbird-mw#4203.
	if len(repo.CommitOID) != 0 && len(repo.CommitOID) < 20 {
		logging.Error(ctx, "found truncated commit OID", kvp.Int("repo_id", int(repo.RepoID)))
		// Re-add trailling zero bytes.
		buf := make([]byte, 20-len(repo.CommitOID))
		repo.CommitOID = append(repo.CommitOID, buf...)
	}

	return &repo, nil
}

func (s *Store) GetFirstRepository(ctx context.Context, filter repofilter.F) (*db.Repository, error) {
	var repo *db.Repository
	err := s.LoadRepositories(ctx, filter, func(ctx context.Context, r *db.Repository) bool {
		repo = r
		return false
	})
	return repo, err
}

func (s *Store) GetFirstFileset(ctx context.Context, id uint64) (*db.Fileset, error) {
	q := `
SELECT
	repository_id, owner_id, fileset, deleted_at
FROM blackbird_external_filesets
WHERE repository_id = ?
LIMIT 1
`
	var fs db.Fileset
	err := sqlx.GetContext(ctx, s.db, &fs, q, id)
	if err != nil {
		return nil, err
	}
	return &fs, nil
}

func (s *Store) GetFirstFilesetByNWO(ctx context.Context, fileset types.NWO) (*db.Fileset, error) {
	q := `
SELECT
	repository_id, owner_id, fileset, deleted_at
FROM blackbird_external_filesets
WHERE fileset = ?
LIMIT 1
`
	var fs db.Fileset
	err := sqlx.GetContext(ctx, s.db, &fs, q, fileset)
	if err != nil {
		return nil, err
	}
	return &fs, nil
}

func (s *Store) GetRepositoryByNWO(ctx context.Context, nwo types.NWO) (*db.Repository, error) {
	var repo *db.Repository
	err := s.LoadRepositories(ctx, repofilter.And(repofilter.NotDeleted(), repofilter.NWO(nwo)), func(ctx context.Context, r *db.Repository) bool {
		repo = r
		return false
	})
	if err != nil {
		return nil, errors.WithMessagef(err, "failed to find %s", nwo)
	}

	return repo, nil
}

func (s *Store) LoadRepositoriesByIDs(ctx context.Context, repos map[types.RepoID]*db.Repository) error {
	if len(repos) == 0 {
		return nil
	}

	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "query.dbstore.load_repos_by_id", time.Since(start))
	}()

	filters := make([]repofilter.F, 0, len(repos))
	for repoID := range repos {
		filters = append(filters, repofilter.ID(repoID))
	}

	err := s.LoadRepositories(ctx, repofilter.And(repofilter.NotDeleted(), repofilter.Or(filters...)), func(ctx context.Context, repo *db.Repository) bool {
		repos[repo.RepoID] = repo
		return true
	})
	if err != nil {
		return errors.Wrap(err, "error selecting repositories by id")
	}

	return nil
}

func (s *Store) RepositoryExists(ctx context.Context, repoID types.RepoID) (bool, error) {
	var exists bool
	err := s.db.GetContext(ctx, &exists, "SELECT EXISTS(SELECT * FROM blackbird_repositories WHERE id=?)", repoID)
	return exists, err
}

func (s *Store) DeleteRepository(ctx context.Context, repoID types.RepoID) error {
	if err := db.WaitOnThrottler(ctx, s.throttler, 1*time.Minute); err != nil {
		return err
	}

	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return errors.Wrap(err, "could not start transaction to delete repository")
	}
	defer tx.Rollback() //nolint:errcheck

	q := "UPDATE blackbird_repositories SET deleted_at = UTC_TIMESTAMP() WHERE id = ?"
	_, err = tx.ExecContext(ctx, q, repoID)
	if err != nil {
		return errors.Wrap(err, "error deleting repository")
	}

	if err := tx.Commit(); err != nil {
		return errors.Wrap(err, "could not commit transaction to delete repository")
	}

	return nil
}

func filterToWhere(filter repofilter.F) (string, []interface{}) {
	switch ft := filter.(type) {
	case repofilter.IsAny:
		return "TRUE", []interface{}{}
	case repofilter.AndFilter:
		subclauses := make([]string, 0, len(ft.Filters))
		args := []interface{}{}
		for _, sub := range ft.Filters {
			where, subArgs := filterToWhere(sub)
			subclauses = append(subclauses, where)
			args = append(args, subArgs...)
		}
		return "(" + strings.Join(subclauses, " AND ") + ")", args
	case repofilter.OrFilter:
		subclauses := make([]string, 0, len(ft.Filters))
		args := []interface{}{}
		for _, sub := range ft.Filters {
			where, subArgs := filterToWhere(sub)
			subclauses = append(subclauses, where)
			args = append(args, subArgs...)
		}
		return "(" + strings.Join(subclauses, " OR ") + ")", args
	case repofilter.IsPublic:
		return "blackbird_repositories.is_public = TRUE", []interface{}{}
	case repofilter.IsDeleted:
		return "blackbird_repositories.deleted_at IS NOT NULL", []interface{}{}
	case repofilter.IsNotDeleted:
		return "blackbird_repositories.deleted_at IS NULL", []interface{}{}
	case repofilter.IDFilter:
		return "blackbird_repositories.id = ?", []interface{}{ft.ID}
	case repofilter.IDGreaterFilter:
		return "blackbird_repositories.id > ?", []interface{}{ft.ID}
	case repofilter.NWOFilter:
		return "(blackbird_repositories.owner_login = ? AND blackbird_repositories.name = ?)", []interface{}{ft.NWO.Owner().String(), ft.NWO.Name()}
	default:
		panic(fmt.Sprintf("unexpected filter type %+v", ft))
	}
}
