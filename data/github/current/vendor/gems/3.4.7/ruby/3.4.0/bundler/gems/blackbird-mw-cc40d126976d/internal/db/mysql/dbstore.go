package mysql

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	throttler "github.com/github/go-freno-client"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/repofilter"
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

func (s *Store) SetCorpusIngestMode(ctx context.Context, corpus routing.Corpus, from, to db.IngestMode) (bool, error) {
	ctx = logging.With(ctx, kvp.String("corpus", corpus.String()))

	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return false, errors.Wrap(err, "could not start transaction to switch ingest modes")
	}
	defer tx.Rollback() //nolint:errcheck

	// Do a select before updating to enforce state transition and handle any
	// potential races.
	var c db.CorpusState
	q := `
SELECT corpus_id, epoch_id, ingest_mode
FROM blackbird_corpus_state
WHERE corpus_id=?
LIMIT 1`
	if err := tx.GetContext(ctx, &c, q, corpus); err != nil {
		return false, errors.Wrap(err, "failed to select corpus")
	}

	if c.IngestMode != from {
		logging.Info(ctx, "not transitioning ingest mode: from_mode != current_mode", kvp.String("current_mode", c.IngestMode.String()), kvp.String("from_mode", from.String()), kvp.String("to_mode", to.String()))
		return false, nil // NB: Not in the mode we think we are
	}
	if c.IngestMode == to {
		logging.Info(ctx, "not transitioning ingest mode: already in new mode", kvp.String("current_mode", c.IngestMode.String()), kvp.String("from_mode", from.String()), kvp.String("to_mode", to.String()))
		return false, nil // NB: Mode already set
	}

	if c.IngestMode+1 != to {
		return false, fmt.Errorf("cannot move from ingest mode %s to %s", c.IngestMode.String(), to.String())
	}

	q = `
UPDATE blackbird_corpus_state SET ingest_mode=?
WHERE corpus_id=?`
	_, err = tx.ExecContext(ctx, q, to, corpus)
	if err != nil {
		return false, errors.Wrap(err, "unable to set corpus state")
	}

	err = tx.Commit()
	if err != nil {
		return false, err
	}

	logging.Info(ctx, fmt.Sprintf("switched to %s ingest mode", to.String()))
	statting.Counter(ctx, "ingest_mode_changed", 1, stats.Tags{"corpus": corpus.String(), "mode": to.String()})
	return true, nil
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

	mode := db.IngestModeBackfill

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

func (s *Store) GetEpochEndOffsets(ctx context.Context, epochID types.EpochID) (db.EpochOffsets, error) {
	q := "SELECT epoch_id, kafka_partition, kafka_offset FROM blackbird_epoch_offsets WHERE epoch_id=?"
	var rows []*db.EpochOffset
	if err := s.db.SelectContext(ctx, &rows, q, epochID); err != nil {
		return nil, errors.WithStack(err)
	}

	offsets := make(db.EpochOffsets)
	for _, o := range rows {
		offsets.Set(o.Partition, o.Offset)
	}
	return offsets, nil
}

func (s *Store) SetEpochEndOffsets(ctx context.Context, epochID types.EpochID, offsets db.EpochOffsets) error {
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return errors.WithStack(err)
	}
	defer tx.Rollback() //nolint:errcheck

	for partition, offset := range offsets {
		q := "INSERT INTO blackbird_epoch_offsets (epoch_id, kafka_partition, kafka_offset) VALUES (?, ?, ?)"
		if _, err := tx.ExecContext(ctx, q, epochID, partition, offset); err != nil {
			return errors.WithStack(err)
		}
	}

	if err := tx.Commit(); err != nil {
		return errors.WithStack(err)
	}
	return nil
}

