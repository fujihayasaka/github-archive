package noop

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/github/go-telemetry/logging"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/repofilter"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

func New(repos ...*db.Repository) *Store {
	corpusState := make(map[routing.Corpus]db.CorpusState)
	for _, corpus := range routing.Corpora {
		corpusState[corpus] = db.CorpusState{Corpus: corpus}
	}

	return &Store{
		corpusState: corpusState,
		Repos:       repos,
	}
}

type Store struct {
	mutex       sync.Mutex
	corpusState map[routing.Corpus]db.CorpusState
	Repos       []*db.Repository
}

func (s *Store) RepositorySequence(ctx context.Context, repoID types.RepoID, fn db.RepoInfoFn) (*db.RepositoryResult, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	var repo *db.Repository
	for _, r := range s.Repos {
		if r.RepoID == repoID {
			repo = r
			break
		}
	}

	// NOTE: This is the upsert case - details will be filled in from apiRepo if
	// the callback succeeds. The repository will not be inserted unless the
	// callback succeeds, mimicing the transactional behavior of the real store.
	repoInfoState := db.RepoInfoStateExisting
	if repo == nil {
		repoInfoState = db.RepoInfoStateNew
		repo = db.NewDummyRepository(repoID)
	}

	skip, apiRepo, refTip, err := fn(ctx, repoInfoState)
	if err != nil {
		return nil, err
	}

	if skip != nil {
		return &db.RepositoryResult{SkipReason: skip}, nil
	}

	if !db.RepositoryStateChanged(ctx, repo, apiRepo, refTip) {
		return &db.RepositoryResult{Repository: repo, GitHubRepository: apiRepo, RefTip: refTip}, nil
	}

	repo.OwnerID = apiRepo.OwnerID
	repo.OwnerLogin = apiRepo.OwnerLogin
	repo.Name = apiRepo.Name
	repo.NetworkID = sql.NullInt32{Int32: int32(apiRepo.NetworkID), Valid: true}
	repo.IsArchived = apiRepo.Archived
	repo.IsPublic = apiRepo.Public
	repo.IsFork = sql.NullBool{Bool: apiRepo.IsFork, Valid: true}
	repo.NumStars = sql.NullInt32{Int32: apiRepo.NumStars, Valid: true}
	repo.NumWatchers = sql.NullInt32{Int32: apiRepo.NumWatchers, Valid: true}
	repo.HasLicense = sql.NullBool{Bool: apiRepo.LicenseName != "", Valid: true}
	repo.LicenseName = sql.NullString{String: apiRepo.LicenseName, Valid: true} // NOTE: We store empty strings as valid in the production database
	repo.HasReadme = sql.NullBool{Bool: apiRepo.HasReadme, Valid: true}
	repo.Experiments = apiRepo.Experiments
	repo.CreatedAt = sql.NullTime{Time: apiRepo.CreatedAt, Valid: !apiRepo.CreatedAt.IsZero()}
	repo.PushedAt = sql.NullTime{Time: apiRepo.PushedAt, Valid: !apiRepo.PushedAt.IsZero()}
	repo.CommitOID = refTip.CommitOID.Bytes()
	repo.CommitSeqNo = sql.NullInt64{Int64: repo.CommitSeqNo.Int64 + 1, Valid: true}
	repo.DeletedAt = sql.NullTime{}

	if repoInfoState == db.RepoInfoStateNew {
		s.Repos = append(s.Repos, repo)
	}

	return &db.RepositoryResult{Repository: repo, GitHubRepository: apiRepo, RefTip: refTip}, nil
}

