package repository_test

import (
	"context"
	"database/sql"
	"encoding/binary"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/transforms"
)

var stableIDcounter = 0

func newStableID() []byte {
	stableIDcounter++
	stableID := make([]byte, 8)
	binary.BigEndian.PutUint64(stableID, uint64(stableIDcounter))
	return stableID
}

func TestRepositoryUpdate(t *testing.T) {
	db := dbtest.RequireConnection(t)
	r := repository.NewService(db)
	ctx := context.Background()

	repoID := ts.RepositoryEID(1)

	expected := &ts.Repository{
		RepositoryID:        repoID,
		OwnerID:             1,
		CodeScanningEnabled: false,
		SourceUpdatedAt:     sqltime.Time{Time: time.UnixMicro(1).UTC()},
		DefaultRef:          []byte("r1"),
		Visibility:          sql.NullString{Valid: false},
	}

	// First read should be nil
	actual, err := r.Find(ctx, repoID)
	require.NoError(t, err)
	require.Nil(t, actual)

	// First write
	err = r.Update(ctx, expected)
	require.NoError(t, err)

	// Second read should return the actual data
	actual, err = r.Find(ctx, repoID)
	require.NoError(t, err)
	require.NotNil(t, actual)
	requireRepositoryEqual(t, expected, actual)

	// Update fields and write
	expected = &ts.Repository{
		RepositoryID:        repoID,
		OwnerID:             2,
		CodeScanningEnabled: true,
		SourceUpdatedAt:     sqltime.Time{Time: time.UnixMicro(2).UTC()},
		DefaultRef:          []byte("r2"),
		Visibility:          sql.NullString{String: "private", Valid: true},
	}
	err = r.Update(ctx, expected)
	require.NoError(t, err)

	// Assert that the fields got actually updated
	actual, err = r.Find(ctx, repoID)
	require.NoError(t, err)
	require.NotNil(t, actual)
	requireRepositoryEqual(t, expected, actual)
}

// requireRepositoryEqual asserts equality on the fields that are not
// written by the database (e.g. it doesnt consider the ID field)
func requireRepositoryEqual(t *testing.T, expected, actual *ts.Repository) {
	t.Helper()

	require.Equal(t, expected.RepositoryID, actual.RepositoryID)
	require.Equal(t, expected.OwnerID, actual.OwnerID)
	require.Equal(t, expected.CodeScanningEnabled, actual.CodeScanningEnabled)
	require.Equal(t, expected.SourceUpdatedAt, actual.SourceUpdatedAt)
	require.Equal(t, expected.DefaultRef, actual.DefaultRef)
}

func TestReposToIndex(t *testing.T) {
	db := dbtest.RequireConnection(t)
	r := repository.NewService(db)
	ctx := context.Background()

	// There is nothing in the DB, this should return 0
	repos, err := r.ReposToIndex(ctx, nil, 100)
	require.NoError(t, err)
	require.Len(t, repos, 0)

	count, err := r.CountReposToIndex(ctx, nil)
	require.NoError(t, err)
	require.Equal(t, uint(0), count)

	now := time.Now()

	// repo 1 has both analyses and metadata
	dbtest.RequireCreate(t, db, &ts.Analysis{
		ID:                 1,
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/master"),
	})
	dbtest.RequireCreate(t, db, &ts.Analysis{
		ID:                 2,
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/master"),
	})
	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:    1,
		SourceUpdatedAt: sqltime.Time{Time: now},
		DefaultRef:      []byte("main"),
	})

	// repo 2 has just metadata
	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:    2,
		SourceUpdatedAt: sqltime.Time{Time: now},
		DefaultRef:      []byte("main"),
		LastIndexedAt:   sql.NullTime{Valid: true, Time: now.Add(-time.Hour * 6)},
	})

	// repo 3 has just an analysis
	dbtest.RequireCreate(t, db, &ts.Analysis{
		ID:                 3,
		RepositoryID:       3,
		SourceRepositoryID: 3,
		Ref:                []byte("refs/heads/master"),
	})

	// We only expect repo1 and repo2 to be returned
	repos, err = r.ReposToIndex(ctx, nil, 100)
	ids := transforms.Map(repos, func(r *ts.Repository) ts.RepositoryEID {
		return r.RepositoryID
	})
	require.NoError(t, err)
	require.Len(t, ids, 2)
	require.Contains(t, ids, ts.RepositoryEID(1))
	require.Contains(t, ids, ts.RepositoryEID(2))

	count, err = r.CountReposToIndex(ctx, nil)
	require.NoError(t, err)
	require.Equal(t, uint(2), count)

	// with an earlier cutoff, only repo 1 should be returned, since it has last_indexed_at = NULL
	yesterday := now.Add(-time.Hour * 24)
	repos, err = r.ReposToIndex(ctx, &yesterday, 100)
	ids = transforms.Map(repos, func(r *ts.Repository) ts.RepositoryEID {
		return r.RepositoryID
	})
	require.NoError(t, err)
	require.Len(t, ids, 1)
	require.Equal(t, ts.RepositoryEID(1), ids[0])

	count, err = r.CountReposToIndex(ctx, &yesterday)
	require.NoError(t, err)
	require.Equal(t, uint(1), count)
}