func (s *Store) repositorySequenceWithTxn(ctx context.Context, repoID types.RepoID, fn db.RepoInfoFn) (*db.RepositoryResult, error) {
	if err := db.WaitOnThrottler(ctx, s.throttler, 1*time.Minute); err != nil {
		return nil, err
	}

	err := s.sem.Acquire(ctx, 1)
	if err != nil {
		return nil, err
	}
	defer s.sem.Release(1)

	start := time.Now()
	defer func() { statting.DistributionMs(ctx, "repository_sequence.txn.duration", time.Since(start)) }()
	tx, err := s.db.BeginTxx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback() //nolint:errcheck

	// select the current repo state and lock the row
	q := `
SELECT
  id, owner_id, owner_login, name, is_public, source_topic, deleted_at, is_archived, pushed_at, created_at, has_license, num_watchers, num_stars,
  has_readme, public_fork_count, seq_no, commit_oid, network_id, license_name, is_fork, experiments, repo_seq_no
FROM blackbird_repositories
WHERE id = ?
FOR UPDATE NOWAIT
`
	repoInfoState := db.RepoInfoStateExisting
	repo := &db.Repository{}
	err = tx.GetContext(ctx, repo, q, repoID)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}

		// We don't know the values yet, so insert dummies values for NOT NULL colums.
		repoInfoState = db.RepoInfoStateNew
		repo = db.NewDummyRepository(repoID)
		q = "INSERT INTO blackbird_repositories (id, owner_id, owner_login, name, deleted_at, seq_no) VALUES (?, ?, ?, ?, UTC_TIMESTAMP(), 0)"
		_, err := tx.ExecContext(ctx, q, repo.RepoID, repo.OwnerID, repo.OwnerLogin, repo.Name)
		if err != nil {
			return nil, err
		}
	}

	// get the external repo state from the callback
	startCallback := time.Now()
	skip, apiRepo, refTip, err := fn(ctx, repoInfoState)
	if err != nil {
		statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "error"})
		logging.Error(ctx, "callback failed, aborting sequence number", kvp.Err(err), kvp.Duration("duration_ms", time.Since(startCallback)))
		return nil, err
	}

	if skip != nil {
		statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "skip"})
		return &db.RepositoryResult{SkipReason: skip}, nil
	}

	statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "success"})

	if !db.RepositoryStateChanged(ctx, repo, apiRepo, refTip) {
		logging.Info(ctx, "repository state did not change, will roll back transaction")
		// tx will be rolled back
		return &db.RepositoryResult{Repository: repo, GitHubRepository: apiRepo, RefTip: refTip}, nil
	}

	q = `
UPDATE blackbird_repositories SET
  owner_id=?, owner_login=?, name=?, is_public=?, is_archived=?, pushed_at=?, created_at=?, has_license=?, num_watchers=?,
  num_stars=?, has_readme=?, public_fork_count=?, network_id=?, commit_oid=?, license_name=?, is_fork=?, repo_seq_no=?, experiments=?, seq_no=IFNULL(seq_no+1, 1), deleted_at=NULL
WHERE id = ?
`
	_, err = tx.ExecContext(
		ctx,
		q,
		apiRepo.OwnerID,
		apiRepo.OwnerLogin,
		apiRepo.Name,
		apiRepo.Public,
		apiRepo.Archived,
		sql.NullTime{Time: apiRepo.PushedAt, Valid: !apiRepo.PushedAt.IsZero()},
		sql.NullTime{Time: apiRepo.CreatedAt, Valid: !apiRepo.CreatedAt.IsZero()},
		apiRepo.LicenseName != "",
		apiRepo.NumWatchers,
		apiRepo.NumStars,
		apiRepo.HasReadme,
		apiRepo.PublicForkCount,
		apiRepo.NetworkID,
		refTip.CommitOID.Bytes(),
		apiRepo.LicenseName,
		apiRepo.IsFork,
		int64(apiRepo.RepoSeqNo),
		apiRepo.Experiments,
		apiRepo.ID,
	)
	if err != nil {
		return nil, err
	}

	logging.Info(ctx, "repository state changed, updated row")

	// reload repository to get latest value, including new sequence number
	err = s.loadRepositoriesInBatchesWithQuerier(ctx, tx, 1, repofilter.ID(repoID), func(ctx context.Context, repos []*db.Repository) bool {
		for _, r := range repos {
			repo = r
			return false
		}
		return false
	})
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commiting transaction failed: %w", err)
	}

	return &db.RepositoryResult{Repository: repo, GitHubRepository: apiRepo, RefTip: refTip}, nil
}

