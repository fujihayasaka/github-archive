package mysql

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	throttler "github.com/github/go-freno-client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/repofilter"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_GetSetEpochDescription(t *testing.T) {
	corpus := helpers.Corpus(t)
	conn := testDB(t)

	store := New(conn, throttler.DefaultThrottler)
	ctx := context.Background()

	epoch, err := store.CreateEpoch(ctx, corpus, "test 1")
	require.NoError(t, err)
	require.Equal(t, types.EpochID(1), epoch.EpochID)
	require.Equal(t, "test 1", epoch.Description)
	require.Equal(t, corpus, epoch.Corpus)

	epoch, err = store.GetEpoch(ctx, epoch.EpochID)
	require.NoError(t, err)
	require.Equal(t, types.EpochID(1), epoch.EpochID)
	require.Equal(t, "test 1", epoch.Description)
	require.Equal(t, corpus, epoch.Corpus)

	err = store.UpdateEpochDescription(ctx, epoch.EpochID, "updated description")
	require.NoError(t, err)
	epoch, err = store.GetEpoch(ctx, epoch.EpochID)
	require.NoError(t, err)
	require.Equal(t, "updated description", epoch.Description)
}

func Test_SwitchIngestModes(t *testing.T) {
	conn := testDB(t)

	corpus := helpers.Corpus(t)
	store := New(conn, throttler.DefaultThrottler)
	ctx := context.Background()
	_, err := store.CreateEpoch(ctx, corpus, t.Name())
	require.NoError(t, err)

	modes := map[db.IngestMode]db.IngestMode{
		db.IngestModeBackfill:              db.IngestModeBackfillCatchup,
		db.IngestModeBackfillCatchup:       db.IngestModeIncrementalTransition,
		db.IngestModeIncrementalTransition: db.IngestModeIncremental,
	}

	for from, to := range modes {
		t.Run(fmt.Sprintf("%sTo%s", from.String(), to.String()), func(t *testing.T) {
			conn.MustExec("UPDATE blackbird_corpus_state SET ingest_mode=? WHERE corpus_id=?", from, corpus)

			ok, err := store.SetCorpusIngestMode(ctx, corpus, from, to)
			require.NoError(t, err)
			require.True(t, ok)

			state, err := store.GetCorpusState(ctx, corpus)
			require.NoError(t, err)
			require.Equal(t, to, state.IngestMode)
		})
	}
}

func Test_CorpusInvalidIngestModeTransition(t *testing.T) {
	conn := testDB(t)

	corpus := helpers.Corpus(t)
	store := New(conn, throttler.DefaultThrottler)
	ctx := context.Background()

	_, err := store.CreateEpoch(ctx, corpus, t.Name())
	require.NoError(t, err)

	// Invalid b/c you must go through all the states in order
	_, err = store.SetCorpusIngestMode(ctx, corpus, db.IngestModeBackfill, db.IngestModeIncrementalTransition)
	require.EqualError(t, err, "cannot move from ingest mode Backfill to IncrementalTransition")
}

func Test_CreateEpochCreatesCorpusStateAndUpdatesCache(t *testing.T) {
	// It's debatable whether CreateEpoch should create corpus state if it
	// doesn't exist. Previously, it would not update corpus state with the
	// epoch if there was no corpus state. I think this is a better
	// alternative; otherwise, it should error if the corpus state doesn't
	// exist yet.

	conn := testDB(t)

	corpus := helpers.Corpus(t)
	store := New(conn, throttler.DefaultThrottler)
	ctx := context.Background()

	// test 1: no corpus state yet, returns 0 epoch corpus state
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)
	require.Equal(t, &db.CorpusState{Corpus: corpus, EpochID: 0}, state)

	epoch, err := store.CreateEpoch(ctx, corpus, "test 1")
	require.NoError(t, err)
	require.Equal(t, types.EpochID(1), epoch.EpochID)
	require.Equal(t, "test 1", epoch.Description)
	require.Equal(t, corpus, epoch.Corpus)

	state, err = store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)
	require.Equal(t, corpus, state.Corpus)
	require.Equal(t, types.EpochID(1), state.EpochID)
	require.Equal(t, db.IngestModeBackfill, state.IngestMode)

	// test 2: updating corpus that already exists
	epoch, err = store.CreateEpoch(ctx, corpus, "test 2")
	require.NoError(t, err)
	require.Equal(t, types.EpochID(2), epoch.EpochID)
	require.Equal(t, "test 2", epoch.Description)
	require.Equal(t, corpus, epoch.Corpus)

	state, err = store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)
	require.Equal(t, corpus, state.Corpus)
	require.Equal(t, types.EpochID(2), state.EpochID)
	require.Equal(t, db.IngestModeBackfill, state.IngestMode)
}