func TestActiveRepos(t *testing.T) {
	db := dbtest.RequireConnection(t)
	r := repository.NewService(db)
	ctx := context.Background()

	// There is nothing in the DB, this should return 0
	ids, err := r.ActiveRepos(ctx, nil, 0, 100)
	require.NoError(t, err)
	require.Len(t, ids, 0)

	now := sqltime.Now()
	lastWeek := sqltime.Time{Time: now.Add(-7 * 24 * time.Hour)}

	dbtest.RequireCreate(t, db, &ts.LogicalAlert{
		RepositoryID:          1,
		Number:                1,
		StableAlertIdentifier: newStableID(),
		BaseModel: ts.BaseModel{
			UpdatedAt: now,
		},
	})
	dbtest.RequireCreate(t, db, &ts.LogicalAlert{
		RepositoryID:          1,
		Number:                2,
		StableAlertIdentifier: newStableID(),
		BaseModel: ts.BaseModel{
			UpdatedAt: lastWeek,
		},
	})

	dbtest.RequireCreate(t, db, &ts.LogicalAlert{
		RepositoryID:          2,
		Number:                1,
		StableAlertIdentifier: newStableID(),
		BaseModel: ts.BaseModel{
			UpdatedAt: now,
		},
	})
	dbtest.RequireCreate(t, db, &ts.LogicalAlert{
		RepositoryID:          3,
		Number:                1,
		StableAlertIdentifier: newStableID(),
		BaseModel: ts.BaseModel{
			UpdatedAt: lastWeek,
		},
	})

	ids, err = r.ActiveRepos(ctx, nil, 0, 100)
	require.NoError(t, err)
	require.Len(t, ids, 3)

	yesterday := now.Add(-24 * time.Hour)
	ids, err = r.ActiveRepos(ctx, &yesterday, 0, 100)
	require.NoError(t, err)
	require.Len(t, ids, 2)
	require.Contains(t, ids, ts.RepositoryEID(1))
	require.Contains(t, ids, ts.RepositoryEID(2))
}

func TestDisabledRepos(t *testing.T) {
	db := dbtest.RequireConnection(t)
	r := repository.NewService(db)
	ctx := context.Background()

	// There is nothing in the DB, this should return 0
	ids, err := r.DisabledRepos(ctx, nil, 0, 100)
	require.NoError(t, err)
	require.Len(t, ids, 0)

	now := time.Now()
	oneYearAgo := now.Add(-365 * 24 * time.Hour)

	// repo1 has recent metadata and no analyses
	repo1 := &ts.Repository{
		RepositoryID:    1,
		DefaultRef:      []byte("main"),
		SourceUpdatedAt: sqltime.Time{Time: now},
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: now},
		},
	}
	dbtest.RequireCreate(t, db, repo1)

	// repo2 has old metadata and no analyses
	repo2 := &ts.Repository{
		RepositoryID:    2,
		DefaultRef:      []byte("main"),
		SourceUpdatedAt: sqltime.Time{Time: now},
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: oneYearAgo},
		},
	}
	dbtest.RequireCreate(t, db, repo2)

	// repo3 has old metadata and an analysis
	repo3 := &ts.Repository{
		RepositoryID:    3,
		DefaultRef:      []byte("main"),
		SourceUpdatedAt: sqltime.Time{Time: now},
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: oneYearAgo},
		},
	}
	dbtest.RequireCreate(t, db, repo3)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		ID:                 1,
		RepositoryID:       3,
		SourceRepositoryID: 3,
		Ref:                []byte("refs/heads/master"),
	})

	// only repo1 and repo2 should be returned when no cutoff is specified
	ids, err = r.DisabledRepos(ctx, nil, 0, 3)
	require.NoError(t, err)
	require.Len(t, ids, 2)
	require.Contains(t, ids, ts.RepositoryEID(1))
	require.Contains(t, ids, ts.RepositoryEID(2))

	// the start should be taken into account
	ids, err = r.DisabledRepos(ctx, nil, 2, 3)
	require.NoError(t, err)
	require.Len(t, ids, 1)
	require.Equal(t, ts.RepositoryEID(2), ids[0])

	// with an earlier cutoff, only repo 2 should be returned
	lastMonth := now.Add(-30 * 24 * time.Hour)
	ids, err = r.DisabledRepos(ctx, &lastMonth, 1, 3)
	require.NoError(t, err)
	require.Len(t, ids, 1)
	require.Equal(t, ts.RepositoryEID(2), ids[0])
}