func (s *Store) RepositorySequence(ctx context.Context, repoID types.RepoID, fn db.RepoInfoFn) (*db.RepositoryResult, error) {
	repo, err := s.GetRepositoryByID(ctx, repoID)
	if err != nil {
		return nil, err
	}
	if repo == nil {
		return s.repositorySequenceWithTxn(ctx, repoID, fn)
	}

	// get the external repo state from the callback
	startCallback := time.Now()
	skip, apiRepo, refTip, err := fn(ctx, db.RepoInfoStateExisting)
	if err != nil {
		statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "error"})
		logging.Error(ctx, "callback failed, aborting sequence number", kvp.Err(err), kvp.Duration("duration_ms", time.Since(startCallback)))
		return nil, err
	}

	if skip != nil {
		statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "skip"})
		return &db.RepositoryResult{SkipReason: skip}, nil
	}

	statting.DistributionMs(ctx, "repository_sequence.callback.duration", time.Since(startCallback), stats.Tags{"status": "success"})

	if !db.RepositoryStateChanged(ctx, repo, apiRepo, refTip) {
		logging.Info(ctx, "repository state did not change")
		return &db.RepositoryResult{Repository: repo, GitHubRepository: apiRepo, RefTip: refTip}, nil
	}

	// Repository state changed, so we must fallback to using a transaction.
	return s.repositorySequenceWithTxn(ctx, repoID, fn)
}

func (s *Store) ErroredRepositorySequence(ctx context.Context, repoID types.RepoID, deleted bool) (*db.SequenceNumbers, error) {
	if err := db.WaitOnThrottler(ctx, s.throttler, 1*time.Minute); err != nil {
		return nil, err
	}

	start := time.Now()
	defer func() { statting.DistributionMs(ctx, "errored_repository_sequence.txn.duration", time.Since(start)) }()
	tx, err := s.db.BeginTxx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback() //nolint:errcheck

	// lock the repository row
	q := `
SELECT
  id, owner_id, owner_login, name, is_public, source_topic, deleted_at, is_archived, pushed_at, created_at, has_license, num_watchers, num_stars,
  has_readme, public_fork_count, seq_no, commit_oid, network_id, license_name, is_fork, experiments, repo_seq_no
FROM blackbird_repositories
WHERE id = ?
FOR UPDATE NOWAIT
`
	repo := &db.Repository{}
	err = tx.GetContext(ctx, repo, q, repoID)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, err
		}

		// We don't know the values, so insert dummies values for NOT NULL colums.
		repo = db.NewDummyRepository(repoID)
		q = "INSERT INTO blackbird_repositories (id, owner_id, owner_login, name, deleted_at, seq_no) VALUES (?, ?, ?, ?, UTC_TIMESTAMP(), 0)"
		_, err := tx.ExecContext(ctx, q, repo.RepoID, repo.OwnerID, repo.OwnerLogin, repo.Name)
		if err != nil {
			return nil, err
		}
	}

	if deleted {
		q = "UPDATE blackbird_repositories SET seq_no=IFNULL(seq_no+1, 1), deleted_at=UTC_TIMESTAMP() WHERE id=?"
		_, err = tx.ExecContext(ctx, q, repoID)
	} else {
		q = "UPDATE blackbird_repositories SET seq_no=IFNULL(seq_no+1, 1) WHERE id=?"
		_, err = tx.ExecContext(ctx, q, repoID)
	}
	if err != nil {
		return nil, err
	}

	var sequenceNos db.SequenceNumbers
	err = tx.GetContext(ctx, &sequenceNos, "SELECT seq_no, IFNULL(repo_seq_no, 0) AS repo_seq_no FROM blackbird_repositories WHERE id=?", repoID)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commiting transaction failed: %w", err)
	}

	return &sequenceNos, nil
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
  has_readme, public_fork_count, seq_no, commit_oid, network_id, license_name, is_fork, experiments, repo_seq_no
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
  has_readme, public_fork_count, seq_no, commit_oid, network_id, license_name, is_fork, experiments, repo_seq_no
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