func Test_SetEpochOffsets(t *testing.T) {
	conn := testDB(t)
	corpus := helpers.Corpus(t)
	store := New(conn, throttler.DefaultThrottler)
	ctx := context.Background()
	epoch, err := store.CreateEpoch(ctx, corpus, "test")
	require.NoError(t, err)

	offsets := db.EpochOffsets{}
	offsets.Set(1, 1)
	offsets.Set(1, 5)
	offsets.Set(2, 10)
	offsets.Set(2, 1)

	err = store.SetEpochEndOffsets(ctx, epoch.EpochID, offsets)
	require.NoError(t, err)

	offsets, err = store.GetEpochEndOffsets(ctx, epoch.EpochID)
	require.NoError(t, err)

	assert.Equal(t, int64(5), offsets[1])
	assert.Equal(t, int64(10), offsets[2])
}

func Test_LoadAllRepositories(t *testing.T) {
	conn := testDB(t)

	ctx := context.Background()

	repos := []*db.Repository{
		{
			RepoID:          1,
			OwnerID:         1,
			OwnerLogin:      "github",
			Name:            "linguist",
			IsPublic:        true,
			IsArchived:      true,
			PushedAt:        sql.NullTime{Time: time.Date(2022, time.January, 1, 0, 0, 0, 0, time.UTC), Valid: true},
			CreatedAt:       sql.NullTime{Time: time.Date(2021, time.January, 1, 0, 0, 0, 0, time.UTC), Valid: true},
			HasLicense:      sql.NullBool{Bool: true, Valid: true},
			NumWatchers:     sql.NullInt32{Int32: 100, Valid: true},
			NumStars:        sql.NullInt32{Int32: 5, Valid: true},
			HasReadme:       sql.NullBool{Bool: true, Valid: true},
			PublicForkCount: sql.NullInt32{Int32: 0, Valid: true},
		},
		{
			RepoID:     2,
			OwnerID:    1,
			OwnerLogin: "github",
			Name:       "blackbird-mw",
			IsPublic:   false,
		},
		{
			RepoID:      3,
			OwnerID:     2,
			OwnerLogin:  "apache",
			Name:        "http",
			IsPublic:    true,
			SourceTopic: sql.NullString{String: "foo", Valid: true},
		},
		{
			RepoID:      4,
			OwnerID:     2,
			OwnerLogin:  "apache",
			Name:        "lucene",
			IsPublic:    true,
			SourceTopic: sql.NullString{String: "foo", Valid: true},
			DeletedAt:   helpers.GetNullTime(t, "2021-01-01T00:00:00Z"),
		},
	}

	helpers.InsertRepositories(t, conn, repos...)

	repos[3].DeletedAt = sql.NullTime{Time: repos[3].DeletedAt.Time, Valid: true}

	out := map[types.RepoID]db.Repository{}
	expected := map[types.RepoID]db.Repository{
		repos[0].RepoID: *repos[0],
		repos[1].RepoID: *repos[1],
		repos[2].RepoID: *repos[2],
		repos[3].RepoID: *repos[3],
	}

	store := New(conn, throttler.DefaultThrottler)
	err := store.LoadRepositories(ctx, repofilter.Any(), func(ctx context.Context, repo *db.Repository) bool {
		out[repo.RepoID] = *repo
		return true
	})
	require.NoError(t, err)
	require.Equal(t, expected, out)

	out = map[types.RepoID]db.Repository{}
	expected = map[types.RepoID]db.Repository{
		repos[3].RepoID: *repos[3],
	}

	err = store.LoadRepositories(ctx, repofilter.Deleted(), func(ctx context.Context, repo *db.Repository) bool {
		out[repo.RepoID] = *repo
		return true
	})
	require.NoError(t, err)
	require.Equal(t, expected, out, "expected only one repo was deleted")
}

