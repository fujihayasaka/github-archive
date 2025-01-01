package data_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/simon-engledew/sqlh"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/slices"
)

func TestEntities(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	found := data.UpsertEntityArgs{}

	for n, args := range []data.UpsertEntityArgs{
		{
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   1,
			UserIDs:    []uint64{1},
		},
		{
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   1,
			UserIDs:    []uint64{2},
		},
		{
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   1,
			UserIDs:    []uint64{1, 2, 3},
		},
		{
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   2,
			UserIDs:    []uint64{1},
		},
		{
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   1,
			UserIDs:    []uint64{1, 2, 3},
		},
		{
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   1,
			UserIDs:    []uint64{4},
		},
		{
			EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
			EntityID:   1,
			UserIDs:    []uint64{},
		},
	} {
		t.Run(fmt.Sprintf("test-%d[%d]", n, len(args.UserIDs)), func(t *testing.T) {
			require.NoError(t, d.UpsertEntity(ctx, args))
			require.NoError(t, d.UpsertEntity(fromctx.Statter.With(ctx, expectMatch(t, "tg_entities")), args))

			require.NoError(t, db.QueryRow(`
SELECT entity_type, entity_id, user_ids
FROM tg_entities
WHERE entity_type = ? AND entity_id = ?`, args.EntityType, args.EntityID).Scan(
				&found.EntityType, &found.EntityID, sqlh.Json(&found.UserIDs),
			))

			slices.Sort(found.UserIDs)
			require.Equal(t, args, found)
		})
	}
}

func TestDeleteEntity(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	require.NoError(t, d.UpsertEntity(ctx, data.UpsertEntityArgs{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityID:   2,
		UserIDs:    []uint64{1},
	}))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_entities WHERE entity_type = ? AND entity_id = ?", "Business", 2)))

	require.NoError(t, d.DeleteEntity(ctx, 2, v1.EntityType_ENTITY_TYPE_BUSINESS))

	require.Equal(t, 0, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_purchasers WHERE entity_type = ? AND entity_id = ?", "Business", 2)))
}
