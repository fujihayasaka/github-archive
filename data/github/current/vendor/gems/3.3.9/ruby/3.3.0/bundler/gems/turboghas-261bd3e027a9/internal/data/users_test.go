package data_test

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/stretchr/testify/require"
)

func TestUpsertUser(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	var found data.UpsertUserArgs

	for _, args := range []data.UpsertUserArgs{
		{
			UserID: 1,
			Login:  "test",
			Type:   v1.UserType_USER_TYPE_USER,
		},
		{
			UserID: 1,
			Login:  "test-update",
			Type:   v1.UserType_USER_TYPE_USER,
		},
		{
			UserID: 1,
			Login:  "Test-Update",
			Type:   v1.UserType_USER_TYPE_USER,
		},
	} {
		require.NoError(t, d.UpsertUser(ctx, args))
		require.NoError(t, d.UpsertUser(fromctx.Statter.With(ctx, expectMatch(t, "tg_users")), args))
		require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_users")))
		require.NoError(t, db.QueryRow("SELECT user_id, login, type FROM tg_users").Scan(
			&found.UserID, &found.Login, &found.Type,
		))
		require.Equal(t, args, found)
	}
}

func TestDeleteUser(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	require.NoError(t, d.UpsertUser(ctx, data.UpsertUserArgs{
		UserID: 1,
		Login:  "before",
		Type:   v1.UserType_USER_TYPE_USER,
	}))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_users WHERE login = ?", "before")))

	require.NoError(t, d.DeleteUser(ctx, 1))

	require.Equal(t, 0, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_users WHERE login = ?", "before")))
}