func Test_LoadAllRepositoriesInBatches(t *testing.T) {
	conn := testDB(t)

	ctx := context.Background()

	repos := []*db.Repository{
		{
			RepoID:     1,
			OwnerID:    1,
			OwnerLogin: "github",
			Name:       "linguist",
			IsPublic:   true,
		},
		{
			RepoID:     2,
			OwnerID:    1,
			OwnerLogin: "github",
			Name:       "blackbird-mw",
			IsPublic:   false,
		},
		{
			RepoID:          3,
			OwnerID:         2,
			OwnerLogin:      "apache",
			Name:            "http",
			IsPublic:        true,
			SourceTopic:     sql.NullString{String: "foo", Valid: true},
			IsArchived:      false,
			PushedAt:        sql.NullTime{Time: time.Date(2022, time.January, 1, 0, 0, 0, 0, time.UTC), Valid: true},
			CreatedAt:       sql.NullTime{Time: time.Date(2021, time.January, 1, 0, 0, 0, 0, time.UTC), Valid: true},
			HasLicense:      sql.NullBool{Bool: true, Valid: true},
			NumWatchers:     sql.NullInt32{Int32: 1, Valid: true},
			NumStars:        sql.NullInt32{Int32: 1, Valid: true},
			HasReadme:       sql.NullBool{Bool: false, Valid: true},
			PublicForkCount: sql.NullInt32{Int32: 0, Valid: true},
		},
	}

	helpers.InsertRepositories(t, conn, repos...)

	out := map[types.RepoID]db.Repository{}
	expected := map[types.RepoID]db.Repository{
		repos[0].RepoID: *repos[0],
		repos[1].RepoID: *repos[1],
		repos[2].RepoID: *repos[2],
	}

	store := New(conn, throttler.DefaultThrottler)
	// batch size = 2 => requires two queries to finish
	err := store.LoadRepositoriesInBatches(ctx, 2, repofilter.Any(), func(ctx context.Context, repos []*db.Repository) bool {
		for _, repo := range repos {
			out[repo.RepoID] = *repo
		}
		return true
	})
	require.NoError(t, err)
	require.Equal(t, expected, out)
}

func Test_DeleteRepository(t *testing.T) {
	conn := testDB(t)

	ctx := context.Background()
	store := New(conn, throttler.DefaultThrottler)

	repo := helpers.Repositories(t, 1)[0]
	helpers.InsertRepositories(t, conn, repo)

	err := store.DeleteRepository(ctx, repo.RepoID)
	require.NoError(t, err)

	reloaded, err := store.GetRepositoryByNWO(ctx, types.NWOFromString(repo.NWO()))
	require.NoError(t, err)
	require.Nil(t, reloaded)
}

func Test_RepoScore(t *testing.T) {
	conn := testDB(t)

	ctx := context.Background()
	repo := helpers.Repositories(t, 1)[0]
	store := New(conn, throttler.DefaultThrottler)

	// Insert a repo with no repo score-related fields
	_, err := conn.Exec(
		"INSERT INTO blackbird_repositories (id, owner_id, owner_login, name, is_public) VALUES (?, ?, ?, ?, ?)",
		repo.RepoID,
		repo.OwnerID,
		repo.OwnerLogin,
		repo.Name,
		repo.IsPublic,
	)
	require.NoError(t, err)

	storeRepo, err := store.GetRepositoryByID(ctx, repo.RepoID)
	require.NoError(t, err)
	require.Equal(t, float32(db.RepoScoreAjustment), storeRepo.RepoScore(), "repo doesn't have expected default score")

	q := `
UPDATE blackbird_repositories
SET is_archived=?, pushed_at=?, created_at=?, has_license=?, num_watchers=?, num_stars=?, has_readme=?, public_fork_count=?
WHERE id=?
`
	_, err = conn.Exec(q, repo.IsArchived, time.Date(2022, time.January, 1, 0, 0, 0, 0, time.UTC), time.Date(2012, time.January, 1, 0, 0, 0, 0, time.UTC), true, 1_000, 10_000, true, 500, repo.RepoID)
	require.NoError(t, err)

	storeRepo, err = store.GetRepositoryByID(ctx, repo.RepoID)
	require.NoError(t, err)
	require.InDelta(t, -864.6503, storeRepo.RepoScore(), 0.01, "Expected: 10 + 100 + 200 + (100 * log2(1000)) + (100 * log2(10,000)) - 3500")
}

func Test_GetRepositoryByID(t *testing.T) {
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	ctx := context.Background()

	repo, err := store.GetRepositoryByID(ctx, helpers.RepoID(t))
	require.NoError(t, err)
	require.Nil(t, repo)
}