func TestDisabledReposBatch(t *testing.T) {
	db := dbtest.RequireConnection(t)
	r := repository.NewService(db)
	ctx := context.Background()

	// There is nothing in the DB, this should return 0
	ids := []ts.RepositoryEID{}
	err := r.DisabledReposBatch(ctx, nil, 1, func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error {
		ids = append(ids, repositoryIDs...)
		return nil
	})
	require.NoError(t, err)
	require.Len(t, ids, 0)

	now := time.Now()
	oneYearAgo := now.Add(-365 * 24 * time.Hour)

	// repo1 has recent metadata and no analyses
	repo1 := &ts.Repository{
		RepositoryID:    1,
		DefaultRef:      []byte("main"),
		SourceUpdatedAt: sqltime.Time{Time: now},
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: now},
		},
	}
	dbtest.RequireCreate(t, db, repo1)

	// repo2 has old metadata and no analyses
	repo2 := &ts.Repository{
		RepositoryID:    2,
		DefaultRef:      []byte("main"),
		SourceUpdatedAt: sqltime.Time{Time: now},
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: oneYearAgo},
		},
	}
	dbtest.RequireCreate(t, db, repo2)

	// repo3 has old metadata and an analysis
	repo3 := &ts.Repository{
		RepositoryID:    3,
		DefaultRef:      []byte("main"),
		SourceUpdatedAt: sqltime.Time{Time: now},
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: oneYearAgo},
		},
	}
	dbtest.RequireCreate(t, db, repo3)
	dbtest.RequireCreate(t, db, &ts.Analysis{
		ID:                 1,
		RepositoryID:       3,
		SourceRepositoryID: 3,
		Ref:                []byte("refs/heads/master"),
	})

	// only repo1 and repo2 should be returned when no cutoff is specified
	ids = []ts.RepositoryEID{}
	var count int
	err = r.DisabledReposBatch(ctx, nil, 1, func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error {
		ids = append(ids, repositoryIDs...)
		count++
		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 2, count)
	require.Len(t, ids, 2)
	require.Contains(t, ids, ts.RepositoryEID(1))
	require.Contains(t, ids, ts.RepositoryEID(2))

	// the step should be taken into account
	ids = []ts.RepositoryEID{}
	count = 0
	err = r.DisabledReposBatch(ctx, nil, 100, func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error {
		ids = append(ids, repositoryIDs...)
		count++
		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 1, count)
	require.Len(t, ids, 2)
	require.Contains(t, ids, ts.RepositoryEID(1))
	require.Contains(t, ids, ts.RepositoryEID(2))

	// with an earlier cutoff, only repo 2 should be returned
	lastMonth := now.Add(-30 * 24 * time.Hour)
	ids = []ts.RepositoryEID{}
	count = 0
	err = r.DisabledReposBatch(ctx, &lastMonth, 100, func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error {
		ids = append(ids, repositoryIDs...)
		count++
		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 1, count)
	require.Len(t, ids, 1)
	require.Equal(t, ts.RepositoryEID(2), ids[0])
}

func TestDelete(t *testing.T) {
	db := dbtest.RequireConnection(t)
	r := repository.NewService(db)
	ctx := context.Background()

	now := time.Now()

	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:    1,
		SourceUpdatedAt: sqltime.Time{Time: now},
		DefaultRef:      []byte("main"),
	})
	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:    2,
		SourceUpdatedAt: sqltime.Time{Time: now},
		DefaultRef:      []byte("main"),
	})
	dbtest.RequireCreate(t, db, &ts.Repository{
		RepositoryID:    3,
		SourceUpdatedAt: sqltime.Time{Time: now},
		DefaultRef:      []byte("main"),
	})

	// call should not fail when no ids are specified
	err := r.Delete(ctx, []ts.RepositoryEID{})
	require.NoError(t, err)

	var repos []*ts.Repository
	err = db.Where("repository_id IN (1, 2, 3)").Find(&repos).Error
	require.NoError(t, err)
	require.Len(t, repos, 3)

	err = r.Delete(ctx, []ts.RepositoryEID{2, 3})
	require.NoError(t, err)

	err = db.Where("repository_id IN (1, 2, 3)").Find(&repos).Error
	require.NoError(t, err)
	require.Len(t, repos, 1)
	require.Equal(t, ts.RepositoryEID(1), repos[0].RepositoryID)
}
