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

func TestPurchasers(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	var found data.UpsertPurchaserArgs

	for _, args := range []data.UpsertPurchaserArgs{
		{
			OwnerID:    1,
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   1,
		},
		{
			OwnerID:    1,
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   2,
		},
	} {
		require.NoError(t, d.UpsertPurchaser(ctx, args))
		require.NoError(t, d.UpsertPurchaser(fromctx.Statter.With(ctx, expectMatch(t, "tg_purchasers")), args))
		require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_purchasers")))
		require.NoError(t, db.QueryRow("SELECT owner_id, entity_type, entity_id FROM tg_purchasers").Scan(
			&found.OwnerID, &found.EntityType, &found.EntityID,
		))
		require.Equal(t, args, found)
	}
}

func TestDeletePurchaser(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	require.NoError(t, d.UpsertPurchaser(ctx, data.UpsertPurchaserArgs{
		OwnerID:    1,
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityID:   2,
	}))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_purchasers WHERE owner_id = ?", 1)))

	require.NoError(t, d.DeletePurchaser(ctx, 1))

	require.Equal(t, 0, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_purchasers WHERE owner_id = ?", 1)))
}
