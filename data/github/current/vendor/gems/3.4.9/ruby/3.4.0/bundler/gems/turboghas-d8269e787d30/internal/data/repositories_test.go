package data_test

import (
	"testing"

	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"

	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/stretchr/testify/require"
)

func TestUpsertRepository(t *testing.T) {
	ctx := t.Context()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	var found data.UpsertRepositoryArgs

	for _, args := range []data.UpsertRepositoryArgs{
		{
			RepositoryID: 1,
			OwnerID:      1,
			Name:         "test",
			Enabled:      data.Feature(v1.Feature_FEATURE_ALL),
		},
		{
			RepositoryID: 1,
			OwnerID:      1,
			Name:         "Test-Update",
			Enabled:      data.Feature(v1.Feature_FEATURE_NONE),
		},
		{
			RepositoryID: 1,
			OwnerID:      1,
			Name:         "test-update",
			Enabled:      data.Feature(v1.Feature_FEATURE_NONE),
		},
		{
			RepositoryID: 1,
			OwnerID:      1,
			Name:         "test-update",
			Enabled:      data.Feature(v1.Feature_FEATURE_NONE),
		},
	} {
		require.NoError(t, d.UpsertRepository(ctx, args))
		require.NoError(t, d.UpsertRepository(fromctx.Statter.With(ctx, expectMatch(t, "tg_repositories")), args))
		require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories")))
		require.NoError(t, db.QueryRow("SELECT repository_id, owner_id, name, enabled FROM tg_repositories").Scan(
			&found.RepositoryID, &found.OwnerID, &found.Name, &found.Enabled,
		))
		require.Equal(t, args, found)
	}
}

func TestDeleteRepository(t *testing.T) {
	ctx := t.Context()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	require.NoError(t, d.UpsertRepository(ctx, data.UpsertRepositoryArgs{
		RepositoryID: 1,
		OwnerID:      1,
		Name:         "test",
		Enabled:      data.Feature(v1.Feature_FEATURE_ALL),
	}))
	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories")))

	require.NoError(t, d.DeleteRepository(ctx, 1))

	require.Equal(t, 0, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories")))

	require.NoError(t, d.UpsertRepository(ctx, data.UpsertRepositoryArgs{
		RepositoryID: 1,
		OwnerID:      1,
		Name:         "test",
		Enabled:      data.Feature(v1.Feature_FEATURE_ALL),
	}))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories")))
}

func TestUpdateRepository(t *testing.T) {
	ctx := t.Context()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	require.NoError(t, d.UpsertRepository(ctx, data.UpsertRepositoryArgs{
		RepositoryID: 1,
		OwnerID:      1,
		Name:         "test",
		Enabled:      data.Feature(v1.Feature_FEATURE_ALL),
	}))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories WHERE name = ?", "test")))

	require.NoError(t, d.UpsertRepository(ctx, data.UpsertRepositoryArgs{
		RepositoryID: 1,
		OwnerID:      1,
		Name:         "test-rename",
		Enabled:      data.Feature(v1.Feature_FEATURE_ALL),
	}))

	require.Equal(t, 0, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories WHERE name = ?", "test")))
	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories WHERE name = ?", "test-rename")))

	require.NoError(t, d.UpsertRepository(ctx, data.UpsertRepositoryArgs{
		RepositoryID: 1,
		OwnerID:      2,
		Name:         "test-rename",
		Enabled:      data.Feature(v1.Feature_FEATURE_ALL),
	}))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_repositories WHERE owner_id = ?", 2)))
}