func (s *Store) ErroredRepositorySequence(ctx context.Context, repoID types.RepoID, deleted bool) (*db.SequenceNumbers, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	var deletedAt sql.NullTime
	if deleted {
		deletedAt = sql.NullTime{Time: time.Now(), Valid: true}
	}

	for _, repo := range s.Repos {
		if repo.RepoID == repoID {
			repo.CommitSeqNo = sql.NullInt64{Int64: repo.CommitSeqNo.Int64 + 1, Valid: true}
			repo.RepoSeqNo = sql.NullInt64{Int64: repo.RepoSeqNo.Int64, Valid: true}
			repo.DeletedAt = deletedAt
			return &db.SequenceNumbers{
				CommitSeqNo: uint64(repo.CommitSeqNo.Int64),
				RepoSeqNo:   types.RepoSeqNo(repo.RepoSeqNo.Int64),
			}, nil
		}
	}

	repo := db.NewDummyRepository(repoID)
	repo.DeletedAt = sql.NullTime{Time: time.Now(), Valid: true}
	repo.CommitSeqNo = sql.NullInt64{Int64: 1, Valid: true}
	repo.RepoSeqNo = sql.NullInt64{} // Simulates a repo that was never ingested that would have a null for `repo_seq_no` in the MySQL store.
	s.Repos = append(s.Repos, repo)

	return &db.SequenceNumbers{
			CommitSeqNo: uint64(repo.CommitSeqNo.Int64),
			RepoSeqNo:   types.RepoSeqNo(repo.RepoSeqNo.Int64),
		},
		nil
}

func (s *Store) GetCorpusState(ctx context.Context, corpus routing.Corpus) (*db.CorpusState, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	state, ok := s.corpusState[corpus]
	if !ok {
		panic(fmt.Sprintf("unknown corpus %s", corpus))
	}
	return &state, nil
}

func (s *Store) SetCorpusIngestMode(ctx context.Context, corpus routing.Corpus, from, to db.IngestMode) (bool, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	state, ok := s.corpusState[corpus]
	if !ok {
		state = db.CorpusState{Corpus: corpus, IngestMode: to}
	} else {
		if state.IngestMode+1 != to {
			return false, fmt.Errorf("cannot move from ingest mode %s to %s", state.IngestMode.String(), to.String())
		}
		state.IngestMode = to
	}
	s.corpusState[corpus] = state
	return true, nil
}

func (s *Store) CreateEpoch(ctx context.Context, corpus routing.Corpus, description string) (*db.Epoch, error) {
	logging.Info(ctx, "NOOP: creating epoch")
	s.mutex.Lock()
	defer s.mutex.Unlock()
	state, ok := s.corpusState[corpus]
	if !ok {
		return nil, errors.New("corpus not found")
	}
	state.EpochID++
	state.IngestMode = db.IngestModeBackfill
	s.corpusState[corpus] = state
	epoch := &db.Epoch{EpochID: state.EpochID, Corpus: corpus, Description: description}
	return epoch, nil
}

func (s *Store) GetEpoch(ctx context.Context, epochID types.EpochID) (*db.Epoch, error) {
	logging.Info(ctx, "NOOP: GetEpoch")
	return &db.Epoch{EpochID: epochID}, nil
}

func (s *Store) UpdateEpochDescription(ctx context.Context, epochID types.EpochID, description string) error {
	logging.Info(ctx, "NOOP: UpdateEpochDescription")
	return nil
}

func (s *Store) GetEpochEndOffsets(ctx context.Context, epochID types.EpochID) (db.EpochOffsets, error) {
	logging.Info(ctx, "NOOP: GetEpochEndOffsets")
	return db.EpochOffsets{}, nil
}

func (s *Store) SetEpochEndOffsets(ctx context.Context, epochID types.EpochID, offsets db.EpochOffsets) error {
	logging.Info(ctx, "NOOP: SetEpochEndOffsets")
	return nil
}

func (s *Store) LoadRepositories(ctx context.Context, filter repofilter.F, fn db.LoadRepoFn) error {
	for _, repo := range s.Repos {
		if !applyFilter(filter, repo) {
			continue
		}

		if cont := fn(ctx, repo); !cont {
			return nil
		}
	}

	return nil
}

func (s *Store) LoadRepositoriesInBatches(ctx context.Context, batchSize int, filter repofilter.F, fn db.LoadRepoBatchFn) error {
	_ = fn(ctx, s.Repos)
	return nil
}

func (s *Store) SuggestRepositoryNWOs(ctx context.Context, prompt string, actor *models.Actor) ([]*db.Repository, error) {
	output := []*db.Repository{}
	for _, repo := range s.Repos {
		if repo.IsDeleted() {
			continue
		}

		matchesPrompt := strings.HasPrefix(repo.Name, prompt) || strings.HasPrefix(repo.NWO(), prompt)
		if !matchesPrompt {
			continue
		}

		if repo.IsAccessibleBy(actor) {
			output = append(output, repo)
		}
	}
	return output, nil
}

func (s *Store) GetFirstRepository(ctx context.Context, filter repofilter.F) (*db.Repository, error) {
	var repo *db.Repository
	err := s.LoadRepositories(ctx, filter, func(ctx context.Context, r *db.Repository) bool {
		repo = r
		return false
	})
	if err != nil {
		return nil, err
	}

	return repo, nil
}

func (s *Store) GetRepositoryByNWO(ctx context.Context, nwo types.NWO) (*db.Repository, error) {
	var repo *db.Repository
	err := s.LoadRepositories(ctx, repofilter.And(repofilter.NotDeleted(), repofilter.NWO(nwo)), func(ctx context.Context, r *db.Repository) bool {
		repo = r
		return false
	})
	if err != nil {
		return nil, err
	}

	return repo, nil
}

func (s *Store) GetRepositoryByID(ctx context.Context, id types.RepoID) (*db.Repository, error) {
	var repo *db.Repository
	err := s.LoadRepositories(ctx, repofilter.And(repofilter.NotDeleted(), repofilter.ID(id)), func(ctx context.Context, r *db.Repository) bool {
		repo = r
		return false
	})
	if err != nil {
		return nil, err
	}

	return repo, nil
}

func (s *Store) LoadRepositoriesByIDs(ctx context.Context, repos map[types.RepoID]*db.Repository) error {
	filters := []repofilter.F{}
	for repoID := range repos {
		filters = append(filters, repofilter.ID(repoID))
	}

	err := s.LoadRepositories(ctx, repofilter.And(repofilter.NotDeleted(), repofilter.Or(filters...)), func(ctx context.Context, repo *db.Repository) bool {
		repos[repo.RepoID] = repo
		return true
	})
	if err != nil {
		return err
	}

	return nil
}

func (s *Store) RepositoryExists(ctx context.Context, repoID types.RepoID) (bool, error) {
	for _, repo := range s.Repos {
		if repo.RepoID == repoID {
			return true, nil
		}
	}
	return false, nil
}

func (s *Store) DeleteRepository(ctx context.Context, repoID types.RepoID) error {
	for _, repo := range s.Repos {
		if repo.RepoID == repoID {
			repo.DeletedAt = sql.NullTime{
				Time:  time.Now(),
				Valid: true,
			}

			return nil
		}
	}

	return nil
}

func applyFilter(filter repofilter.F, repo *db.Repository) bool {
	switch ft := filter.(type) {
	case repofilter.IsAny:
		return true
	case repofilter.AndFilter:
		for _, sub := range ft.Filters {
			if !applyFilter(sub, repo) {
				return false
			}
		}
		return true
	case repofilter.OrFilter:
		for _, sub := range ft.Filters {
			if applyFilter(sub, repo) {
				return true
			}
		}
		return false
	case repofilter.IsPublic:
		return repo.IsPublic
	case repofilter.IsDeleted:
		return repo.IsDeleted()
	case repofilter.IsNotDeleted:
		return !repo.IsDeleted()
	case repofilter.IDFilter:
		return repo.RepoID == ft.ID
	case repofilter.IDGreaterFilter:
		return repo.RepoID > ft.ID
	case repofilter.NWOFilter:
		return repo.OwnerLogin == ft.NWO.Owner().String() && repo.Name == ft.NWO.Name()
	default:
		panic(fmt.Sprintf("unexpected filter type %+v", ft))
	}
}
